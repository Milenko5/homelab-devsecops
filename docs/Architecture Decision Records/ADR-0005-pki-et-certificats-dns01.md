# ADR-0005 : Architecture PKI (Cert-Manager DNS-01), Split-Horizon DNS (Cloudflare & AdGuard Home) et Ingress HTTPS (Traefik)

## Statut

Accepté

## Contexte

L'application des principes "Zero Trust" exige un chiffrement en transit (HTTPS/TLS) valide pour l'ensemble des services du cluster, sans obliger l'administrateur ou les utilisateurs à installer manuellement un certificat d'autorité racine locale sur chaque appareil (poste de travail, mobile, tablette). Par ailleurs :
1. Le laboratoire étant hébergé sur un réseau local privé (`172.16.16.0/23`), nous refusons d'exposer les ports entrants `80`/`443` sur le routeur domestique, ce qui rend le défi ACME `HTTP-01` inutilisable.
2. En local, le trafic vers `*.lab.sysdev.ca` doit être routé directement en couche 2 vers le contrôleur Ingress Traefik (`172.16.17.20`) via nos deux serveurs DNS internes **AdGuard Home** (`172.16.16.5` et `172.16.16.6`), tout en préparant une future exposition sélective de services vers l'extérieur par tunnel chiffré (*Cloudflare Tunnel*).

## Décision

Nous avons retenu une architecture **Split-Horizon DNS** et **PKI automatisée** reposant sur quatre composants :
1. **Cloudflare DNS (Offre Gratuite) + Enregistrements CAA gérés par OpenTofu (`dns.tf`)** pour la zone publique `sysdev.ca`.
2. **AdGuard Home en Haute Disponibilité (`172.16.16.5` et `172.16.16.6`) géré par OpenTofu (`gmichels/adguard`)** pour la résolution locale de `*.lab.sysdev.ca` et `lab.sysdev.ca` vers l'IP virtuelle Cilium L2 de Traefik (`172.16.17.20`).
3. **Cert-Manager (`ClusterIssuer` Let's Encrypt Production en mode `DNS-01`)** dont le jeton API Cloudflare est chiffré dans Git via **Mozilla SOPS & Age** (`cloudflare-secret.sops.yaml`).
4. **Traefik Proxy (v3)** configuré avec un certificat Wildcard unique (`wildcard-lab-sysdev-ca-tls`) attaché au magasin TLS par défaut (`TLSStore` `default`) et redirection permanente HTTP $\rightarrow$ HTTPS.

## Conséquences et Justifications

* **Certificats Publics Reconnus Partout (Zéro CA manuelle) :** Le défi `DNS-01` permet à Cert-Manager de prouver la propriété de `sysdev.ca` en créant temporairement un enregistrement TXT `_acme-challenge.lab.sysdev.ca` via l'API Cloudflare. Let's Encrypt valide cet enregistrement publiquement et émet un certificat Wildcard (`*.lab.sysdev.ca` et `lab.sysdev.ca`) reconnu nativement par tous les navigateurs et systèmes d'exploitation, sans ouvrir aucun port sur le pare-feu domestique.

* **Durcissement DNS CAA (RFC 8659) en IaC :** OpenTofu configure automatiquement des enregistrements `CAA` (`issue` et `issuewild`) sur la zone Cloudflare `sysdev.ca` autorisant exclusivement `letsencrypt.org` à émettre des certificats pour ce domaine, protégeant l'infrastructure contre toute émission frauduleuse par une autorité tierce.

* **Split-Horizon DNS Automatisé et Contournement DNS-01 (`extraArgs`) :**
  * Sur le LAN, OpenTofu programme simultanément les deux instances AdGuard Home (`adguard.primaire` et `adguard.secondaire`) pour résoudre `*.lab.sysdev.ca` vers `172.16.17.20`.
  * Afin d'éviter que cette réécriture Wildcard locale n'intercepte l'auto-vérification (*self-check*) du défi ACME par Cert-Manager, ce dernier est configuré avec `--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53` et `--dns01-recursive-nameservers-only`, forçant l'interrogation directe des serveurs DNS publics lors des validations Let's Encrypt.

* **Chiffrement en Mémoire du Jeton API (SOPS / Age) :** Le jeton API Cloudflare (limité au strict moindre privilège `Zone:Read` et `DNS:Edit` sur `sysdev.ca`) est chiffré à la volée en mémoire via le script `scripts/chiffrerSecretCloudflare.sh` (`sops --encrypt /dev/stdin`) sans jamais écrire le secret en clair sur le disque.

* **Mutualisation TLS avec Traefik `TLSStore` :** En déclarant le secret `wildcard-lab-sysdev-ca-tls` dans l'objet `TLSStore` `default` de Traefik, tout nouvel `Ingress` ou `IngressRoute` déployé dans le cluster bénéficie automatiquement du chiffrement HTTPS Let's Encrypt sans dupliquer les requêtes de certificats (évitant ainsi d'atteindre les limites de débit *Rate Limits* de Let's Encrypt).

