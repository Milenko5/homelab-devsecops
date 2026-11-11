# Guide d'amorçage (Jour 0) et Runbook d'initialisation

Ce document décrit les étapes manuelles requises lors du « Jour 0 » avant de lancer l'automatisation complète de l'infrastructure. L'objectif est de préparer les trois hôtes physiques Ubuntu, d'installer Incus 7.5, l'environnement d'administration isolé (DevContainer), générer les secrets cryptographiques et lancer l'automatisation complète de l'infrastructure (des hôtes physiques Ubuntu 26.04 LTS jusqu'à FluxCD) sans jamais exposer les secrets dans le dépôt Git.

---

## 1. Topologie Réseau et Plan d'Adressage (IPAM)

Avant de commencer, assurez-vous que la configuration suivante est appliquée sur votre routeur domestique / pare-feu afin d'éviter tout conflit d'adresses IP :

| Composant / Rôle                  | Adresse IP / Plage                    | Interface / Notes                              |
| :-------------------------------- | :------------------------------------ | :--------------------------------------------- |
| **Sous-réseau LAN & Passerelle**  | `172.16.16.0/23` (GW : `172.16.16.1`) | Réseau physique local                          |
| **Plage DHCP du Routeur**         | `172.16.16.10` à `172.16.16.150`      | Plage réservée aux appareils domestiques       |
| **Hôte Physique 1 (Intel 16 Go)** | `172.16.17.240` (Statique)            | Pont `br0` — Dédié — API Incus 7.5 sur `:8443` |
| **Hôte Physique 2 (Intel 16 Go)** | `172.16.17.241` (Statique)            | Pont `br0` — Dédié — API Incus 7.5 sur `:8443` |
| **Hôte Physique 3 (Intel 16 Go)** | `172.16.17.242` (Statique)            | Pont `br0` — Dédié — API Incus 7.5 sur `:8443` |
| **Nœud K3s 1 (`k3s-srv-01`)**     | `172.16.17.221` (Statique)            | Conteneur LXC sur Hôte 1 (12 Go RAM / 80 Go)   |
| **Nœud K3s 2 (`k3s-srv-02`)**     | `172.16.17.222` (Statique)            | Conteneur LXC sur Hôte 2 (12 Go RAM / 80 Go)   |
| **Nœud K3s 3 (`k3s-srv-03`)**     | `172.16.17.223` (Statique)            | Conteneur LXC sur Hôte 3 (12 Go RAM / 80 Go)   |
| **Pool Cilium LoadBalancer (L2)** | `172.16.17.20` à `172.16.17.220`      | **Exclu du DHCP** — Annonces ARP Cilium        |

---
## 2. Préparation des 3 Hôtes Physiques (Ubuntu 26.04 LTS)

Les trois machines physiques doivent être installées avec **Ubuntu Server 26.04 LTS (`resolute`)**, formatées en **ext4**, **sans partition swap**, avec **UEFI Secure Boot désactivé dans le BIOS** (requis pour charger les modules noyau hors-arbre compilés par DKMS comme **DRBD 9** sans rejet `Key was rejected by service`), le serveur OpenSSH activé et le pont réseau `br0` configuré.

Toute la configuration système (désactivation du swap, modules noyau, paramètres `sysctl`, mises à jour APT et installation d'**Incus 7.5**) est automatisée par le playbook Ansible `playbook-hosts.yml`.

Connectez-vous en SSH sur chacun des 3 serveurs (`.240`, `.241` et `.242`) pour exécuter les 5 sous-étapes suivantes :
### 2.1 Configuration du pont réseau `br0` avec Netplan

Sur chacun des 3 serveurs physiques (`.240`, `.241` et `.242`), identifiez le nom de votre interface réseau physique avec `ip -br link` (ex. `enp3s0` ou `eno1`), puis éditez `/etc/netplan/00-installer-config.yaml` :

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0: # <-- Remplacez par le nom de votre interface physique
      dhcp4: false
      dhcp6: false

  bridges:
    br0:
      interfaces: [enp3s0] # <-- Même nom d'interface ici
      dhcp4: false
      addresses:
        - 172.16.17.240/23   # <-- .240 (PC 1), .241 (PC 2), ou .242 (PC 3)
      routes:
        - to: default
          via: 172.16.16.1
      nameservers:
        addresses: [172.16.16.5, 172.16.16.6]
      parameters:
        stp: false
        forward-delay: 0
```

Appliquez la configuration de manière sécurisée (retour arrière automatique après 120 secondes en cas de coupure SSH) :

```bash
# Validation syntaxique stricte (échoue sans couper le réseau en cas d'erreur YAML)
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan generate

# Activation du pont br0 (netplan try ne supportant pas le bloc parameters sur un bridge)
sudo netplan apply
ip -br addr show br0
```

### 2.2 Création et durcissement de l'utilisateur de service `ansible`

Pour éviter d'utiliser le compte administrateur interactif lors de l'automatisation et tracer toutes les actions de gestion de configuration dans `/var/log/auth.log`, créez un compte de service dédié `ansible` (sans mot de passe) sur chacun des 3 serveurs physiques (`.240`, `.241` et `.242`) :

```bash
# 1. Création du groupe anticipé 'incus-admin' et de l'utilisateur système 'ansible' (sans mot de passe)
sudo groupadd --system incus-admin
sudo adduser --disabled-password --gecos "Ansible Automation Service Account" ansible
sudo usermod -aG incus-admin ansible

# 2. Préparation du dossier SSH avec permissions strictes (0700)
sudo install -d -m 0700 -o ansible -g ansible /home/ansible/.ssh

# 3. Configuration sudoers durcie (exige un contrôle syntaxique via visudo -cf)
cat << 'EOF' | sudo tee /etc/sudoers.d/90-ansible-homelab >/dev/null
# Durcissement du compte d'automatisation Ansible
# Si sudo-rs est utiliser cette option est désactiver de façon interne
# Defaults:ansible !requiretty
Defaults:ansible env_reset
Defaults:ansible passwd_timeout=0
ansible ALL=(root) NOPASSWD: ALL
EOF

sudo chmod 0440 /etc/sudoers.d/90-ansible-homelab
sudo visudo -cf /etc/sudoers.d/90-ansible-homelab
```

---
## 3. Lancement de l'environnement d'administration (DevContainer)

Sur votre poste de travail (machine d'administration), aucun outil CLI n'a besoin d'être installé localement (voir `ADR-0009`). Vous devez uniquement disposer de **Docker** et de **Visual Studio Code** avec l'extension `Dev Containers` (`ms-vscode-remote.remote-containers`).

1. Assurez-vous que le dossier `~/.ssh` existe sur votre poste de travail :

```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
```

2. Ouvrez ce dépôt dans VS Code et cliquez sur **Reopen in Container** (ou via `Ctrl+Shift+P` -> **Dev Containers: Rebuild and Reopen in Container**).

3. **Toutes les commandes de la suite de ce guide doivent être exécutées depuis le terminal intégré du DevContainer.**


---

## 4. Ségrégation et Configuration des Clés Cryptographiques (SSH, GPG & Age)

Nous appliquons une séparation stricte des rôles cryptographiques (voir `ADR-0007`) : **SSH** pour l'administration système locale, **GPG** pour la signature du code Git, et **Age** pour le chiffrement des secrets Kubernetes.

### 4.1 Clé SSH dédiée à Ansible (Administration Système)

Générez la paire de clés SSH puis copiez la clé publique sur vos 3 serveurs Ubuntu physiques ((en passant une dernière fois par votre compte initial) :

```bash
# 1. Génération de la clé SSH Ed25519
ssh-keygen -t ed25519 -C "ansible-homelab" -f ~/.ssh/id_ed25519_homelab -N ""

# 2. Injection de la clé publique dans le compte 'ansible' des 3 hôtes (restreinte au sous-réseau LAN)
PUBKEY="no-agent-forwarding,no-X11-forwarding $(cat ~/.ssh/id_ed25519_homelab.pub)"

for ip in 172.16.17.240 172.16.17.241 172.16.17.242; do
  ssh -t ubuntu@$ip "sudo install -d -m 0700 -o ansible -g ansible /home/ansible/.ssh && echo '$PUBKEY' | sudo tee /home/ansible/.ssh/authorized_keys >/dev/null && sudo chmod 0600 /home/ansible/.ssh/authorized_keys && sudo chown ansible:ansible /home/ansible/.ssh/authorized_keys"
done

# 3. Test de connexion directe et sans mot de passe avec le compte 'ansible'
for ip in 172.16.17.240 172.16.17.241 172.16.17.242; do
  ssh -i ~/.ssh/id_ed25519_homelab ansible@$ip "sudo whoami && id"
done
```

> [!Note] Une fois l'Étape 0 (`playbook-hosts.yml`) exécutée, la connexion par mot de passe et le compte initial `ubuntu` sont définitivement désactivés en SSH au profit exclusif du compte `ansible` par clé Ed25519.

### 4.2 Clé GPG dédiée à la signature des commits Git et vérification FluxCD

Le Ruleset GitHub (`github.tf`) et le contrôleur FluxCD exigent que 100 % des commits et des tags soient signés avec votre clé GPG :

```bash
# 1. Identifiez l'ID long (16 caractères hexadécimaux) de votre clé GPG
gpg --list-secret-keys --keyid-format=long

# 2. Configurez Git pour signer systématiquement tous les commits et tags avec GPG
git config --global gpg.format openpgp
git config --global user.signingkey <VOTRE_GPG_KEY_ID>
git config --global commit.gpgsign true
git config --global tag.gpgSign true

# 3. Exportez votre clé publique GPG (pour GitHub et pour le secret Kubernetes FluxCD)
gpg --armor --export <VOTRE_GPG_KEY_ID> > ~/.ssh/flux-gpg-pub.asc
```
> [!Note] *(Ajoutez le contenu de `~/.ssh/flux-gpg-pub.asc` dans **GitHub Settings -> SSH and GPG keys -> New GPG key**).*

> [!Warning] Votre clef GPG doit être générer à l'extérieur du devcontainer.  En l'exportant dans le répertoire ~/.ssh de votre utilisateur, elle sera accessible dans le devcontainer.
### 4.3 Clé de chiffrement Age pour Mozilla SOPS (Secrets Kubernetes)

```bash
age-keygen -o ~/.ssh/sops-age.txt
```

> [!Important] Copiez la clé publique affichée dans le terminal (commençant par `age1...`) et remplacez la valeur correspondante dans le fichier `.sops.yaml` situé à la racine du dépôt.

---

## 5. Configuration des variables secrètes (`.env`)

Créez un fichier `.env` à la racine du projet (ignoré par Git via `.gitignore`). Il contient la phrase secrète de chiffrement du fichier d'état OpenTofu (`AES-GCM`).  Nous y collerons les 3 jetons Incus générés automatiquement par Ansible à l'Étape 0 de la section 6 :

```bash
# 1. Phrase secrète (min. 16 caractères) pour chiffrer le fichier terraform.tfstate (OpenTofu)
export TF_VAR_state_passphrase="$(openssl rand -base64 32)"

# 2. Jetons d'authentification API Incus 7.5 (affichés par playbook-hosts.yml à l'Étape 0)
export TF_VAR_incus_trust_token_hote_1="COLLEZ_LE_JETON_DU_PC_1_ICI"
export TF_VAR_incus_trust_token_hote_2="COLLEZ_LE_JETON_DU_PC_2_ICI"
export TF_VAR_incus_trust_token_hote_3="COLLEZ_LE_JETON_DU_PC_3_ICI"

# 3. GitHub Personal Access Token (droits "repo" pour FluxCD et Terraform)
# Ou la permission `Administration: Read and write` si un token `Fine-grained` est utilisé
export GITHUB_TOKEN="ghp_votre_jeton_github"

# 4. Cloudflare API Token (droits Zone:Read et DNS:Edit pour Cert-Manager DNS-01)
export CLOUDFLARE_API_TOKEN="votre_jeton_cloudflare"
```

> [!Note]
> 1. **GITHUB_TOKEN=** : Générez un _Personal Access Token_ (PAT) classique sur GitHub avec les droits `repo` complets et `workflow`.
   > 
>2. **CLOUDFLARE_API_TOKEN=** : Générez un jeton personnalisé sur Cloudflare avec les permissions strictes suivantes :
 >>   - Zone -> DNS -> Edit
 >>   - Zone -> Zone -> Read        
 >>   - Inclure -> Toutes les zones (ou spécifiquement votre domaine de laboratoire). 

---

## 6. Séquence d'exécution du déploiement

Le déploiement complet du cluster et sa maintenance suivent ces étapes automatisées :

### Étape 0 : Préparation des hôtes physiques, compilation DRBD 9 et installation d'Incus 7.5 (Ansible)

Ce playbook se connecte via le compte de service dédié `ansible`, met à jour Ubuntu 26.04 LTS, désactive le swap, compile et charge le module noyau **DRBD 9 (`drbd-dkms`)** depuis le dépôt signé LINBIT (pour Piraeus/LINSTOR), installe **Incus 7.5** depuis le dépôt signé Zabbly, initialise le stockage `ext4` (`--preseed`) et affiche les 3 jetons d'approbation pour Terraform/OpenTofu :

```bash
cd infrastructure/ansible
ansible-playbook -i inventory/baremetal.yml playbook-hosts.yml
cd ../..
```

> [!Important] Copiez les 3 jetons affichés à la fin du playbook dans votre fichier `.env`, puis chargez les variables :

> [!Note] Il est possible d'effectuer un dryrun, pour parer à d'éventuelle erreur, il suffit d'ajouter `--check --diff` à votre commande `ansible-playbook`

```bash
source .env
```

#### **Opération de Jour 2 (Mise à jour système Ubuntu & Incus sans coupure) :**

Pour mettre à jour mensuellement les paquets APT et le noyau des 3 machines physiques en les redémarrant **une par une** (`serial_update=1`) afin de préserver le quorum K3s :

```bash
ansible-playbook -i infrastructure/ansible/inventory/baremetal.yml infrastructure/ansible/playbook-hosts.yml --tags update -e serial_update=1
```

### Étape 1 : Provisionnement des conteneurs système K3s et des Rulesets GitHub (OpenTofu/Terraform)

```bash
# Vérification de l'accès à l'API des 3 hôtes Incus 7.5
nc -zv 172.16.17.240 8443 && nc -zv 172.16.17.241 8443 && nc -zv 172.16.17.242 8443

# Création des profils, des 3 conteneurs Ubuntu 26.04 (12 Go RAM) et de l'inventaire Ansible
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
cd ../..
```

### Étape 2 : Amorçage du quorum K3s Haute Disponibilité (Ansible)

```bash
cd infrastructure/ansible
ansible-playbook playbook.yml
cd ../..

# Vérification des 3 nœuds (statut NotReady normal tant que Cilium n'est pas installé)
kubectl get nodes -o wide
```

### Étape 3 : Amorçage du réseau eBPF et du LoadBalancer L2 (Cilium)

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="172.16.17.221" \
  --set k8sServicePort=6443 \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set bpf.autoMount.enabled=false \
  --set l2announcements.enabled=true \
  --set externalIPs.enabled=true \
  --set k8sClientRateLimit.qps=10 \
  --set k8sClientRateLimit.burst=20 \
  --set operator.replicas=2 \
  --set operator.rollOutPods=true \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set rollOutCiliumPods=true
```

Surveillez le démarrage des pods Cilium et le passage des 3 noeuds à `Ready`

```sh
kubectl -n kube-system rollout status ds/cilium --timeout=180s
kubectl get nodes -o wide
```

Vérifier le remplacement eBPF de kube-proxy et la santé de Cilium

```sh
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief
kubectl get ciliumloadbalancerippools,ciliuml2announcementpolicies -A
```

La première commande doit retourner `OK`, c'est à dire que Cilium a pris le relais de `kube-proxy`.
La seconde commande doit vous indiquez que vous avez 201 adresses ip de disponible.
### Étape 4 : Amorçage GitOps Zero-Trust (FluxCD, SOPS/Age & Vérification GPG)

Puisque notre Ruleset GitHub interdit tout push direct non signé sur `main` (aucun `bypass_actors`), nous installons les contrôleurs FluxCD et injectons nos deux clés cryptographiques (**Age** pour le déchiffrement des secrets, et **GPG publique** pour la vérification des commits Git) :

```bash
# 1. Vérification des prérequis et installation des contrôleurs FluxCD dans le cluster
flux check --pre
flux install

# 2. Injection de la clé privée Age (pour le déchiffrement SOPS par kustomize-controller)
cat ~/.ssh/sops-age.txt | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin

# 3. Injection de votre clé publique GPG (pour la vérification des commits par source-controller)
kubectl create secret generic flux-pgp-public-keys \
  --namespace=flux-system \
  --from-file=my-git-pubkey.asc=$HOME/.ssh/flux-gpg-pub.asc

# 4. Application de la synchronisation GitOps (une fois vos fichiers cluster/ fusionnés sur main via une PR signée GPG)
kubectl apply -f cluster/clusters/homelab/flux-system/
```