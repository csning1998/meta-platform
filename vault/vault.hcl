
ui            = true
api_addr      = "https://127.0.0.1:8222"
cluster_addr  = "https://127.0.0.1:8333"
disable_mlock = false

storage "raft" {
  node_id = "node1"
  path    = "/opt/vault/data"
}

listener "tcp" {
  address       = "127.0.0.1:8222"
  tls_disable   = false
  tls_cert_file = "/opt/vault/tls/vault.pem"
  tls_key_file  = "/opt/vault/tls/vault-key.pem"
}
