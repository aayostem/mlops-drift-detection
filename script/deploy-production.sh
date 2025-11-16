#!/bin/bash

set -e

echo "🏭 MLOps Platform - Production Deployment"
echo "=========================================="
echo "This script deploys the complete MLOps platform to production"
echo ""

# Configuration
export ENVIRONMENT="prod"
export CLUSTER_NAME="ml-platform-prod"
export DOMAIN_NAME="mlplatform.company.com"
export AWS_REGION="us-west-2"
export K8S_VERSION="1.27"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check Kubernetes access
    if ! kubectl cluster-info > /dev/null 2>&1; then
        log_error "Kubernetes cluster not accessible"
        exit 1
    fi
    
    # Check required tools
    for cmd in terraform kubectl helm aws jq; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd not found in PATH"
            exit 1
        fi
    done
    
    # Check domain DNS
    if ! nslookup $DOMAIN_NAME &> /dev/null; then
        log_warning "Domain $DOMAIN_NAME not resolvable. Please configure DNS."
    fi
    
    log_success "Pre-flight checks passed"
}

# Infrastructure deployment
deploy_infrastructure() {
    log_info "Deploying production infrastructure..."
    
    cd terraform/environments/prod
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -reconfigure -upgrade
    
    # Plan deployment
    log_info "Creating execution plan..."
    terraform plan -var-file="terraform.tfvars" -out=production.tfplan
    
    # Apply infrastructure
    log_info "Applying infrastructure changes..."
    terraform apply -auto-approve production.tfplan
    
    # Extract outputs
    log_info "Extracting Terraform outputs..."
    terraform output -json > ../../kubernetes/terraform-outputs/prod.json
    
    cd - > /dev/null
    
    log_success "Infrastructure deployed successfully"
}

# Kubernetes platform deployment
deploy_kubernetes_platform() {
    log_info "Deploying Kubernetes platform components..."
    
    # Create namespaces
    log_info "Creating required namespaces..."
    kubectl apply -k kubernetes/base/namespaces
    
    # Deploy ArgoCD
    log_info "Deploying ArgoCD for GitOps..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=600s
    
    # Get ArgoCD admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    log_info "ArgoCD admin password: $ARGOCD_PASSWORD"
    
    # Deploy application of applications
    log_info "Deploying ArgoCD Application of Applications..."
    kubectl apply -f argocd/applications/app-of-apps.yaml
    
    log_success "Kubernetes platform deployed successfully"
}

# Wait for platform components
wait_for_platform() {
    log_info "Waiting for all platform components to be ready..."
    
    # Wait for critical applications
    declare -a APPS=("ml-platform" "mlflow" "monitoring" "vault" "istio-system")
    
    for app in "${APPS[@]}"; do
        log_info "Waiting for $app to be healthy..."
        kubectl wait --for=condition=healthy app/$app -n argocd --timeout=1200s
    done
    
    # Wait for all pods to be ready
    log_info "Waiting for all pods to be ready..."
    kubectl wait --for=condition=ready pods --all --all-namespaces --timeout=1800s
    
    log_success "All platform components are ready"
}

# Initialize security
initialize_security() {
    log_info "Initializing security components..."
    
    # Initialize Vault
    log_info "Initializing HashiCorp Vault..."
    kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3 -format=json > vault-keys.json
    
    # Unseal Vault
    log_info "Unsealing Vault..."
    for i in {0..2}; do
        KEY=$(jq -r ".unseal_keys_b64[$i]" vault-keys.json)
        kubectl exec -n vault vault-0 -- vault operator unseal $KEY
    done
    
    # Setup Vault secrets engines
    log_info "Setting up Vault secrets engines..."
    ./scripts/setup-vault.sh
    
    # Secure vault keys
    log_info "Securing Vault keys..."
    mv vault-keys.json /secure/location/vault-keys-$(date +%Y%m%d).json
    chmod 600 /secure/location/vault-keys-*.json
    
    log_success "Security components initialized"
}

