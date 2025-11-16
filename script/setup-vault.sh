#!/bin/bash

set -e

echo "🔐 Setting up Vault for MLOps platform..."

# Export Vault address
export VAULT_ADDR="https://vault.ml-platform.svc.cluster.local:8200"
export VAULT_SKIP_VERIFY=true

# Wait for Vault to be ready
echo "⏳ Waiting for Vault to be ready..."
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=300s

# Initialize Vault if not already initialized
if ! vault status | grep -q "Initialized.*true"; then
    echo "🚀 Initializing Vault..."
    vault operator init -key-shares=5 -key-threshold=3 > vault-keys.txt
    
    # Extract unseal keys and root token
    UNSEAL_KEY_1=$(grep "Unseal Key 1" vault-keys.txt | awk '{print $4}')
    UNSEAL_KEY_2=$(grep "Unseal Key 2" vault-keys.txt | awk '{print $4}')
    UNSEAL_KEY_3=$(grep "Unseal Key 3" vault-keys.txt | awk '{print $4}')
    ROOT_TOKEN=$(grep "Initial Root Token" vault-keys.txt | awk '{print $4}')
    
    # Unseal Vault
    vault operator unseal $UNSEAL_KEY_1
    vault operator unseal $UNSEAL_KEY_2
    vault operator unseal $UNSEAL_KEY_3
    
    export VAULT_TOKEN=$ROOT_TOKEN
else
    echo "✅ Vault already initialized"
    export VAULT_TOKEN=$(vault login -method=userpass username=admin -format=json | jq -r '.auth.client_token')
fi

# Enable Kubernetes auth method
echo "🔧 Enabling Kubernetes auth method..."
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="https://kubernetes.default.svc.cluster.local"

# Enable secrets engines
echo "🔑 Enabling secrets engines..."
vault secrets enable -path=secret kv-v2
vault secrets enable database
vault secrets enable aws
vault secrets enable pki
vault secrets enable transit

# Configure database secrets engine for PostgreSQL
vault write database/config/ml-platform-postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="ml-platform-role" \
    connection_url="postgresql://{{username}}:{{password}}@postgresql.ml-platform.svc.cluster.local:5432/mlflow" \
    username="vault-admin" \
    password="$(vault read -field=password secret/data/ml-platform/database-admin)"

# Create database role
vault write database/roles/ml-platform-role \
    db_name=ml-platform-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

# Configure AWS secrets engine
vault write aws/config/root \
    access_key=$AWS_ACCESS_KEY_ID \
    secret_key=$AWS_SECRET_ACCESS_KEY \
    region=us-west-2

vault write aws/roles/ml-platform-role \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ml-platform-*",
        "arn:aws:s3:::ml-platform-*/*"
      ]
    }
  ]
}
EOF

# Create ML platform policy
vault policy write ml-platform vault/policies/ml-platform.hcl

# Create Kubernetes auth role
vault write auth/kubernetes/role/ml-platform \
    bound_service_account_names=ml-workloads \
    bound_service_account_namespaces=ml-platform,mlflow \
    policies=ml-platform \
    ttl=1h

echo "✅ Vault setup completed successfully!"