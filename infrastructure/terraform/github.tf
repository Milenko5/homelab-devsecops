# -----------------------------------------------------------------------------
# 1. Dépôt GitHub public (Vitrine Portfolio DevSecOps)
# -----------------------------------------------------------------------------
resource "github_repository" "homelab" {
  # checkov:skip=CKV_GIT_1:Dépôt volontairement public (Vitrine Portfolio DevSecOps ; secrets chiffrés via SOPS/Age et OpenTofu AES-GCM)
  name        = "homelab-devsecops"
  description = "Laboratoire DevSecOps Bare-Metal Haute Disponibilité (K3s, Incus 7.5, Cilium eBPF, OpenTofu, Ansible, FluxCD, Vault, Kyverno)"
  visibility  = "public"

  has_issues      = true
  has_discussions = false
  has_projects    = false
  has_wiki        = false

  auto_init = false

  # Hygiène Git : historique linéaire, DCO Sign-off et contrôle humain avant fusion
  allow_merge_commit          = false
  allow_squash_merge          = true
  allow_rebase_merge          = true
  allow_auto_merge            = false
  delete_branch_on_merge      = true
  web_commit_signoff_required = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

# 1.a Étiquettes SEO du dépôt (Ressource dédiée v6+ remplaçant l'attribut déprécié : topics)
resource "github_repository_topics" "homelab_topics" {
  repository = github_repository.homelab.name
  topics = [
    "devsecops",
    "kubernetes",
    "k3s",
    "opentofu",
    "terraform",
    "ansible",
    "fluxcd",
    "gitops",
    "cilium",
    "ebpf",
    "incus",
    "zero-trust"
  ]
}

# 1.b Alertes de vulnérabilités Dependabot (Ressource dédiée v6+ remplaçant l'attribut déprécié : vulnerability_alerts)
resource "github_repository_vulnerability_alerts" "homelab_alerts" {
  repository = github_repository.homelab.name
}

# -----------------------------------------------------------------------------
# 2. Ruleset : Verrouillage Zero-Trust de la branche principale (main)
#    Aucun bypass_actors : Même l'admin doit passer par une PR signée GPG + CI verte
# -----------------------------------------------------------------------------
resource "github_repository_ruleset" "protection_branche_main" {
  name        = "verrouillage-zero-trust-main"
  repository  = github_repository.homelab.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true
    required_signatures     = true

    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      required_check {
        context = "Sécurité : Scan de Secrets (Gitleaks)"
      }
      required_check {
        context = "IaC : Validation OpenTofu (HCL) & TFLint"
      }
      required_check {
        context = "Config : Validation Ansible Lint"
      }
      required_check {
        context = "GitOps : Schémas Kubernetes & Audit Checkov"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# 3. Ruleset : Protection et immuabilité des tags de release (v*)
# -----------------------------------------------------------------------------
resource "github_repository_ruleset" "protection_tags_versions" {
  name        = "immuabilite-tags-versions"
  repository  = github_repository.homelab.name
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/tags/v*"]
      exclude = []
    }
  }

  rules {
    deletion            = true
    non_fast_forward    = true
    update              = true
    required_signatures = true
  }
}
