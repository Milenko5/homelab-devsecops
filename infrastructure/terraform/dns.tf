# -----------------------------------------------------------------------------
# 1. Gouvernance DNS Publique sur Cloudflare (Domaine sysdev.ca - Plan Gratuit)
# -----------------------------------------------------------------------------
data "cloudflare_zone" "sysdev" {
  name = var.domaine_principal
}

# Enregistrement CAA (RFC 8659) : Autorise exclusivement Let's Encrypt à émettre
# des certificats TLS standards pour sysdev.ca (Protection anti-usurpation PKI)
resource "cloudflare_record" "caa_letsencrypt_issue" {
  zone_id = data.cloudflare_zone.sysdev.id
  name    = "@"
  type    = "CAA"
  ttl     = 3600

  data {
    flags = "0"
    tag   = "issue"
    value = "letsencrypt.org"
  }
}

# Enregistrement CAA Wildcard : Autorise exclusivement Let's Encrypt à émettre
# des certificats Wildcard (*.lab.sysdev.ca)
resource "cloudflare_record" "caa_letsencrypt_issuewild" {
  zone_id = data.cloudflare_zone.sysdev.id
  name    = "@"
  type    = "CAA"
  ttl     = 3600

  data {
    flags = "0"
    tag   = "issuewild"
    value = "letsencrypt.org"
  }
}

# -----------------------------------------------------------------------------
# 2. Split-Horizon DNS Local sur AdGuard Home Primaire (172.16.16.5)
# -----------------------------------------------------------------------------
resource "adguard_rewrite" "primaire_wildcard_lab" {
  provider = adguard.primaire
  domain   = "*.${var.sous_domaine_lab}"
  answer   = var.ip_ingress_traefik
  enabled  = true
}

resource "adguard_rewrite" "primaire_apex_lab" {
  provider = adguard.primaire
  domain   = var.sous_domaine_lab
  answer   = var.ip_ingress_traefik
  enabled  = true
}

# -----------------------------------------------------------------------------
# 3. Split-Horizon DNS Local sur AdGuard Home Secondaire (172.16.16.6)
# -----------------------------------------------------------------------------
resource "adguard_rewrite" "secondaire_wildcard_lab" {
  provider = adguard.secondaire
  domain   = "*.${var.sous_domaine_lab}"
  answer   = var.ip_ingress_traefik
  enabled  = true
}

resource "adguard_rewrite" "secondaire_apex_lab" {
  provider = adguard.secondaire
  domain   = var.sous_domaine_lab
  answer   = var.ip_ingress_traefik
  enabled  = true
}
