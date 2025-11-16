#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
ACTION=${2:-deploy}
CONFIG_DIR="./config"
TERRAFORM_DIR="./terraform"
K8S_DIR="./kubernetes"

echo "🚀 MLOps Platform Deployment Orchestrator"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo ""

# Load environment configuration
source ${CONFIG_DIR}/environments/${ENVIRONMENT}.env

deploy_infrastructure() {
    echo "🏗️  Deploying Infrastructure..."
    
    # Initialize and plan Terraform
    cd ${TERRAFORM_DIR}/environments/${ENVIRONMENT}
    terraform init -reconfigure
    terraform plan -var-file="terraform.tfvars"
    
    if [ "$ACTION" == "deploy" ]; then
        terraform apply -var-file="terraform.tfvars" -auto-approve
    fi
    
    # Extract outputs for Kubernetes
    terraform output -json > ${K8S_DIR}/terraform-outputs/${ENVIRONMENT}.json
    cd - > /dev/null
    
    echo "✅ Infrastructure deployment completed"
}

deploy_kubernetes() {
    echo "⚙️  Deploying Kubernetes Components..."
    
    # Apply base Kubernetes configuration
    kubectl apply -k ${K8S_DIR}/base
    
    # Deploy ArgoCD for GitOps
    kubectl apply -n argocd -f ${K8S_DIR}/components/argocd/install.yaml
    
    # Wait for ArgoCD to be ready
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
    
    # Apply ArgoCD applications
    kubectl apply -f ${K8S_DIR}/argocd/app-of-apps.yaml
    
    echo "✅ Kubernetes deployment completed"
}

deploy_ml_platform() {
    echo "🤖 Deploying ML Platform Components..."
    
    # Wait for ArgoCD to sync applications
    echo "⏳ Waiting for ArgoCD applications to sync..."
    kubectl wait --for=condition=healthy app/ml-platform -n argocd --timeout=600s
    kubectl wait --for=condition=healthy app/mlflow -n argocd --timeout=600s
    kubectl wait --for=condition=healthy app/monitoring -n argocd --timeout=600s
    
    # Initialize ML platform
    kubectl apply -f ${K8S_DIR}/components/ml-platform/init.yaml
    
    echo "✅ ML Platform deployment completed"
}

run_tests() {
    echo "🧪 Running Platform Tests..."
    
    # Health checks
    ./scripts/health-check.sh ${ENVIRONMENT}
    
    # Integration tests
    ./scripts/integration-tests.sh ${ENVIRONMENT}
    
    # Performance tests
    ./scripts/performance-tests.sh ${ENVIRONMENT}
    
    # Security scans
    ./scripts/security-scan.sh ${ENVIRONMENT}
    
    echo "✅ Platform tests completed"
}

destroy_platform() {
    echo "🗑️  Destroying Platform..."
    
    read -p "❌ Are you sure you want to destroy the $ENVIRONMENT environment? (yes/no): " confirmation
    if [ "$confirmation" != "yes" ]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    # Delete ArgoCD applications first
    kubectl delete -f ${K8S_DIR}/argocd/app-of-apps.yaml --ignore-not-found=true
    
    # Destroy Kubernetes resources
    kubectl delete -k ${K8S_DIR}/overlays/${ENVIRONMENT} --ignore-not-found=true
    
    # Destroy infrastructure
    cd ${TERRAFORM_DIR}/environments/${ENVIRONMENT}
    terraform destroy -var-file="terraform.tfvars" -auto-approve
    cd - > /dev/null
    
    echo "✅ Platform destruction completed"
}

show_status() {
    echo "📊 Platform Status:"
    echo ""
    
    # Infrastructure status
    echo "🏗️  Infrastructure:"
    cd ${TERRAFORM_DIR}/environments/${ENVIRONMENT}
    terraform show -json | jq -r '.values.outputs | to_entries[] | "  \(.key): \(.value.value)"'
    cd - > /dev/null
    
    echo ""
    echo "⚙️  Kubernetes:"
    kubectl get nodes -o wide
    echo ""
    kubectl get pods -A --sort-by='.metadata.namespace'
    
    echo ""
    echo "🤖 ML Platform:"
    kubectl get applications -n argocd
    echo ""
    kubectl get services -n ml-platform
}

case $ACTION in
    "deploy")
        deploy_infrastructure
        deploy_kubernetes
        deploy_ml_platform
        run_tests
        ;;
    "destroy")
        destroy_platform
        ;;
    "status")
        show_status
        ;;
    "test")
        run_tests
        ;;
    "infra-only")
        deploy_infrastructure
        ;;
    "k8s-only")
        deploy_kubernetes
        ;;
    "ml-only")
        deploy_ml_platform
        ;;
    *)
        echo "Usage: $0 [dev|staging|prod] [deploy|destroy|status|test|infra-only|k8s-only|ml-only]"
        exit 1
        ;;
esac

echo ""
echo "🎉 MLOps Platform deployment completed successfully!"
echo ""
echo "🌐 Access URLs:"
echo "  ArgoCD: https://argocd.${DOMAIN_NAME}"
echo "  MLflow: https://mlflow.${DOMAIN_NAME}"
echo "  API: https://api.${DOMAIN_NAME}"
echo "  Grafana: https://grafana.${DOMAIN_NAME}"
echo ""
echo "Next steps:"
echo "  1. Configure your CI/CD pipelines"
echo "  2. Set up monitoring alerts"
echo "  3. Train and deploy your first model"
echo "  4. Configure drift detection thresholds"