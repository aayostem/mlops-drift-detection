#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
ACTION=${2:-sync}

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "Usage: $0 [dev|staging|prod] [sync|diff|status]"
    exit 1
fi

echo "🚀 GitOps Deployment for $ENVIRONMENT environment"

# ArgoCD configuration
ARGOCD_SERVER="argocd.mlplatform.company.com"
ARGOCD_USERNAME="admin"
ARGOCD_PASSWORD=$(aws secretsmanager get-secret-value --secret-id argocd-admin-password --query SecretString --output text)

# Login to ArgoCD
argocd login $ARGOCD_SERVER --username $ARGOCD_USERNAME --password $ARGOCD_PASSWORD --insecure

case $ACTION in
    "sync")
        echo "🔄 Syncing applications..."
        argocd app sync ml-platform-$ENVIRONMENT
        argocd app sync mlflow-$ENVIRONMENT
        argocd app sync monitoring-$ENVIRONMENT
        
        # Wait for sync completion
        argocd app wait ml-platform-$ENVIRONMENT --health
        argocd app wait mlflow-$ENVIRONMENT --health
        echo "✅ GitOps sync completed!"
        ;;
        
    "diff")
        echo "🔍 Showing differences..."
        argocd app diff ml-platform-$ENVIRONMENT
        argocd app diff mlflow-$ENVIRONMENT
        ;;
        
    "status")
        echo "📊 Application status:"
        argocd app list
        argocd app get ml-platform-$ENVIRONMENT
        ;;
        
    "rollback")
        echo "↩️  Rolling back to previous version..."
        argocd app rollback ml-platform-$ENVIRONMENT
        ;;
        
    *)
        echo "❌ Unknown action: $ACTION"
        exit 1
        ;;
esac

# Display application URLs
echo "🌐 Access URLs:"
echo "ArgoCD: https://$ARGOCD_SERVER"
echo "MLflow: https://mlflow.$ENVIRONMENT.mlplatform.company.com"
echo "API: https://api.$ENVIRONMENT.mlplatform.company.com"
echo "Grafana: https://grafana.$ENVIRONMENT.mlplatform.company.com"