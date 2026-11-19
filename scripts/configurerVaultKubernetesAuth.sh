#!/bin/bash
set -euo pipefail

VAULT_INIT_FILE="${HOME}/.ssh/vault-init.json"

if [[ ! -f "${VAULT_INIT_FILE}" ]]; then
  echo "ERREUR: Fichier ${VAULT_INIT_FILE} introuvable. Initialisez d'abord Vault." >&2
  exit 1
fi

ROOT_TOKEN=$(jq -r '.root_token' "${VAULT_INIT_FILE}")

echo "1. Activation du moteur de secrets KV v2 sous le chemin 'secret/'..."
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" \
  vault secrets enable -version=2 -path=secret kv 2>/dev/null || echo "   -> Moteur 'secret/' déjà activé."

echo "2. Création de la politique du moindre privilège 'eso-reader' (lecture seule sur secret/data/*)..."
kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" \
  vault policy write eso-reader - << 'EOF'
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["list", "read"]
}
EOF

echo "3. Activation de l'authentification native Kubernetes dans Vault (Zero Static Token)..."
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" \
  vault auth enable kubernetes 2>/dev/null || echo "   -> Auth 'kubernetes' déjà activée."

echo "4. Configuration du point de terminaison Kubernetes Auth vers l'API interne du cluster..."
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" sh -c '
  vault write auth/kubernetes/config \
    kubernetes_host="https://${KUBERNETES_PORT_443_TCP_ADDR}:443"
'

echo "5. Liaison du rôle Vault 'external-secrets' au ServiceAccount 'external-secrets' (namespace 'external-secrets')..."
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" \
  vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=eso-reader \
    ttl=1h

echo "6. Injection d'un premier secret applicatif de démonstration dans Vault (secret/demo-app/database)..."
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" \
  vault kv put secret/demo-app/database \
    username="demo_user" \
    password="$(openssl rand -base64 24)" \
    db_host="postgres.demo-app.svc.cluster.local"

echo "7. Injection des identifiants administrateur Grafana dans Vault (secret/monitoring/grafana)..."
if ! kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" vault kv get secret/monitoring/grafana >/dev/null 2>&1; then
  kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" \
    vault kv put secret/monitoring/grafana \
      admin_user="admin" \
      admin_password="$(openssl rand -base64 18)"
fi

echo "8. Injection des secrets Authentik (SSO / ForwardAuth) dans Vault (secret/authentik/config)..."
if ! kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" vault kv get secret/authentik/config >/dev/null 2>&1; then
  kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${ROOT_TOKEN}" \
    vault kv put secret/authentik/config \
      secret_key="$(openssl rand -base64 48)" \
      pg_password="$(openssl rand -hex 24)" \
      pg_admin_password="$(openssl rand -hex 24)"
fi

echo "✅ HashiCorp Vault est configuré avec Kubernetes Auth et prêt pour External Secrets Operator (ESO) !"
