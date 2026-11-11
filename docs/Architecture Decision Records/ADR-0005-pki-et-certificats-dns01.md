# ADR-0005 : Gestion de l'infrastructure à clé publique (PKI) en environnement privé

## Statut

Accepté

## Contexte

L'application des principes "Zero Trust" exige un chiffrement en transit (HTTPS/TLS) pour l'ensemble des services, y compris ceux destinés à un usage strictement interne. L'utilisation de certificats auto-signés n'est pas une pratique acceptable en entreprise. Nous devions automatiser l'obtention de certificats valides via Let's Encrypt. Toutefois, notre laboratoire étant privé, il n'expose pas les ports 80/443 à Internet, rendant le défi de validation standard (`HTTP-01`) inopérant.

## Décision

Nous avons décidé d'utiliser **Cert-Manager** configuré avec un `ClusterIssuer` Let's Encrypt utilisant le défi cryptographique **DNS-01**, adossé à l'API de **Cloudflare**.

## Conséquences et Justifications

- **Sécurité périmétrique maintenue :** Le défi DNS-01 permet à Cert-Manager de prouver la propriété du domaine en injectant temporairement un enregistrement TXT dans notre zone DNS Cloudflare via un jeton d'API. Let's Encrypt valide cet enregistrement publiquement sans jamais avoir besoin d'établir une connexion entrante vers notre infrastructure locale.
    
- **Automatisation complète :** Cert-Manager gère l'intégralité du cycle de vie des certificats (demande, validation, stockage sous forme de Secret Kubernetes, et renouvellement automatique avant expiration).
    
- **Moindre privilège :** Le jeton d'API Cloudflare utilisé est strictement limité en droits (lecture de la zone, édition du DNS) et cloisonné à un seul domaine.
