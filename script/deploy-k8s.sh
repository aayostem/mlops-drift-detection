#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
ACTION=${2:-apply}

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "Usage: $0 [dev|staging|prod] [apply|delete|diff]"
    exit 1
fi

echo "🚀 Deploying MLOps platform to $ENVIRONMENT environment"

# Load environment specific variables
source ./environments/${ENVIRONMENT}.env

# Generate kustomization with envsubst
echo "📝 Generating Kubernetes manifests..."
mkdir -p ./manifests/${ENVIRONMENT}
kustomize build ./kubernetes/overlays/${ENVIRONMENT} | envsubst > ./manifests/${ENVIRONMENT}/all.yaml

if [ "$ACTION" == "apply" ]; then
    echo "🛠️  Applying Kubernetes manifests..."
    kubectl apply -f ./manifests/${ENVIRONMENT}/all.yaml
    
    # Wait for deployments to be ready
    echo "⏳ Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/mlflow-tracking-server -n mlflow
    kubectl wait --for=condition=available --timeout=600s deployment/ml-model-api -n ml-platform
    
    echo "✅ MLOps platform deployed successfully to $ENVIRONMENT!"
    
    # Display ingress endpoints
    echo "🌐 Access endpoints:"
    kubectl get ingress -A
    
elif [ "$ACTION" == "delete" ]; then
    echo "🗑️  Deleting MLOps platform from $ENVIRONMENT..."
    kubectl delete -f ./manifests/${ENVIRONMENT}/all.yaml
    
elif [ "$ACTION" == "diff" ]; then
    echo "🔍 Showing differences..."
    kubectl diff -f ./manifests/${ENVIRONMENT}/all.yaml
fi