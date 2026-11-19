# ADR-0009 : Environnement d'administration isolé, reproductible et vérifié (DevContainer)

## Statut

Accepté

## Contexte

L'administration d'un cluster DevSecOps requiert plus d'une dizaine d'outils en ligne de commande (Terraform/OpenTofu, Ansible, kubectl, Helm, Flux, Cilium, SOPS, Age, Syft, Grype, Checkov, Cosign, Kubeconform, TFLint). Installer ces outils directement sur le système d'exploitation du poste de travail entraîne rapidement une dérive des versions ("Version Drift") et expose l'administrateur au risque d'exécuter un binaire corrompu ou altéré lors d'un téléchargement (`curl | bash`).

## Décision

Nous avons décidé d'encapsuler l'intégralité de la boîte à outils d'administration et de sécurité dans un conteneur de développement standardisé (DevContainer) basé sur **Ubuntu 26.04 LTS**, dont chaque binaire téléchargé est figé par version et **vérifié cryptographiquement par somme de contrôle SHA-256 avec arrêt immédiat en cas d'échec (Hard-Fail)**. Cette configuration sera versionnée directement dans le dépôt Git via un dossier `.devcontainer/` contenant un `Dockerfile` et un `devcontainer.json`.

## Conséquences et justifications

* **Intégrité des Binaires et Approche Fail-Fast (`sha256sum -c`) :** Aucun binaire n'est extrait ou rendu exécutable sans avoir préalablement validé son condensat SHA-256 contre le manifeste de contrôle officiel de l'éditeur. Le `Dockerfile` s'exécute sous `SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]` : la moindre divergence de hachage provoque l'arrêt immédiat de la construction de l'image. Cette même exigence de validation cryptographique est appliquée dans Ansible pour les empreintes GPG des dépôts Zabbly Incus et LINBIT DRBD 9.

* **Source Unique de Vérité (Single Source of Truth) & Maintenance Automatisée :** Les versions des 12 outils CLI sont centralisées uniquement via les arguments `ARG` de `.devcontainer/Dockerfile` et lues dynamiquement par tous les workflows GitHub Actions (`ci-infra.yml`, `supply-chain.yml`, `build-devcontainer.yml`). Un workflow planifié chaque lundi (`update-cli-tools.yml`) interroge les API officielles (GitHub Releases, Kubernetes, PyPI), crée un commit signé cryptographiquement (`Verified` via l'API GraphQL `createCommitOnBranch`, sans aucun PAT ni clé privée stockée dans GitHub Secrets) et ouvre automatiquement une Pull Request dès qu'une nouvelle version stable est publiée.

* **Audit Local Tolérance Zéro Avant Publication (`build-devcontainer.yml`) :** Lors de la publication de l'image DevContainer vers `ghcr.io`, celle-ci est d'abord compilée **localement uniquement** (`load: true`, `push: false`), inventoriée en SBOM SPDX par **Anchore Syft**, puis auditée par **Anchore Grype** (`--only-fixed --fail-on critical`, **sans aucune exception**). Si la moindre vulnérabilité critique corrigée subsiste dans l'OS ou dans l'un des binaires CLI tiers, le pipeline s'arrête immédiatement : aucune image vulnérable n'est publiée sur `ghcr.io` ni signée par **Sigstore Cosign**.

* **Reproductibilité garantie :** Tout membre de l'équipe DevSecOps clonant le dépôt et ouvrant le projet obtiendra instantanément un environnement de terminal disposant des versions exactes et identiques de Terraform/OpenTofu, Ansible, et des utilitaires Kubernetes.
    
* **Sécurité et isolation :** L'environnement de travail est isolé du système d'exploitation hôte. Les extensions de l'éditeur (Visual Studio Code) nécessaires au projet (comme le surlignage syntaxique pour Terraform/OpenTofu ou l'intégration de SOPS) sont installées automatiquement dans le conteneur sans altérer la configuration personnelle de l'utilisateur.
    
* **Isolation des Secrets Hôtes et Persistance Automatique (Kubeconfig & mTLS Incus) :** L'image Docker du DevContainer ne contient aucun secret. Les clés SSH, Age, GPG, le certificat client mTLS d'OpenTofu pour Incus (`~/.ssh/incus-client`, évitant la réutilisation des jetons d'enrôlement à usage unique) et la sauvegarde persistante du Kubeconfig (`~/.ssh/homelab.kubeconfig`, automatiquement restaurée vers `~/.kube/config` via `postStartCommand` lors de chaque reconstruction du conteneur) sont conservés dans le volume hôte monté `~/.ssh`, permettant de reconstruire, publier et signer l'image du DevContainer sur `ghcr.io` en toute sécurité et sans perte d'état.
