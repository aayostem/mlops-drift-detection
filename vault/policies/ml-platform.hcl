# vault/policies/ml-platform.hcl

path "secret/data/ml-platform/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/ml-platform/*" {
  capabilities = ["list"]
}

path "database/creds/ml-platform-role" {
  capabilities = ["read"]
}

path "aws/creds/ml-platform-role" {
  capabilities = ["read"]
}

path "pki/issue/ml-platform" {
  capabilities = ["create", "update"]
}

path "transit/encrypt/ml-platform" {
  capabilities = ["create", "update"]
}

path "transit/decrypt/ml-platform" {
  capabilities = ["create", "update"]
}