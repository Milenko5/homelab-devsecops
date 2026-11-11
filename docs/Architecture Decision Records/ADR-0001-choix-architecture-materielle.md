# ADR-0001 : Choix de l'architecture matérielle et Séparation des responsabilités
---
## Statut

Accepté

## Contexte

L'élaboration d'un laboratoire DevSecOps de pointe exige une infrastructure matérielle capable de supporter des charges de travail complexes, parmis lesquels figurent:
- bases de données distribuées
- moteurs eBPF
- stockage répliqué

Au départ, l'utilisation de deux nano-ordinateurs (Raspberry Pi 4) a été envisagé.  Cependant, une véritable architecture de haute disponibilité (HA) nécessite au minimum 3 nœuds physiques pour tolérer une panne matérielle sans perdre le quorum de la base de données `etcd`. Au départ, des services Docker déjà existant devaient cohabiter sur l'une des machines, ce qui aurait créé une asymétrie de ressources et des risques d'interférences réseau (`iptables`).

## Décision

Nous avons décidé de dédier exclusivement trois machines physiques Intel identiques basées sur l'architecture x86_64 (3 × 16 Go de RAM, soit 48 Go au total) au cluster Kubernetes. Les services Docker existant ont été migrés sur un Raspberry Pi indépendant afin d'isoler complètement les deux environnements.

## Conséquences et Justifications

* **Haute Disponibilité et Symétrie parfaite :** L'algorithme de consensus Raft utilisé par etcd exige un nombre impair de nœuds.  De ce fait la répartition du plan de contrôle sur 3 machines physiques dédiées de 16 Go garantit que la perte totale d'un PC maintient le quorum Raft à 2 membres sur 3. Chaque nœud K3s dispose exactement de la même enveloppe de ressources (12 Go de RAM alloués), assurant un ordonnancement prévisible et une continuité de service digne d'un environnement de production lors d'un basculement (failover).

* **Isolation des Domaines de Défaillance (Blast Radius) :** En déplaçant les conteneurs Docker existants sur un Raspberry Pi séparé, nous éliminons tout risque de conflit de pare-feu sur les ponts réseaux Linux et évitons que des services ne faisant pas partis du cluster DevSecOps consomme la mémoire du cluster.

* **Compatibilité logicielle maximale (amd64) :** L'architecture x86_64 sur les nœuds du cluster garantit une compatibilité native avec 100 % des outils de sécurité et images conteneurisées de l'industrie, tandis que le Raspberry Pi (ARM64) est dédié aux services légers hors cluster.

* **Performances Disque (IOPS) :** Les bases de données comme etcd et le stockage distribué en espace noyau (Piraeus / LINSTOR / DRBD 9) sont extrêmement sensibles à la latence de stockage. Les interfaces SATA/NVMe natives des trois machines Intel offrent la faible latence requise par `etcd` et par la réplication synchrone de DRBD 9, prévenant l'instabilité du plan de contrôle Kubernetes.
