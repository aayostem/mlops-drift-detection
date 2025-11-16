# Operational Runbooks

## Incident Response

### High Drift Detection Alert
**Severity**: Critical

**Symptoms**:
- Drift score > 0.8 for 15+ minutes
- Model accuracy degradation
- Increased prediction errors

**Immediate Actions**:
1. Check drift detection dashboard
2. Verify data pipeline integrity
3. Check for feature store issues
4. Review model performance metrics

**Resolution**:
```bash
# 1. Check current drift status
./scripts/drift-status.sh

# 2. If confirmed, trigger retraining
./scripts/retrain-model.sh --model breast-cancer-classifier --urgent

# 3. Deploy new model
./scripts/deploy-model.sh --model breast-cancer-classifier --version latest --canary 10

# 4. Monitor canary performance
./scripts/monitor-canary.sh --model breast-cancer-classifier
```


### Model Serving Performance Degradation
Severity: High

Symptoms:

P95 latency > 1 second

Error rate > 5%

CPU utilization > 90%

Immediate Actions:

Check Kubernetes resource utilization

Review application logs

Check dependent services (feature store, database)

Scale up deployment if needed

Resolution:

# 1. Scale up deployment
kubectl scale deployment/ml-model-api --replicas=10 -n ml-platform

# 2. Check resource limits
kubectl top pods -n ml-platform

# 3. Review logs for errors
kubectl logs -l app=ml-model-api -n ml-platform --tail=100

# 4. Check feature store performance
kubectl exec -n ml-platform deploy/feature-store-service -- curl http://localhost:8080/health


### Monthly Platform Updates
# 1. Backup critical data
./scripts/backup-platform.sh

# 2. Update platform components
./scripts/update-platform.sh --components all

# 3. Run health checks
./scripts/health-check.sh

# 4. Validate model performance
./scripts/validate-models.sh

## Database Mintenance
# 1. Backup database
./scripts/backup-database.sh

# 2. Run vacuum and analyze
kubectl exec -n ml-platform deploy/mlflow-tracking-server -- \
  psql -h postgresql -U mlflow -c "VACUUM ANALYZE;"

# 3. Check database size and growth
kubectl exec -n ml-platform deploy/mlflow-tracking-server -- \
  psql -h postgresql -U mlflow -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables WHERE schemaname NOT IN ('information_schema', 'pg_catalog') ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"

  
### **4. Final Platform Validation**

