# ADR-0003 : Stratégie d'automatisation de bout en bout, découplage et choix d'OpenTofu (HCL)

## Statut

Accepté

## Contexte

Un environnement DevSecOps moderne ne tolère aucune intervention manuelle récurrente sur les serveurs (pas de "ClickOps" ni de modifications via SSH). Nous devions définir une chaîne d'automatisation capable de transformer trois machines physiques en un cluster Kubernetes hautement disponible, sécurisé et prêt à recevoir des applications, tout en conservant une trace auditable de chaque configuration.

De plus, pour la brique de provisionnement d'infrastructure (IaC), trois options majeures ont été évaluées :

1. **Pulumi (Python / Go / TypeScript) :** Approche orientée génie logiciel utilisant des langages de programmation généralistes. Elle offre d'excellentes capacités de tests unitaires natifs (TDD avec *mocks*) et chiffre nativement les secrets à l'intérieur du fichier d'état (*State*) mais sans fournisseur officiel pour Incus.

2. **HashiCorp Terraform (HCL) :** Approche purement déclarative utilisant le langage dédié HCL (*HashiCorp Configuration Language*), qui constitue le standard majoritaire de l'industrie.  Mais stock en clair les secrets dans le fichier `terraform.tfstate`, et est sous licence propriétaire (BSL).

3. **OpenTofu (HCL) :** Fork open-source de Terraform (MPL 2.0) gouverné par la Linux Foundation et la CNCF, 100 % compatible avec l'écosystème HCL de Terraform mais intégrant nativement le chiffrement de bout en bout des fichiers d'état.

## Décision

Nous avons opté pour un découplage strict des responsabilités en utilisant trois outils distincts, chacun expert dans son domaine : 
- **OpenTofu** (compatible avec la syntaxe **Terraform HCL**)
- **Ansible**
- **FluxCD**

## Conséquences et Justifications

### 1. Pourquoi le langage HCL plutôt que Pulumi ?

* **Support natif et officiel de l'hyperviseur (`lxc/incus`) :** Le fournisseur Terraform pour Incus est développé et maintenu officiellement par l'équipe de Linux Containers. Pulumi ne dispose pas de fournisseur natif officiel pour Incus et nécessiterait l'utilisation d'un pont dynamique (*Terraform Provider Bridge*), ajoutant une couche d'abstraction et un risque lors des mises à jour.

* **Application du principe KISS (Keep It Simple, Stupid) :** Bien que Pulumi soit séduisant pour un profil de développeur, l'utilisation d'un langage impératif complet en IaC comporte un risque de sur-ingénierie (boucles complexes, héritage, abstractions excessives). La rigidité déclarative du langage HCL impose une structure plate, lisible et immédiatement compréhensible par toute équipe DevSecOps.

### 2. Pourquoi OpenTofu plutôt que HashiCorp Terraform ?

* **Chiffrement natif du State et du Plan (`AES-GCM` / `PBKDF2`) :** C'est l'argument de sécurité décisif.  Alors que Terraform écrit les valeurs sensibles (`sensitive = true`, comme nos jetons d'approbation API Incus) en texte clair dans le fichier `terraform.tfstate`, OpenTofu permet d'imposer (`enforced = true`) le chiffrement côté client en `AES-GCM` directement dans le bloc `terraform.encryption`. Même en cas d'exposition accidentelle du fichier `.tfstate`, aucun secret ne peut être compromis.

* **Cohérence Open-Source (Linux Foundation / CNCF) :** Tout comme Incus (fork communautaire de LXD), OpenTofu garantit une licence 100 % libre (MPL 2.0) sans restriction d'usage commercial, tout en préservant une transférabilité totale des compétences Terraform attendues sur le marché.

### 3. Séparation stricte des responsabilités (Le trio d'automatisation)

* **Ansible - Niveau 0 (Les Hôtes Physiques) :** Le playbook `playbook-hosts.yml` s'exécute via un compte de service dédié non-interactif (`ansible`, authentifié par clé Ed25519 restreinte par sous-réseau IP et options `no-agent-forwarding`). Il prépare et met à jour les 3 serveurs physiques Ubuntu 26.04 LTS, compile et charge le module noyau DRBD 9 (`drbd-dkms` pour Piraeus/LINSTOR), installe Incus 7.5 depuis le dépôt signé Zabbly et génère les jetons d'API.

- **OpenTofu / Terraform - Niveau 1 (Le Provisionneur API) :**  Utilisé exclusivement pour déclarer l'état de l'infrastructure externe. Il dialogue avec l'API REST de nos trois hôtes Incus pour instancier les conteneurs système, alloue les ressources (CPU/RAM/Disque), génère dynamiquement l'inventaire Ansible des conteneurs, et configure les services tiers (zones DNS (Cloudflare), dépôts GitHub, politiques HashiCorp Vault).

- **Ansible - Niveau 2 (L'Amorçage K3s HA) :** Une fois les conteneurs Incus créés, Ansible prend le relais sans agent (*agentless*) via SSH. Le playbook `playbook.yml` configure le système interne des conteneurs LXC, soit le système d'exploitation Ubuntu (prérequis LVM2 et vérification du module DRBD 9 pour Piraeus/LINSTOR, montage du système de fichiers eBPF, désactivation du swap) et orchestre l'amorçage initial du quorum `etcd` de K3s ainsi que du réseau Cilium.

- **FluxCD - Niveau 3 (L'Opérateur GitOps) :** Dès que l'API Kubernetes et le réseau CNI (Cilium eBPF) sont fonctionnels, Ansible se retire définitivement. FluxCD surveille le dépôt Git et réconcilie en continu, et de façon asynchrone, les composants internes (Traefik, Cert-Manager, Piraeus/LINSTOR, Vault, Kyverno) et les applications métiers.

> [!NOTE]
> Le compte de service `ansible` et le durcissement SSH (`PasswordAuthentication no`, `PermitRootLogin no`, `AllowUsers ansible`) sont désormais uniformisés sur les **deux couches** (Niveau 0 sur les hôtes physiques via `playbook-hosts.yml`, et Niveau 2 dans les conteneurs K3s via Cloud-Init).

### 3. Reprise après Sinistre (Disaster Recovery)

- Ce découplage garantit qu'en cas de perte totale du matériel, l'ensemble de l'infrastructure logicielle, depuis les conteneurs de l'hyperviseur jusqu'aux charges de travail Kubernetes, peut être reconstruit de manière déterministe en quelques minutes par l'exécution séquentielle de ces trois outils.