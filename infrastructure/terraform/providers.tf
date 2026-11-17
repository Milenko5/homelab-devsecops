terraform {
  required_version = ">= 1.13.2"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.2.1"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.52.0"
    }
    adguard = {
      source  = "gmichels/adguard"
      version = "~> 1.7.1"
    }
  }

  # Fonctionnalité exclusive à OpenTofu : Chiffrement natif du State (DevSecOps)
  encryption {
    key_provider "pbkdf2" "homelab_key" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "methode_aes_gcm" {
      keys = key_provider.pbkdf2.homelab_key
    }
    state {
      method   = method.aes_gcm.methode_aes_gcm
      enforced = true
    }
    plan {
      method   = method.aes_gcm.methode_aes_gcm
      enforced = true
    }
  }
}

provider "incus" {
  # Stocke le certificat client mTLS dans ~/.ssh/incus-client pour survivre aux rebuilds du DevContainer
  config_dir                   = pathexpand("~/.ssh/incus-client")
  generate_client_certificates = true
  accept_remote_certificate    = true

  # Connexion autonome au PC Physique 1 (16 Go RAM - Dédié)
  remote {
    name    = "k8s01"
    address = "https://172.16.17.240:8443"
    token   = var.incus_trust_token_hote_1
  }

  # Connexion autonome au PC Physique 2 (16 Go RAM - Dédié)
  remote {
    name    = "k8s02"
    address = "https://172.16.17.241:8443"
    token   = var.incus_trust_token_hote_2
  }

  # Connexion autonome au PC Physique 3 (16 Go RAM - Dédié)
  remote {
    name    = "k8s03"
    address = "https://172.16.17.242:8443"
    token   = var.incus_trust_token_hote_3
  }
}

# Authentification automatique via la variable d'environnement GITHUB_TOKEN (.env)
provider "github" {}

# Authentification automatique via la variable d'environnement CLOUDFLARE_API_TOKEN (.env)
provider "cloudflare" {}

# Serveur DNS local AdGuard Home Primaire (172.16.16.5)
provider "adguard" {
  alias    = "primaire"
  host     = var.adguard_host_1
  username = var.adguard_username
  password = var.adguard_password
  scheme   = var.adguard_scheme
}

# Serveur DNS local AdGuard Home Secondaire (172.16.16.6)
provider "adguard" {
  alias    = "secondaire"
  host     = var.adguard_host_2
  username = var.adguard_username
  password = var.adguard_password
  scheme   = var.adguard_scheme
}
