#!/bin/bash

set -e

MODEL_NAME=$1
NEW_VERSION=$2
STRATEGY=${3:-linear}  # linear, exponential, manual
MAX_TRAFFIC=${4:-100}
DURATION_MINUTES=${5:-60}

echo "🚀 Starting advanced canary deployment for $MODEL_NAME version $NEW_VERSION"

# Validate inputs
if [[ -z "$MODEL_NAME" || -z "$NEW_VERSION" ]]; then
    echo "Usage: $0 <model_name> <new_version> [strategy] [max_traffic] [duration_minutes]"
    exit 1
fi

# Deployment configuration
DEPLOYMENT_NAME="$MODEL_NAME-deployment"
CANARY_DEPLOYMENT_NAME="$MODEL_NAME-canary"
NAMESPACE="ml-platform"
INTERVAL_SECONDS=300  # 5 minutes between traffic shifts
STEPS=$((DURATION_MINUTES * 60 / INTERVAL_SECONDS))

# Create canary deployment
echo "🔧 Creating canary deployment..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $CANARY_DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    app: $MODEL_NAME
    version: canary
    track: canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $MODEL_NAME
      version: canary
  template:
    metadata:
      labels:
        app: $MODEL_NAME
        version: canary
        track: canary
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: model-serving
        image: 123456789.dkr.ecr.us-west-2.amazonaws.com/$MODEL_NAME:$NEW_VERSION
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        env:
        - name: MODEL_NAME
          value: "$MODEL_NAME"
        - name: VERSION
          value: "$NEW_VERSION"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

# Wait for canary to be ready
echo "⏳ Waiting for canary deployment to be ready..."
kubectl rollout status deployment/$CANARY_DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s

# Initialize traffic shifting
echo "🔄 Starting traffic shifting with $STRATEGY strategy..."

case $STRATEGY in
    "linear")
        echo "📈 Using linear traffic shifting..."
        for ((i=1; i<=STEPS; i++)); do
            PERCENTAGE=$((i * MAX_TRAFFIC / STEPS))
            echo "Shifting $PERCENTAGE% traffic to canary..."
            shift_traffic $PERCENTAGE
            sleep $INTERVAL_SECONDS
            check_canary_health $PERCENTAGE
        done
        ;;
        
    "exponential")
        echo "🚀 Using exponential traffic shifting..."
        PERCENTAGE=5
        while [ $PERCENTAGE -le $MAX_TRAFFIC ]; do
            echo "Shifting $PERCENTAGE% traffic to canary..."
            shift_traffic $PERCENTAGE
            sleep $INTERVAL_SECONDS
            check_canary_health $PERCENTAGE
            PERCENTAGE=$((PERCENTAGE * 2))
            if [ $PERCENTAGE -gt $MAX_TRAFFIC ]; then
                PERCENTAGE=$MAX_TRAFFIC
            fi
        done
        ;;
        
    "manual")
        echo "👤 Using manual traffic shifting..."
        echo "Current traffic split:"
        get_traffic_split
        echo "Use 'shift_traffic <percentage>' to adjust traffic"
        echo "Use 'check_canary_health' to monitor canary health"
        echo "Use 'promote_canary' to complete deployment"
        return 0
        ;;
esac

# Promote canary to stable
echo "🎯 Promoting canary to stable..."
promote_canary

echo "✅ Advanced canary deployment completed successfully!"

# Helper functions
shift_traffic() {
    local percentage=$1
    kubectl patch virtualservice $MODEL_NAME -n $NAMESPACE --type=merge -p "
    spec:
      http:
      - route:
        - destination:
            host: $MODEL_NAME-service
            subset: stable
          weight: $((100 - percentage))
        - destination:
            host: $MODEL_NAME-service
            subset: canary
          weight: $percentage
    "
}

check_canary_health() {
    local percentage=$1
    
    # Check error rate
    ERROR_RATE=$(get_error_rate)
    echo "📊 Canary error rate: ${ERROR_RATE}%"
    
    # Check latency
    LATENCY=$(get_p95_latency)
    echo "⏱️  Canary P95 latency: ${LATENCY}ms"
    
    # Check drift score
    DRIFT_SCORE=$(get_drift_score)
    echo "🎯 Canary drift score: ${DRIFT_SCORE}"
    
    # Rollback if thresholds exceeded
    if (( $(echo "$ERROR_RATE > 5" | bc -l) )); then
        echo "❌ Error rate too high, rolling back..."
        rollback_deployment
        exit 1
    fi
    
    if (( $(echo "$LATENCY > 1000" | bc -l) )); then
        echo "❌ Latency too high, rolling back..."
        rollback_deployment
        exit 1
    fi
    
    if (( $(echo "$DRIFT_SCORE > 0.8" | bc -l) )); then
        echo "❌ Drift score too high, rolling back..."
        rollback_deployment
        exit 1
    fi
}

get_error_rate() {
    kubectl exec -n monitoring deploy/prometheus -- \
        curl -s "http://localhost:9090/api/v1/query?query=rate(http_requests_total{status=~\"5..\",pod=~\"$CANARY_DEPLOYMENT_NAME.*\"}[1m])" | \
        jq -r '.data.result[0].value[1] // 0' | bc -l
}

get_p95_latency() {
    kubectl exec -n monitoring deploy/prometheus -- \
        curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.95, rate(model_inference_duration_seconds_bucket{pod=~\"$CANARY_DEPLOYMENT_NAME.*\"}[1m]))" | \
        jq -r '.data.result[0].value[1] // 0' | bc -l
}

get_drift_score() {
    kubectl exec -n monitoring deploy/prometheus -- \
        curl -s "http://localhost:9090/api/v1/query?query=drift_score{model=\"$MODEL_NAME\"}" | \
        jq -r '.data.result[0].value[1] // 0' | bc -l
}

rollback_deployment() {
    echo "🔄 Rolling back deployment..."
    kubectl patch virtualservice $MODEL_NAME -n $NAMESPACE --type=merge -p "
    spec:
      http:
      - route:
        - destination:
            host: $MODEL_NAME-service
            subset: stable
          weight: 100
        - destination:
            host: $MODEL_NAME-service
            subset: canary
          weight: 0
    "
    kubectl delete deployment $CANARY_DEPLOYMENT_NAME -n $NAMESPACE
}

promote_canary() {
    # Update stable deployment
    kubectl set image deployment/$DEPLOYMENT_NAME \
        model-serving=123456789.dkr.ecr.us-west-2.amazonaws.com/$MODEL_NAME:$NEW_VERSION \
        -n $NAMESPACE
    
    kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s
    
    # Remove canary
    kubectl patch virtualservice $MODEL_NAME -n $NAMESPACE --type=merge -p "
    spec:
      http:
      - route:
        - destination:
            host: $MODEL_NAME-service
            subset: stable
          weight: 100
    "
    
    kubectl delete deployment $CANARY_DEPLOYMENT_NAME -n $NAMESPACE
    
    echo "✅ Canary promoted to stable successfully!"
}

get_traffic_split() {
    kubectl get virtualservice $MODEL_NAME -n $NAMESPACE -o json | \
        jq '.spec.http[0].route[] | {subset: .destination.subset, weight: .weight}'
}