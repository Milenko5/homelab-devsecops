# ADR-0006 : Centralisation et Injection des secrets d'entreprise

## Statut

Accepté

## Contexte

La gestion des données sensibles (clés d'API, mots de passe) est une vulnérabilité classique. Bien que nous utilisions SOPS pour le chiffrement statique dans notre dépôt GitOps, une architecture "Enterprise Grade" nécessite un moteur de secrets dynamique capable d'émettre, de révoquer et de faire pivoter des identifiants à la volée.

## Décision

Nous avons décidé de déployer **HashiCorp Vault** en Haute Disponibilité avec le stockage intégré Raft (Integrated Storage), et de l'interfacer avec Kubernetes via l'**External Secrets Operator (ESO)**.

## Conséquences et Justifications

- **Haute Disponibilité sans dépendance externe (Quorum Raft sur DRBD 9) :** Le choix du stockage intégré Raft (`3` réplicas : `vault-0`, `vault-1`, `vault-2` répartis sur nos 3 serveurs physiques) élimine le besoin de maintenir une base de données Consul externe. Chaque nœud Raft persiste ses données chiffrées sur un volume de `5 Gi` répliqué de façon synchrone par **Piraeus / LINSTOR (DRBD 9)** (`piraeus-storage-replicated`). De plus, la sonde `readinessProbe` est configurée avec `sealedcode=204&uninitcode=204` pour permettre la réconciliation GitOps initiale et l'accès à l'interface web (`https://vault.lab.sysdev.ca`) même lorsqu'un nœud attend son déverrouillage (*Unseal*).

- **Authentification Zero-Trust sans Jeton Statique (Kubernetes Auth Method) :** Plutôt que de stocker un jeton statique Vault dans un secret Kubernetes, Vault est configuré avec la méthode d'authentification native **`auth/kubernetes`** (`scripts/configurerVaultKubernetesAuth.sh`). L'opérateur **External Secrets Operator (ESO)** s'authentifie dynamiquement auprès de Vault en présentant le jeton JWT à courte durée de vie de son propre `ServiceAccount` Kubernetes (`external-secrets`), associé à une politique du moindre privilège (`eso-reader`, lecture seule sur `secret/data/*`).

- **Optimisation des ressources (ESO vs Sidecar) :** Historiquement, Vault injectait un conteneur secondaire (`vault-agent-injector`, ici explicitement désactivé via `injector.enabled: false`) dans chaque Pod nécessitant un secret, ce qui augmentait drastiquement l'empreinte mémoire. Avec ESO et notre `ClusterSecretStore` (`vault-backend`), un objet déclaratif `ExternalSecret` récupère de manière asynchrone les secrets depuis Vault et génère un objet `Secret` Kubernetes natif (`Owner`), séparant l'infrastructure de sécurité de la logique applicative.
