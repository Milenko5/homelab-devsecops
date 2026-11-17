#!/bin/bash
set -euo pipefail

# Charge les variables depuis .env si présent
if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  source .env
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || "${CLOUDFLARE_API_TOKEN}" == "votre_jeton_cloudflare" ]]; then
  echo "ERREUR: La variable CLOUDFLARE_API_TOKEN n'est pas définie ou contient encore la valeur d'exemple dans .env" >&2
  exit 1
fi

TARGET_FILE="cluster/infrastructure/configs/cloudflare-secret.sops.yaml"

# Génère le Secret Kubernetes en mémoire et le chiffre directement avec SOPS/Age sans jamais écrire le secret en clair sur disque
cat <<EOF | sops --encrypt --filename-override "${TARGET_FILE}" /dev/stdin > "${TARGET_FILE}"
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "${CLOUDFLARE_API_TOKEN}"
EOF

echo "✅ Secret Cloudflare chiffré avec SOPS/Age généré dans : ${TARGET_FILE}"