#### **End-to-End Testing** (`scripts/validate-platform.sh`)
```bash
#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
MODEL_NAME="breast-cancer-classifier"

echo "🔬 Platform Validation Suite"
echo "============================"
echo "Environment: $ENVIRONMENT"
echo ""

# Load environment configuration
source ./config/environments/${ENVIRONMENT}.env

run_data_pipeline_test() {
    echo "📊 Testing Data Pipeline..."
    
    # Trigger data processing pipeline
    RESPONSE=$(curl -s -X POST "https://api.${DOMAIN_NAME}/pipelines/trigger" \
        -H "Content-Type: application/json" \
        -d '{"pipeline_type": "data_processing", "dataset": "validation"}')
    
    if echo "$RESPONSE" | jq -e '.status == "success"' > /dev/null; then
        echo "✅ Data pipeline test passed"
        return 0
    else
        echo "❌ Data pipeline test failed"
        return 1
    fi
}

run_feature_store_test() {
    echo "🏪 Testing Feature Store..."
    
    # Test feature retrieval
    RESPONSE=$(curl -s -X POST "https://api.${DOMAIN_NAME}/features/online" \
        -H "Content-Type: application/json" \
        -d '{
            "entity_rows": [{"user_id": "test_user_123"}],
            "feature_refs": ["user_stats:avg_transaction_amount", "user_stats:transaction_count_7d"]
        }')
    
    if echo "$RESPONSE" | jq -e 'length > 0' > /dev/null; then
        echo "✅ Feature store test passed"
        return 0
    else
        echo "❌ Feature store test failed"
        return 1
    fi
}

run_model_training_test() {
    echo "🤖 Testing Model Training..."
    
    # Trigger model training
    RESPONSE=$(curl -s -X POST "https://api.${DOMAIN_NAME}/models/train" \
        -H "Content-Type: application/json" \
        -d '{
            "model_name": "test-model",
            "dataset": "validation",
            "parameters": {"n_estimators": 10, "max_depth": 3}
        }')
    
    if echo "$RESPONSE" | jq -e '.run_id != null' > /dev/null; then
        echo "✅ Model training test passed"
        return 0
    else
        echo "❌ Model training test failed"
        return 1
    fi
}

run_model_inference_test() {
    echo "🎯 Testing Model Inference..."
    
    # Test prediction endpoint
    RESPONSE=$(curl -s -X POST "https://api.${DOMAIN_NAME}/predict" \
        -H "Content-Type: application/json" \
        -d '{
            "features": [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0,
                        1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0,
                        2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.0],
            "model_name": "'"$MODEL_NAME"'"
        }')
    
    if echo "$RESPONSE" | jq -e '.prediction != null' > /dev/null; then
        echo "✅ Model inference test passed"
        return 0
    else
        echo "❌ Model inference test failed"
        return 1
    fi
}

run_drift_detection_test() {
    echo "📈 Testing Drift Detection..."
    
    # Trigger drift detection
    RESPONSE=$(curl -s -X POST "https://api.${DOMAIN_NAME}/drift/detect" \
        -H "Content-Type: application/json" \
        -d '{
            "model_name": "'"$MODEL_NAME"'",
            "reference_data_id": "validation-baseline",
            "current_data": [
                {"feature_1": 0.1, "feature_2": 0.2, "target": 0},
                {"feature_1": 0.3, "feature_2": 0.4, "target": 1}
            ]
        }')
    
    if echo "$RESPONSE" | jq -e '.drift_score != null' > /dev/null; then
        echo "✅ Drift detection test passed"
        return 0
    else
        echo "❌ Drift detection test failed"
        return 1
    fi
}

run_monitoring_test() {
    echo "📊 Testing Monitoring Stack..."
    
    # Check that metrics are being collected
    METRIC_COUNT=$(curl -s "https://prometheus.${DOMAIN_NAME}/api/v1/query?query=count(up)" | \
        jq -r '.data.result[0].value[1]' || echo "0")
    
    if [ "$METRIC_COUNT" -gt "0" ]; then
        echo "✅ Monitoring stack test passed"
        return 0
    else
        echo "❌ Monitoring stack test failed"
        return 1
    fi
}

run_security_test() {
    echo "🔒 Testing Security Controls..."
    
    # Test that unauthorized access is blocked
    RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "https://api.${DOMAIN_NAME}/admin" \
        -H "Authorization: Bearer invalid-token")
    
    if [ "$RESPONSE" -eq "401" ] || [ "$RESPONSE" -eq "403" ]; then
        echo "✅ Security controls test passed"
        return 0
    else
        echo "❌ Security controls test failed"
        return 1
    fi
}

run_performance_test() {
    echo "⚡ Testing Performance..."
    
    # Run load test
    RESPONSE=$(kubectl run -n ml-platform -i --rm load-test --image=alpine/curl --restart=Never -- \
        sh -c "for i in \$(seq 1 10); do curl -s -o /dev/null -w '%{http_code}\n' https://api.${DOMAIN_NAME}/health; done" | \
        grep -c "200")
    
    if [ "$RESPONSE" -eq "10" ]; then
        echo "✅ Performance test passed"
        return 0
    else
        echo "❌ Performance test failed"
        return 1
    fi
}

run_comprehensive_validation() {
    echo "Starting comprehensive platform validation..."
    echo "============================================="
    
    TESTS=(
        run_data_pipeline_test
        run_feature_store_test
        run_model_training_test
        run_model_inference_test
        run_drift_detection_test
        run_monitoring_test
        run_security_test
        run_performance_test
    )
    
    FAILED_TESTS=0
    
    for test in "${TESTS[@]}"; do
        if ! $test; then
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        echo ""
    done
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo "🎉 All validation tests passed! The platform is fully operational."
        return 0
    else
        echo "❌ $FAILED_TESTS test(s) failed. Please check the platform configuration."
        return 1
    fi
}

# Run validation
run_comprehensive_validation
```
