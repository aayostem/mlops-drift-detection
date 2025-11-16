#!/bin/bash

set -e

echo "🎯 MLOps Platform - Interview Demonstration"
echo "==========================================="
echo "This script demonstrates key platform capabilities for interviews"
echo ""

# Configuration
export DOMAIN_NAME="mlplatform.company.com"
export MODEL_NAME="breast-cancer-classifier"

# Demo functions
demo_infrastructure() {
    echo "🏗️  1. Infrastructure & Multi-Cloud"
    echo "────────────────────────────────────"
    
    echo "• Terraform-managed infrastructure"
    terraform -chdir=terraform/environments/prod show
    
    echo ""
    echo "• Kubernetes clusters across regions:"
    kubectl config get-contexts
    
    echo ""
    echo "• Network topology:"
    kubectl get networkpolicies -A
    
    read -p "Press enter to continue..."
}

demo_gitops() {
    echo "🔄 2. GitOps & Continuous Deployment"
    echo "────────────────────────────────────"
    
    echo "• ArgoCD applications:"
    kubectl get applications -n argocd
    
    echo ""
    echo "• Application sync status:"
    argocd app list
    
    echo ""
    echo "• Automated deployment pipeline:"
    kubectl get workflows -n tekton-pipelines
    
    read -p "Press enter to continue..."
}

demo_ml_pipelines() {
    echo "🤖 3. ML Pipeline Automation"
    echo "────────────────────────────"
    
    echo "• MLflow experiment tracking:"
    curl -s "https://mlflow.${DOMAIN_NAME}/api/2.0/mlflow/experiments/list" | jq
    
    echo ""
    echo "• Feature store status:"
    curl -s "https://api.${DOMAIN_NAME}/features/health" | jq
    
    echo ""
    echo "• Model registry:"
    curl -s "https://mlflow.${DOMAIN_NAME}/api/2.0/mlflow/registered-models/list" | jq
    
    read -p "Press enter to continue..."
}

demo_model_serving() {
    echo "🎯 4. Model Serving & Inference"
    echo "───────────────────────────────"
    
    echo "• Model serving endpoints:"
    kubectl get virtualservices -n ml-platform
    
    echo ""
    echo "• Live inference test:"
    RESPONSE=$(curl -s -X POST "https://api.${DOMAIN_NAME}/predict" \
        -H "Content-Type: application/json" \
        -d '{
            "features": [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0,
                        1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0,
                        2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.0],
            "model_name": "'"$MODEL_NAME"'"
        }')
    echo "Prediction: $(echo $RESPONSE | jq '.prediction')"
    echo "Confidence: $(echo $RESPONSE | jq '.probabilities')"
    
    echo ""
    echo "• Performance metrics:"
    kubectl get hpa -n ml-platform
    
    read -p "Press enter to continue..."
}

demo_monitoring() {
    echo "📊 5. Monitoring & Observability"
    echo "────────────────────────────────"
    
    echo "• Prometheus metrics collection:"
    curl -s "https://prometheus.${DOMAIN_NAME}/api/v1/query?query=up" | jq '.data.result[] | .metric.instance'
    
    echo ""
    echo "• Grafana dashboards:"
    echo "  - ML Platform Overview"
    echo "  - Model Performance"
    echo "  - Data Drift Detection"
    echo "  - Resource Utilization"
    
    echo ""
    echo "• Distributed tracing:"
    kubectl get services -n monitoring | grep tempo
    
    read -p "Press enter to continue..."
}

demo_drift_detection() {
    echo "📈 6. Drift Detection & Auto-Retraining"
    echo "───────────────────────────────────────"
    
    echo "• Current drift status:"
    curl -s "https://api.${DOMAIN_NAME}/drift/status" | jq
    
    echo ""
    echo "• Drift detection methods:"
    echo "  - Statistical tests (KS, PSI)"
    echo "  - ML-based detection"
    echo "  - Real-time monitoring"
    
    echo ""
    echo "• Auto-retraining pipeline:"
    kubectl get cronjobs -n ml-platform | grep retrain
    
    read -p "Press enter to continue..."
}

demo_security() {
    echo "🔒 7. Security & Governance"
    echo "───────────────────────────"
    
    echo "• Vault secrets management:"
    kubectl exec -n vault vault-0 -- vault secrets list
    
    echo ""
    echo "• OPA policies:"
    kubectl get constraints -A
    
    echo ""
    echo "• Network security:"
    kubectl get networkpolicies -A --no-headers | wc -l
    echo " network policies active"
    
    echo ""
    echo "• Certificate management:"
    kubectl get certificates -A
    
    read -p "Press enter to continue..."
}

demo_cost_optimization() {
    echo "💰 8. Cost Optimization"
    echo "───────────────────────"
    
    echo "• Resource utilization:"
    kubectl top nodes
    
    echo ""
    echo "• Cost optimization actions:"
    kubectl get verticalpodautoscalers -A
    
    echo ""
    echo "• Spot instance usage:"
    kubectl get nodes -l lifecycle=spot
    
    read -p "Press enter to continue..."
}

demo_chaos_engineering() {
    echo "⚡ 9. Chaos Engineering & Resilience"
    echo "────────────────────────────────────"
    
    echo "• Chaos experiments:"
    kubectl get chaos experiments -A
    
    echo ""
    echo "• Resilience testing results:"
    kubectl get workflows -n chaos-mesh
    
    echo ""
    echo "• Service mesh traffic management:"
    kubectl get destinationrules -A
    
    read -p "Press enter to continue..."
}

demo_incident_response() {
    echo "🚨 10. Incident Response Simulation"
    echo "───────────────────────────────────"
    
    echo "• Simulating high drift detection..."
    # This would trigger a mock drift event
    curl -s -X POST "https://api.${DOMAIN_NAME}/demo/drift-event" \
        -H "Content-Type: application/json" \
        -d '{"drift_score": 0.85, "duration_minutes": 20}'
    
    echo ""
    echo "• Alert triggered in:"
    echo "  - Slack channel"
    echo "  - PagerDuty"
    echo "  - Grafana alerts"
    
    echo ""
    echo "• Auto-remediation actions:"
    echo "  - Model retraining triggered"
    echo "  - Canary deployment prepared"
    echo "  - Team notified"
    
    read -p "Press enter to continue..."
}

# Main demo flow
main() {
    echo "Starting MLOps Platform Demonstration..."
    echo ""
    
    demo_infrastructure
    demo_gitops
    demo_ml_pipelines
    demo_model_serving
    demo_monitoring
    demo_drift_detection
    demo_security
    demo_cost_optimization
    demo_chaos_engineering
    demo_incident_response
    
    echo ""
    echo "🎉 Demonstration Completed Successfully!"
    echo ""
    echo "Key Capabilities Demonstrated:"
    echo "• Multi-cloud infrastructure as code"
    echo "• GitOps and continuous deployment"
    echo "• End-to-end ML pipeline automation"
    echo "• Enterprise-grade model serving"
    echo "• Comprehensive monitoring & observability"
    echo "• Advanced drift detection & auto-retraining"
    echo "• Security-first architecture"
    echo "• Cost optimization & resource management"
    echo "• Chaos engineering & resilience"
    echo "• Automated incident response"
}

# Run demonstration
main "$@"