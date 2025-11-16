#!/bin/bash

set -e

IMAGE=$1
SCAN_TYPE=${2:-image}

echo "🔍 Running security scan for $IMAGE"

# Create reports directory
mkdir -p security-reports

case $SCAN_TYPE in
    "image")
        echo "📦 Scanning container image..."
        trivy image \
            --format template \
            --template "@/usr/local/share/trivy/templates/html.tpl" \
            --output security-reports/$(echo $IMAGE | tr '/:' '_').html \
            --severity HIGH,CRITICAL \
            $IMAGE
        
        # Check for critical vulnerabilities
        CRITICAL_COUNT=$(trivy image --severity CRITICAL --format json $IMAGE | jq '.Results[].Vulnerabilities | map(select(.Severity == "CRITICAL")) | length')
        if [ "$CRITICAL_COUNT" -gt 0 ]; then
            echo "❌ Critical vulnerabilities found: $CRITICAL_COUNT"
            exit 1
        fi
        ;;
        
    "config")
        echo "⚙️ Scanning Kubernetes configuration..."
        trivy config \
            --format template \
            --template "@/usr/local/share/trivy/templates/html.tpl" \
            --output security-reports/kubernetes-config.html \
            kubernetes/
        ;;
        
    "fs")
        echo "📁 Scanning filesystem..."
        trivy filesystem \
            --format template \
            --template "@/usr/local/share/trivy/templates/html.tpl" \
            --output security-reports/filesystem.html \
            --severity HIGH,CRITICAL \
            .
        ;;
esac

echo "✅ Security scan completed. Reports saved to security-reports/"