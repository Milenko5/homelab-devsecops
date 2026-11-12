# ADR-0002 : Sélection de l'hyperviseur pour le laboratoire DevSecOps

## Statut

Accepté

## Contexte

Le laboratoire repose sur trois machines physiques Intel x86_64 dédiées disposant chacune de 16 Go de RAM sous Ubuntu 26.04 LTS. Bien que les machines soient dédiées au laboratoire, la pile DevSecOps complète (K3s HA, Cilium eBPF, Piraeus/LINSTOR DRBD 9, HashiCorp Vault, Kyverno, Prometheus) nécessite de maximiser chaque mégaoctet de RAM disponible pour les charges de travail Kubernetes tout en conservant la flexibilité du cycle de vie d'un hyperviseur (snapshots, reconstruction rapide via API).

Nous avons évalué deux options principales :
1. **Proxmox VE :** Une solution standard de l'industrie reposant sur KVM. Bien qu'éprouvée, cette solution introduit une surcharge (overhead) significative en termes de RAM et de CPU en raison de l'exécution d'un noyau complet pour chaque machine virtuelle.
2. **Incus (v7.5) :** Un gestionnaire de conteneurs système moderne (fork de LXD) qui partage le noyau Linux de l'hôte, permettant de faire tourner des systèmes d'exploitation entiers avec une empreinte mémoire quasi nulle à vide.

## Décision

Nous avons décidé d'utiliser **Incus 7.5** en mode autonome (standalone) sur chacune des trois machines physiques pour provisionner nos nœuds Kubernetes (12 Go de RAM par nœud K3s), en remplacement des hyperviseurs traditionnels comme Proxmox VE.

## Conséquences et Justifications

* **Efficacité et Performance (Near-Zero Overhead) :** En éliminant la surcharge d'émulation matérielle de KVM, les conteneurs système Incus atteignent des performances quasi identiques au bare-metal et permettent d'allouer 36 Go de RAM (3 × 12 Go) directement au cluster sur les 48 Go physiques.

* **Protection de l'Hôte via Cgroups v2 :** Incus plafonne strictement chaque nœud K3s à 12 Go de RAM et 4 vCPU, réservant mathématiquement 4 Go de RAM au système d'exploitation hôte Ubuntu 26.04 pour garantir sa stabilité en cas de fuite mémoire applicative dans Kubernetes.

* **Automatisation (API-First) :** L'API REST native d'Incus 7.5 permet à Terraform ( via le fournisseur `lxc/incus`) de provisionner, reconfigurer ou détruire les nœuds du cluster en quelques secondes.  Cette conception s'intègre de manière transparente avec notre stratégie d'Infrastructure as Code (IaC)

* **Indépendance des Hyperviseurs :** Les trois instances Incus opèrent de manière autonome, c'est-à-dire qu'elles ne sont pas liées en cluster. Elles agissent comme simple fournisseur de ressources. La Haute Disponibilité est gérée à la couche supérieure par K3s (`etcd`) et Piraeus/LINSTOR (DRBD 9), évitant toute complexité de double clustering au niveau de l'hyperviseur.
