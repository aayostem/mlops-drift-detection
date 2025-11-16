#!/bin/bash

echo "⚡ MLOps Platform - 5-Minute Demo"
echo "================================="

# 1. Show platform status
echo "1. Platform Status"
kubectl get nodes
kubectl get applications -n argocd

# 2. Demonstrate model serving
echo ""
echo "2. Live Model Inference"
curl -s -X POST "https://api.mlplatform.company.com/predict" \
  -H "Content-Type: application/json" \
  -d '{"features": [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.0], "model_name": "breast-cancer-classifier"}' | jq

# 3. Show monitoring dashboards
echo ""
echo "3. Monitoring Dashboard URLs:"
echo "   - Grafana: https://grafana.mlplatform.company.com"
echo "   - MLflow: https://mlflow.mlplatform.company.com"
echo "   - ArgoCD: https://argocd.mlplatform.company.com"

# 4. Demonstrate drift detection
echo ""
echo "4. Drift Detection Status"
curl -s "https://api.mlplatform.company.com/drift/status" | jq

# 5. Show security features
echo ""
echo "5. Security & Governance"
kubectl get networkpolicies -A --no-headers | wc -l | xargs echo "Active Network Policies:"
kubectl get constraints -A --no-headers | wc -l | xargs echo "OPA Policies:"

echo ""
echo "🎯 Demo Complete - Platform is Production Ready!"