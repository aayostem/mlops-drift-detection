#!/bin/bash

set -e

VERSION=${1:-latest}
CANARY_PERCENTAGE=${2:-10}

echo "🚀 Starting canary deployment of version $VERSION with $CANARY_PERCENTAGE% traffic"

# Update the canary deployment with new version
kubectl set image deployment/ml-model-api-canary \
  model-api=123456789.dkr.ecr.us-west-2.amazonaws.com/ml-platform:$VERSION \
  -n ml-platform

# Wait for canary to be ready
kubectl rollout status deployment/ml-model-api-canary -n ml-platform --timeout=300s

# Gradually shift traffic to canary
for percentage in 10 25 50 75 100; do
    echo "🔄 Shifting $percentage% traffic to canary..."
    
    # Update Istio VirtualService
    kubectl patch virtualservice ml-model-api -n ml-platform --type=merge -p "
    spec:
      http:
      - route:
        - destination:
            host: ml-model-api-service.ml-platform.svc.cluster.local
            subset: stable
          weight: $((100 - percentage))
        - destination:
            host: ml-model-api-service.ml-platform.svc.cluster.local
            subset: canary
          weight: $percentage
    "
    
    # Wait for metrics to stabilize
    echo "⏳ Waiting for metrics to stabilize at $percentage%..."
    sleep 60
    
    # Check metrics and error rates
    ERROR_RATE=$(kubectl exec -n monitoring deploy/prometheus -- \
      curl -s "http://localhost:9090/api/v1/query?query=rate(http_requests_total{status=~\"5..\",pod=~\"ml-model-api-canary.*\"}[1m])" | \
      jq -r '.data.result[0].value[1] // 0')
    
    echo "📊 Current error rate: $ERROR_RATE"
    
    # If error rate is too high, rollback
    if (( $(echo "$ERROR_RATE > 0.05" | bc -l) )); then
        echo "❌ Error rate too high, rolling back..."
        kubectl patch virtualservice ml-model-api -n ml-platform --type=merge -p "
        spec:
          http:
          - route:
            - destination:
                host: ml-model-api-service.ml-platform.svc.cluster.local
                subset: stable
              weight: 100
            - destination:
                host: ml-model-api-service.ml-platform.svc.cluster.local
                subset: canary
              weight: 0
        "
        exit 1
    fi
done

echo "✅ Canary deployment completed successfully!"

# Promote canary to stable
echo "🎯 Promoting canary to stable..."
kubectl set image deployment/ml-model-api-stable \
  model-api=123456789.dkr.ecr.us-west-2.amazonaws.com/ml-platform:$VERSION \
  -n ml-platform

kubectl rollout status deployment/ml-model-api-stable -n ml-platform --timeout=300s

# Clean up canary
kubectl patch virtualservice ml-model-api -n ml-platform --type=merge -p "
spec:
  http:
  - route:
    - destination:
        host: ml-model-api-service.ml-platform.svc.cluster.local
        subset: stable
      weight: 100
    - destination:
        host: ml-model-api-service.ml-platform.svc.cluster.local
        subset: canary
      weight: 0
"

echo "🎉 Deployment completed successfully! Version $VERSION is now live."