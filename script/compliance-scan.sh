#!/bin/bash

set -e

echo "📋 Running Kubernetes compliance checks..."

# Run kube-bench for node compliance
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# Wait for job completion
kubectl wait --for=condition=complete job/kube-bench --timeout=300s

# Get results
kubectl logs job/kube-bench > compliance-reports/kube-bench-$(date +%Y%m%d).log

# Check for failures
FAILED_CHECKS=$(grep -c "\\[FAIL\\]" compliance-reports/kube-bench-*.log || true)

if [ "$FAILED_CHECKS" -gt 0 ]; then
    echo "❌ Compliance check failed: $FAILED_CHECKS failed checks"
    exit 1
fi

echo "✅ Compliance checks passed!"

# Clean up
kubectl delete job kube-bench