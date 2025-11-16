# vault/config/vault-config.hcl

storage "consul" {
  path = "vault/"
  address = "consul-service.consul:8500"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/tls.crt"
  tls_key_file = "/vault/certs/tls.key"
}

api_addr = "https://vault.ml-platform.svc.cluster.local:8200"
cluster_addr = "https://vault.ml-platform.svc.cluster.local:8201"
ui = true