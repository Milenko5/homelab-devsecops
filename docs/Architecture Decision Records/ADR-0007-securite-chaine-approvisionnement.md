# ADR-0007 : Sécurité de la chaîne d'approvisionnement (GPG, Checkov, Anchore Syft/Grype, Cosign et Kyverno)

## Statut

Accepté

## Contexte

Dans une architecture GitOps où le dépôt Git pilote l'intégralité du cluster Kubernetes, la compromission du compte GitHub, l'altération d'un manifeste YAML, l'utilisation d'une action CI tierce compromise ou l'exécution d'une image de conteneur vulnérable constitue un risque critique. Il est impératif de garantir mathématiquement l'authenticité et l'intégrité de chaque artefact à deux niveaux : le **code source (Git/IaC)** et les **images de conteneurs (OCI)**.

De plus, suite aux incidents de sécurité ayant touché la chaîne d'approvisionnement de scanners monolithiques populaires (tels que la compromission d'actions liées à Trivy par des voleurs d'identifiants / *credential stealers*), nous appliquons une politique de défiance stricte envers les outils « tout-en-un » nécessitant de larges privilèges en CI/CD.

## Décision

Nous avons écarté Trivy au profit d'une chaîne d'approvisionnement "Zero Trust" découplée selon le principe de responsabilité unique :

1. **Intégrité Git de bout en bout (OpenPGP / GPG) :** Signature obligatoire de tous les commits et tags via une clé GPG dédiée, imposée en amont par un *GitHub Repository Ruleset* sans aucune exception (`bypass_actors` vide), et vérifiée en aval à l'intérieur même du cluster K3s par FluxCD.

2. **Audit Statique IaC & Secrets (Gitleaks & Checkov) :** Détection des secrets et analyse de conformité statique des manifestes Kubernetes et du code Terraform/OpenTofu via **Checkov**.

3. **Nomenclature (SBOM) et Analyse CVE Découplées (Anchore Syft & Grype) :** Génération du SBOM au format SPDX par **Syft**, suivie d'une analyse de vulnérabilités hors-ligne du fichier SBOM par **Grype**, signature *Keyless OIDC* via **Cosign**, et contrôle d'admission par **Kyverno**.

## Conséquences et justifications

- ### 1. Pourquoi remplacer Trivy par le trio Syft + Grype + Checkov ?

* **Réduction de la surface d'attaque et isolation des identifiants :** Dans notre pipeline `supply-chain.yml`, **Syft** inspecte l'image une seule fois pour produire un fichier local `sbom.spdx.json`. Le scanner de vulnérabilités **Grype** s'exécute ensuite exclusivement sur ce fichier JSON local (`grype sbom:./sbom.spdx.json`) sans nécessiter aucun accès au démon Docker ni aux jetons d'authentification du registre (`GITHUB_TOKEN`).

* **Spécialisation de l'audit IaC avec Checkov :** Plutôt que de dépendre d'un scanner de conteneurs pour auditer du code d'infrastructure, **Checkov** apporte des règles de gouvernance spécialisées pour Kubernetes, OpenTofu (HCL) et les Dockerfiles.

### 2. Ségrégation des Clés et Non-Répudiation Git (GPG vs SSH)

* **Séparation des usages cryptographiques :** La clé SSH (`ed25519`) est strictement cantonnée à l'authentification système locale (Ansible vers Incus), tandis qu'une clé **OpenPGP (GPG)** distincte est dédiée à la signature du code et des tags de version.

* **Absence de Bypass sur `main` :** Le Ruleset GitHub géré par Terraform/OpenTofu interdit tout push direct sur `main`. Tout changement doit obligatoirement passer par une Pull Request signée en GPG et validée par les 4 contrôles CI (`Gitleaks`, `Terraform/OpenTofu/TFLint`, `Ansible-Lint`, `Kubeconform/Checkov`).

* **Vérification Cryptographique In-Cluster par FluxCD :** La ressource `GitRepository` de FluxCD est configurée avec `spec.verify.mode: HEAD`. Le contrôleur Kubernetes vérifie localement la signature GPG de chaque commit contre le secret `flux-pgp-public-keys` avant d'autoriser toute réconciliation dans le cluster.

### 3. Sécurité des Images OCI ("Shift-Left" et "Shield-Right")

* **Coupe-circuit CI (Fail-Fast) :** Dans le workflow `supply-chain.yml`, l'étape de signature Cosign ne s'exécute que si l'analyse Grype sur le SBOM retourne zéro vulnérabilité critique corrigée (`--fail-on critical --only-fixed`). Une image vulnérable ne peut donc mathématiquement jamais être signée.

* **Signature Keyless (Fulcio & Rekor) et Admission Control (Kyverno) :** Les images et leurs attestations SBOM Syft sont signées sans clé privée permanente via OIDC et vérifiées à l'entrée du cluster K3s par Kyverno.
