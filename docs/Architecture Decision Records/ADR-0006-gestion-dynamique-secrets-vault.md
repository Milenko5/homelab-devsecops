# ADR-0006 : Centralisation et Injection des secrets d'entreprise

## Statut

Accepté

## Contexte

La gestion des données sensibles (clés d'API, mots de passe) est une vulnérabilité classique. Bien que nous utilisions SOPS pour le chiffrement statique dans notre dépôt GitOps, une architecture "Enterprise Grade" nécessite un moteur de secrets dynamique capable d'émettre, de révoquer et de faire pivoter des identifiants à la volée.

## Décision

Nous avons décidé de déployer **HashiCorp Vault** en Haute Disponibilité avec le stockage intégré Raft (Integrated Storage), et de l'interfacer avec Kubernetes via l'**External Secrets Operator (ESO)**.

## Conséquences et Justifications

- **Haute Disponibilité sans dépendance :** Le choix du stockage intégré Raft élimine le besoin de maintenir une base de données externe (comme Consul ou etcd dédiée) pour Vault. Les données chiffrées sont répliquées de manière résiliente entre les nœuds Vault.
    
- **Optimisation des ressources (ESO vs Sidecar) :** Historiquement, Vault injectait un conteneur secondaire (sidecar) dans chaque Pod nécessitant un secret, ce qui augmentait drastiquement l'empreinte mémoire. L'External Secrets Operator agit de manière asynchrone : il s'authentifie auprès de Vault, récupère la valeur, et génère un objet `Secret` Kubernetes natif. Cela sépare l'infrastructure de sécurité de la logique applicative et économise la RAM.
