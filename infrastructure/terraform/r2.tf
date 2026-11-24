# -----------------------------------------------------------------------------
# Stockage Objet S3 Cloudflare R2 pour sauvegardes chiffrées (etcd + Vault Raft)
# Optionnel : activable via TF_VAR_r2_enabled=true (requiert droit API Workers R2 Storage:Edit)
# -----------------------------------------------------------------------------
resource "cloudflare_r2_bucket" "homelab_backups" {
  count      = var.r2_enabled ? 1 : 0
  account_id = data.cloudflare_zone.sysdev.account_id
  name       = var.r2_backup_bucket_name
  location   = "ENAM"
}
