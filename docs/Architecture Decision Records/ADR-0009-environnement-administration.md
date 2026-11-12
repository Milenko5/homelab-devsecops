# ADR-0009 : Environnement d'administration isolé, reproductible et vérifié (DevContainer)

## Statut

Accepté

## Contexte

L'administration d'un cluster DevSecOps requiert plus d'une dizaine d'outils en ligne de commande (Terraform/OpenTofu, Ansible, kubectl, Helm, Flux, Cilium, SOPS, Age, Syft, Grype, Checkov, Cosign, Kubeconform, TFLint). Installer ces outils directement sur le système d'exploitation du poste de travail entraîne rapidement une dérive des versions ("Version Drift") et expose l'administrateur au risque d'exécuter un binaire corrompu ou altéré lors d'un téléchargement (`curl | bash`).

## Décision

Nous avons décidé d'encapsuler l'intégralité de la boîte à outils d'administration et de sécurité dans un conteneur de développement standardisé (DevContainer) basé sur **Ubuntu 26.04 LTS**, dont chaque binaire téléchargé est figé par version et **vérifié cryptographiquement par somme de contrôle SHA-256 avec arrêt immédiat en cas d'échec (Hard-Fail)**. Cette configuration sera versionnée directement dans le dépôt Git via un dossier `.devcontainer/` contenant un `Dockerfile` et un `devcontainer.json`.

## Conséquences et justifications

* **Intégrité des Binaires et Approche Fail-Fast (`sha256sum -c`) :** Aucun binaire n'est extrait ou rendu exécutable sans avoir préalablement validé son condensat SHA-256 contre le manifeste de contrôle officiel de l'éditeur. Le `Dockerfile` s'exécute sous `SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]` : la moindre divergence de hachage provoque l'arrêt immédiat de la construction de l'image. Cette même exigence de validation cryptographique est appliquée dans Ansible pour les empreintes GPG des dépôts Zabbly Incus et LINBIT DRBD 9.

* **Zéro Dérive de Version (Immutable Toolbox) :** Les versions de tous les outils CLI sont figées via des arguments `ARG` explicites dans le `Dockerfile`, garantissant une parité stricte entre le poste local et les pipelines GitHub Actions.

* **Reproductibilité garantie :** Tout membre de l'équipe DevSecOps clonant le dépôt et ouvrant le projet obtiendra instantanément un environnement de terminal disposant des versions exactes et identiques de Terraform/OpenTofu, Ansible, et des utilitaires Kubernetes.
    
* **Sécurité et isolation :** L'environnement de travail est isolé du système d'exploitation hôte. Les extensions de l'éditeur (Visual Studio Code) nécessaires au projet (comme le surlignage syntaxique pour Terraform/OpenTofu ou l'intégration de SOPS) sont installées automatiquement dans le conteneur sans altérer la configuration personnelle de l'utilisateur.
    
* **Isolation des Secrets Hôtes et Persistance Automatique du Kubeconfig :** L'image Docker du DevContainer ne contient aucun secret. Les clés SSH, Age, GPG et la sauvegarde persistante du Kubeconfig (`~/.ssh/homelab.kubeconfig`, automatiquement restaurée vers `~/.kube/config` via `postStartCommand` lors de chaque reconstruction du conteneur) sont montées dynamiquement à l'exécution depuis l'hôte, permettant de publier et signer l'image du DevContainer sur `ghcr.io` en toute sécurité.
