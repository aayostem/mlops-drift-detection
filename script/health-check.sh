#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
TIMEOUT=300
INTERVAL=10

echo "🏥 Running Health Checks for $ENVIRONMENT environment..."
echo ""

# Load environment configuration
source ./config/environments/${ENVIRONMENT}.env

check_k8s_cluster() {
    echo "🔍 Checking Kubernetes cluster..."
    
    # Check cluster connectivity
    if ! kubectl cluster-info > /dev/null 2>&1; then
        echo "❌ Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    # Check node status
    UNREADY_NODES=$(kubectl get nodes --no-headers | grep -c "NotReady" || true)
    if [ "$UNREADY_NODES" -gt 0 ]; then
        echo "❌ $UNREADY_NODES nodes are not ready"
        return 1
    fi
    
    echo "✅ Kubernetes cluster is healthy"
    return 0
}

check_namespaces() {
    echo "🔍 Checking required namespaces..."
    
    REQUIRED_NS=("ml-platform" "mlflow" "monitoring" "vault" "argocd")
    
    for ns in "${REQUIRED_NS[@]}"; do
        if ! kubectl get namespace "$ns" > /dev/null 2>&1; then
            echo "❌ Namespace $ns not found"
            return 1
        fi
    done
    
    echo "✅ All required namespaces exist"
    return 0
}

check_pods() {
    echo "🔍 Checking pod status..."
    
    # Check critical pods
    CRITICAL_PODS=(
        "ml-platform/ml-model-api"
        "mlflow/mlflow-tracking-server"
        "monitoring/prometheus"
        "monitoring/grafana"
        "argocd/argocd-server"
    )
    
    ALL_HEALTHY=true
    
    for pod in "${CRITICAL_PODS[@]}"; do
        namespace=$(echo $pod | cut -d'/' -f1)
        deployment=$(echo $pod | cut -d'/' -f2)
        
        if ! kubectl rollout status deployment/$deployment -n $namespace --timeout=60s > /dev/null 2>&1; then
            echo "❌ Deployment $deployment in namespace $namespace is not healthy"
            ALL_HEALTHY=false
        fi
    done
    
    if [ "$ALL_HEALTHY" = true ]; then
        echo "✅ All critical pods are healthy"
        return 0
    else
        return 1
    fi
}

check_services() {
    echo "🔍 Checking service endpoints..."
    
    SERVICES=(
        "https://api.${DOMAIN_NAME}/health"
        "https://mlflow.${DOMAIN_NAME}/health"
        "https://grafana.${DOMAIN_NAME}/api/health"
        "https://argocd.${DOMAIN_NAME}/health"
    )
    
    ALL_HEALTHY=true
    
    for service in "${SERVICES[@]}"; do
        if ! curl -sfk "$service" > /dev/null 2>&1; then
            echo "❌ Service $service is not responding"
            ALL_HEALTHY=false
        fi
    done
    
    if [ "$ALL_HEALTHY" = true ]; then
        echo "✅ All services are responding"
        return 0
    else
        return 1
    fi
}

check_database_connectivity() {
    echo "🔍 Checking database connectivity..."
    
    # Check PostgreSQL
    if ! kubectl exec -n ml-platform deploy/ml-model-api -- \
        pg_isready -h postgresql.ml-platform.svc.cluster.local -p 5432 > /dev/null 2>&1; then
        echo "❌ Cannot connect to PostgreSQL"
        return 1
    fi
    
    # Check Redis
    if ! kubectl exec -n ml-platform deploy/ml-model-api -- \
        redis-cli -h redis-service.ml-platform.svc.cluster.local ping > /dev/null 2>&1; then
        echo "❌ Cannot connect to Redis"
        return 1
    fi
    
    echo "✅ Database connectivity is healthy"
    return 0
}

check_feature_store() {
    echo "🔍 Checking feature store..."
    
    if ! kubectl exec -n ml-platform deploy/feature-store-service -- \
        curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo "❌ Feature store service is not healthy"
        return 1
    fi
    
    echo "✅ Feature store is healthy"
    return 0
}

check_drift_detection() {
    echo "🔍 Checking drift detection service..."
    
    if ! kubectl exec -n ml-platform deploy/drift-detection-service -- \
        curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo "❌ Drift detection service is not healthy"
        return 1
    fi
    
    echo "✅ Drift detection service is healthy"
    return 0
}

check_monitoring_stack() {
    echo "🔍 Checking monitoring stack..."
    
    # Check Prometheus
    if ! kubectl exec -n monitoring deploy/prometheus -- \
        curl -sf http://localhost:9090/-/healthy > /dev/null 2>&1; then
        echo "❌ Prometheus is not healthy"
        return 1
    fi
    
    # Check Alertmanager
    if ! kubectl exec -n monitoring deploy/alertmanager -- \
        curl -sf http://localhost:9093/-/healthy > /dev/null 2>&1; then
        echo "❌ Alertmanager is not healthy"
        return 1
    fi
    
    # Check that metrics are being collected
    METRIC_COUNT=$(kubectl exec -n monitoring deploy/prometheus -- \
        curl -s http://localhost:9090/api/v1/query?query=count%28up%29 | \
        jq -r '.data.result[0].value[1]' || echo "0")
    
    if [ "$METRIC_COUNT" -eq "0" ]; then
        echo "❌ No metrics are being collected"
        return 1
    fi
    
    echo "✅ Monitoring stack is healthy"
    return 0
}

check_security() {
    echo "🔍 Checking security components..."
    
    # Check Vault
    if ! kubectl exec -n vault deploy/vault -- \
        vault status > /dev/null 2>&1; then
        echo "❌ Vault is not healthy"
        return 1
    fi
    
    # Check network policies
    NETWORK_POLICIES=$(kubectl get networkpolicies -A --no-headers | wc -l)
    if [ "$NETWORK_POLICIES" -eq "0" ]; then
        echo "⚠️  No network policies found"
    fi
    
    echo "✅ Security components are healthy"
    return 0
}

run_comprehensive_health_check() {
    echo "Starting comprehensive health check..."
    echo "====================================="
    
    CHECKS=(
        check_k8s_cluster
        check_namespaces
        check_pods
        check_services
        check_database_connectivity
        check_feature_store
        check_drift_detection
        check_monitoring_stack
        check_security
    )
    
    FAILED_CHECKS=0
    
    for check in "${CHECKS[@]}"; do
        if ! $check; then
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
        echo ""
    done
    
    if [ "$FAILED_CHECKS" -eq 0 ]; then
        echo "🎉 All health checks passed! The platform is healthy."
        return 0
    else
        echo "❌ $FAILED_CHECKS health check(s) failed."
        return 1
    fi
}

# Wait for platform to be ready
echo "⏳ Waiting for platform to be ready (timeout: ${TIMEOUT}s)..."
sleep 60

# Run health checks
run_comprehensive_health_check