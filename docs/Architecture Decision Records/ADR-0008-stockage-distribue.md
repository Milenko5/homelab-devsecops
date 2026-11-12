# ADR-0008 : Choix du Système de stockage distribué (Piraeus Operator / LINSTOR & DRBD 9)

## Statut

Accepté (Remplace Longhorn CSI)

## Contexte

Afin de garantir la résilience des données applicatives (HashiCorp Vault, Prometheus, bases de données) lors de la perte physique d'un de nos 3 nœuds, une solution de stockage distribué (Container Storage Interface - CSI) est requise. Nous avons évalué quatre solutions majeures de l'écosystème Cloud Native :

1. **Rook-Ceph :** Le standard lourd de l'industrie, mais sa consommation mémoire et CPU (OSD, MON, MGR) est disproportionnée pour un cluster de 3 nœuds à 16 Go de RAM.
2. **OpenEBS Mayastor :** Basé sur SPDK (NVMe-oF en espace utilisateur), il réserve 100 % d'au moins un cœur CPU par nœud en *polling* continu et exige des disques physiques bruts dédiés.
3. **Longhorn (SUSE/Rancher) :** Simple à déployer sur `ext4`, mais son plan de données en espace utilisateur (Go + cibles iSCSI locales par volume) introduit une latence I/O notable et une surcharge CPU/RAM qui croît avec le nombre de volumes.
4. **Piraeus Operator v2 (LINSTOR / DRBD 9) :** Projet Sandbox de la CNCF orchestrant LINSTOR (plan de contrôle) et **DRBD 9** (plan de données directement intégré dans le noyau Linux).

## Décision

Nous avons décidé d'écarter Longhorn au profit de **Piraeus Operator v2 (LINSTOR / DRBD 9)** comme solution de stockage persistant CSI avec réplication synchrone à travers nos 3 machines physiques.

## Conséquences et justifications

* **Performances Bare-Metal en Espace Noyau (DRBD 9 vs iSCSI User-Space) :** Contrairement à Longhorn qui fait transiter chaque écriture par des processus Go et le démon `iscsid` en espace utilisateur, DRBD 9 réplique les blocs directement dans le noyau Linux (`drbd` et `drbd_transport_tcp`). Les performances IOPS et la latence d'écriture sont quasi identiques au stockage local.

* **Empreinte CPU et RAM Minimale :** Le plan de données DRBD 9 s'exécutant dans le noyau, la consommation processeur et mémoire au repos est quasi nulle. De plus, Piraeus Operator v2 stocke l'état de LINSTOR directement sous forme de ressources personnalisées Kubernetes (CRDs) sans nécessiter de base de données `etcd` ou SQL externe.

* **Architecture Hybride Hôte/Conteneur (Incus + DKMS) :** Les conteneurs système Incus partageant le noyau de l'hôte physique Ubuntu 26.04 LTS (avec *UEFI Secure Boot* désactivé dans le BIOS pour autoriser les modules DKMS non signés par Canonical), le module noyau **DRBD 9 (`drbd-dkms`)** est compilé depuis le dépôt signé LINBIT (format Deb822 avec séquencement `throttle: 1` et IPv4 forcé), substituent l'éventuel module `drbd` v8 natif, vérifié (`version: 9.x` dans `/proc/drbd`) et chargé directement sur les 3 serveurs physiques lors de l'Étape 0 Ansible (`playbook-hosts.yml`). Les conteneurs K3s héritent immédiatement du module noyau via le profil Incus (`linux.kernel_modules`) sans avoir besoin d'exécuter de conteneur privilégié de compilation (`drbd-module-loader` désactivé dans le cluster).

* **Haute Disponibilité et Auto-Guérison (Quorum DRBD) :** Avec un facteur de réplication sur nos 3 nœuds, le mécanisme natif de quorum et d'*auto-promote* de DRBD 9 garantit le basculement instantané des pods avec état (*StatefulSets*) en cas de perte électrique ou réseau d'un serveur physique, tout en prévenant mathématiquement tout scénario de *Split-Brain*.
