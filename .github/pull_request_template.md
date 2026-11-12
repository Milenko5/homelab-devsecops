## Description
Explication du changement apporté et de son contexte architectural.

## Type de changement
- [ ] Infrastructure (OpenTofu / Ansible)
- [ ] GitOps / Kubernetes (FluxCD / Cilium / Sécurité)
- [ ] Documentation / ADR

## Liste de vérification DevSecOps
- [ ] Tous les commits sont signés cryptographiquement (SSH / GPG)
- [ ] Aucun secret en clair n'est présent (chiffré via SOPS/Age)
- [ ] Les linters (`tofu validate`, `ansible-lint`, `kubeconform`) passent