# Configure monitoring and alerting
configure_monitoring() {
    log_info "Configuring monitoring and alerting..."
    
    # Import Grafana dashboards
    log_info "Importing Grafana dashboards..."
    for dashboard in observability/grafana/dashboards/*.json; do
        curl -X POST \
            -H "Content-Type: application/json" \
            -d @$dashboard \
            "https://admin:${GRAFANA_PASSWORD}@grafana.${DOMAIN_NAME}/api/dashboards/db"
    done
    
    # Configure alert channels
    log_info "Configuring alert channels..."
    curl -X POST \
        -H "Content-Type: application/json" \
        -d '{
            "name": "slack-ml-platform",
            "type": "slack",
            "settings": {
                "url": "'"${SLACK_WEBHOOK_URL}"'",
                "channel": "#ml-platform-alerts"
            }
        }' \
        "https://admin:${GRAFANA_PASSWORD}@grafana.${DOMAIN_NAME}/api/alert-notifications"
    
    # Configure Prometheus rules
    log_info "Configuring Prometheus alerting rules..."
    kubectl apply -f observability/prometheus/alerting-rules/
    
    log_success "Monitoring and alerting configured"
}

# Deploy sample models
deploy_sample_models() {
    log_info "Deploying sample models..."
    
    # Train and register sample model
    log_info "Training sample model..."
    python scripts/train_sample_model.py \
        --model-name "breast-cancer-classifier" \
        --dataset-url "s3://ml-platform-data/sample/breast_cancer.csv" \
        --experiment-name "production"
    
    # Deploy model to staging
    log_info "Deploying model to staging..."
    ./scripts/deploy-model.sh \
        --model "breast-cancer-classifier" \
        --version "1.0.0" \
        --stage "Staging"
    
    # Run canary deployment
    log_info "Starting canary deployment..."
    ./scripts/canary-deployment.sh \
        --model "breast-cancer-classifier" \
        --version "1.0.0" \
        --strategy "linear" \
        --duration 60
    
    log_success "Sample models deployed successfully"
}

# Run comprehensive tests
run_production_tests() {
    log_info "Running production validation tests..."
    
    # Health checks
    log_info "Running health checks..."
    ./scripts/health-check.sh prod
    
    # Integration tests
    log_info "Running integration tests..."
    ./scripts/integration-tests.sh prod
    
    # Performance tests
    log_info "Running performance tests..."
    ./scripts/performance-tests.sh prod
    
    # Security scans
    log_info "Running security scans..."
    ./scripts/security-scan.sh prod
    
    # Load tests
    log_info "Running load tests..."
    ./scripts/load-test.sh prod
    
    log_success "All production tests passed"
}

# Final configuration
final_configuration() {
    log_info "Applying final configuration..."
    
    # Configure backup schedules
    log_info "Configuring backup schedules..."
    kubectl apply -f kubernetes/components/backup/
    
    # Configure cost optimization
    log_info "Configuring cost optimization..."
    kubectl apply -f kubernetes/components/cost-optimization/
    
    # Configure chaos engineering
    log_info "Configuring chaos engineering experiments..."
    kubectl apply -f chaos-engineering/experiments/
    
    # Set up log aggregation
    log_info "Setting up log aggregation..."
    kubectl apply -f observability/loki/
    
    log_success "Final configuration completed"
}

# Main deployment function
main() {
    log_info "Starting production deployment of MLOps Platform"
    echo ""
    
    # Execute deployment steps
    preflight_checks
    deploy_infrastructure
    deploy_kubernetes_platform
    wait_for_platform
    initialize_security
    configure_monitoring
    deploy_sample_models
    run_production_tests
    final_configuration
    
    echo ""
    log_success "🎉 MLOps Platform Production Deployment Completed Successfully!"
    echo ""
    
    # Display access information
    display_access_info
}

# Display access information
display_access_info() {
    cat << EOF

🌐 Platform Access URLs:
────────────────────────────────────────────
ArgoCD (GitOps):    https://argocd.${DOMAIN_NAME}
MLflow (Registry):  https://mlflow.${DOMAIN_NAME}  
Model API:          https://api.${DOMAIN_NAME}
Grafana (Metrics):  https://grafana.${DOMAIN_NAME}
Kibana (Logs):      https://kibana.${DOMAIN_NAME}

🔐 Initial Credentials:
────────────────────────────────────────────
ArgoCD:             admin / ${ARGOCD_PASSWORD}
Grafana:            admin / ${GRAFANA_PASSWORD}
MLflow:             No authentication by default

📊 Next Steps:
────────────────────────────────────────────
1. Train and deploy your first model
2. Configure monitoring alerts
3. Set up CI/CD pipelines  
4. Configure budget alerts
5. Run chaos experiments
6. Set up backup verification

⚡ Quick Start Commands:
────────────────────────────────────────────
# Check platform status
./scripts/status.sh prod

# Deploy a new model
./scripts/deploy-model.sh --model your-model --version 1.0.0

# Check drift detection
./scripts/check-drift.sh --model your-model

# Run health checks
./scripts/health-check.sh prod

EOF
}

# Handle interrupts
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"