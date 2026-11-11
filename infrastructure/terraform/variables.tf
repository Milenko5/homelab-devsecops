variable "state_passphrase" {
  description = "Phrase secrète (min. 16 caractères) pour le chiffrement AES-GCM du fichier d'état OpenTofu"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "La phrase secrète de chiffrement du state (TF_VAR_state_passphrase) doit contenir au moins 16 caractères."
  }
}

variable "incus_trust_token_hote_1" {
  description = "Jeton d'authentification (Trust Token) pour l'API Incus du PC 1"
  type        = string
  sensitive   = true
}

variable "incus_trust_token_hote_2" {
  description = "Jeton d'authentification (Trust Token) pour l'API Incus du PC 2"
  type        = string
  sensitive   = true
}

variable "incus_trust_token_hote_3" {
  description = "Jeton d'authentification (Trust Token) pour l'API Incus du PC 3"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Chemin vers la clé publique SSH générée pour Ansible"
  type        = string
  default     = "~/.ssh/id_ed25519_homelab.pub"
}

variable "passerelle_reseau" {
  description = "Adresse IP de votre routeur domestique (Gateway)"
  type        = string
  default     = "172.16.16.1"
}

variable "interface_pont_hote" {
  description = "Nom du pont réseau (bridge) configuré sur les hôtes Ubuntu pour l'accès LAN direct"
  type        = string
  default     = "br0"
}

variable "noeuds_k3s" {
  description = "Définition déclarative des 3 nœuds du plan de contrôle K3s HA"
  type = map(object({
    remote_incus  = string
    adresse_ip    = string
    limite_ram    = string
    limite_cpu    = string
    taille_disque = string
  }))

  default = {
    "k3s-srv-01" = {
      remote_incus  = "k8s01"
      adresse_ip    = "172.16.17.221"
      limite_ram    = "12GB"
      limite_cpu    = "4"
      taille_disque = "80GB"
    }
    "k3s-srv-02" = {
      remote_incus  = "k8s02"
      adresse_ip    = "172.16.17.222"
      limite_ram    = "12GB"
      limite_cpu    = "4"
      taille_disque = "80GB"
    }
    "k3s-srv-03" = {
      remote_incus  = "k8s03"
      adresse_ip    = "172.16.17.223"
      limite_ram    = "12GB"
      limite_cpu    = "4"
      taille_disque = "80GB"
    }
  }
}