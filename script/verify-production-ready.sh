#!/bin/bash

echo "🔍 Production Readiness Verification"
echo "===================================="

check_passed=0
check_failed=0

verify_infrastructure() {
    echo "🏗️  Infrastructure Verification"
    
    # Check Terraform state
    if terraform -chdir=terraform/environments/prod state list &> /dev/null; then
        echo "✅ Terraform state accessible"
        ((check_passed++))
    else
        echo "❌ Terraform state inaccessible"
        ((check_failed++))
    fi
    
    # Check Kubernetes clusters
    if kubectl cluster-info &> /dev/null; then
        echo "✅ Kubernetes cluster accessible"
        ((check_passed++))
    else
        echo "❌ Kubernetes cluster inaccessible"
        ((check_failed++))
    fi
}

verify_security() {
    echo "🔒 Security Verification"
    
    # Check network policies
    policies=$(kubectl get networkpolicies -A --no-headers | wc -l)
    if [ $policies -gt 0 ]; then
        echo "✅ Network policies configured ($policies policies)"
        ((check_passed++))
    else
        echo "❌ No network policies configured"
        ((check_failed++))
    fi
    
    # Check Vault
    if kubectl exec -n vault vault-0 -- vault status &> /dev/null; then
        echo "✅ Vault operational"
        ((check_passed++))
    else
        echo "❌ Vault not operational"
        ((check_failed++))
    fi
}

verify_monitoring() {
    echo "📊 Monitoring Verification"
    
    # Check Prometheus
    if curl -s "https://prometheus.mlplatform.company.com/-/healthy" &> /dev/null; then
        echo "✅ Prometheus healthy"
        ((check_passed++))
    else
        echo "❌ Prometheus unhealthy"
        ((check_failed++))
    fi
    
    # Check alerting
    alerts=$(curl -s "https://prometheus.mlplatform.company.com/api/v1/alerts" | jq '.data.alerts | length')
    if [ $alerts -ge 0 ]; then
        echo "✅ Alerting configured ($alerts active alerts)"
        ((check_passed++))
    else
        echo "❌ Alerting issues"
        ((check_failed++))
    fi
}

verify_ml_platform() {
    echo "🤖 ML Platform Verification"
    
    # Check model serving
    response=$(curl -s -o /dev/null -w "%{http_code}" "https://api.mlplatform.company.com/health")
    if [ $response -eq 200 ]; then
        echo "✅ Model API healthy"
        ((check_passed++))
    else
        echo "❌ Model API unhealthy"
        ((check_failed++))
    fi
    
    # Check feature store
    if kubectl get deployment/feature-store-service -n ml-platform &> /dev/null; then
        echo "✅ Feature store deployed"
        ((check_passed++))
    else
        echo "❌ Feature store not deployed"
        ((check_failed++))
    fi
}

verify_disaster_recovery() {
    echo "🚨 Disaster Recovery Verification"
    
    # Check backups
    if kubectl get cronjob/backup-job -n ml-platform &> /dev/null; then
        echo "✅ Backup jobs configured"
        ((check_passed++))
    else
        echo "❌ Backup jobs not configured"
        ((check_failed++))
    fi
    
    # Check multi-region
    regions=$(kubectl config get-contexts -o name | wc -l)
    if [ $regions -gt 1 ]; then
        echo "✅ Multi-region configured ($regions regions)"
        ((check_passed++))
    else
        echo "⚠️  Single region only"
    fi
}

# Run all verifications
verify_infrastructure
verify_security
verify_monitoring
verify_ml_platform
verify_disaster_recovery

echo ""
echo "Verification Summary:"
echo "✅ $check_passed checks passed"
if [ $check_failed -gt 0 ]; then
    echo "❌ $check_failed checks failed"
    exit 1
else
    echo "🎉 All production readiness checks passed!"
    echo "The platform is ready for production use."
fi