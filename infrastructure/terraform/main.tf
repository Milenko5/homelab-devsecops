# 1. Création du profil système K3s sur chacun des 3 hôtes Incus
resource "incus_profile" "profil_k3s" {
  for_each = var.noeuds_k3s

  name        = "k3s-devsecops"
  remote      = each.value.remote_incus
  description = "Profil LXC optimisé pour K3s, Cilium eBPF et Piraeus/LINSTOR (DRBD 9)"

  config = {
    # Prérequis obligatoires pour exécuter des conteneurs dans LXC + Cilium eBPF + DRBD 9
    "limits.cpu"    = "4"
    "limits.memory" = "8GB"
    # Désactivation stricte du swap pour le conteneur
    "limits.memory.swap"  = "false"
    "security.privileged" = "true"
    "security.nesting"    = "true"
    # Incus demande automatiquement à l'hôte physique de charger ces modules noyau
    "linux.kernel_modules" = "br_netfilter,overlay,ip_tables,ip6_tables,netlink_diag,nf_nat,xt_conntrack,drbd,drbd_transport_tcp,dm_thin_pool,loop"
    "raw.lxc"              = <<-EOT
      lxc.apparmor.profile = unconfined
      lxc.cgroup2.devices.allow = a
      lxc.cap.drop =
      lxc.mount.auto = proc:rw sys:rw cgroup:rw
    EOT

    # Configuration Cloud-Init : injection de la clé SSH pour Ansible et installation de SSH
    "user.user-data" = <<-EOT
      #cloud-config
      package_update: true
      packages:
        - openssh-server
        - python3
        - curl
        - lvm2
        - thin-provisioning-tools
        - bind9-dnsutils
        - iputils-ping

      disable_root: true
      ssh_pwauth: false

      users:
        - name: ansible
          gecos: "Ansible Automation Service Account"
          groups: [sudo]
          shell: /bin/bash
          lock_passwd: true
          ssh_authorized_keys:
            - 'no-agent-forwarding,no-X11-forwarding ${trimspace(file(pathexpand(var.ssh_public_key_path)))}'

      write_files:
        - path: /etc/sudoers.d/90-ansible-homelab
          permissions: '0440'
          owner: root:root
          content: |
            Defaults:ansible env_reset
            ansible ALL=(root) NOPASSWD: ALL
        - path: /etc/ssh/sshd_config.d/99-homelab-hardening.conf
          permissions: '0600'
          owner: root:root
          content: |
            PermitRootLogin no
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            ChallengeResponseAuthentication no
            PubkeyAuthentication yes
            X11Forwarding no
            AllowAgentForwarding no
            AllowUsers ansible

      runcmd:
        - systemctl enable --now ssh
        - systemctl reload ssh
    EOT

    # Configuration réseau statique sur le LAN domestique via Cloud-Init
    "cloud-init.network-config" = <<-EOF
      version: 2
      ethernets:
        eth0:
          dhcp4: false
          addresses:
            - ${each.value.adresse_ip}/23
          gateway4: ${var.passerelle_reseau}
          nameservers:
            addresses: [172.16.16.5, 172.16.16.6]
    EOF
  }

  # Montage de /dev/kmsg requis par le processus Kubelet de Kubernetes
  device {
    name = "kmsg"
    type = "unix-char"
    properties = {
      source = "/dev/kmsg"
      path   = "/dev/kmsg"
    }
  }

  # Attachement au pont réseau physique pour exposer les annonces ARP L2 de Cilium sur le LAN
  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype                  = "bridged"
      parent                   = var.interface_pont_hote
      "security.mac_filtering" = "false" # Autorise les IPs virtuelles L2 de Cilium
    }
  }
}

# 2. Instanciation des 3 conteneurs système Ubuntu 26.04 LTS
resource "incus_instance" "noeud_k3s" {
  for_each = var.noeuds_k3s

  name     = each.key
  remote   = each.value.remote_incus
  image    = "images:ubuntu/26.04/cloud"
  type     = "container"
  profiles = ["default", incus_profile.profil_k3s[each.key].name]

  config = {
    "limits.memory"  = each.value.limite_ram
    "limits.cpu"     = each.value.limite_cpu
    "boot.autostart" = "true"
  }

  # Surcharge de la taille du disque racine pour héberger le stockage distribué Piraeus/LINSTOR (DRBD 9)
  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = "default"
      size = each.value.taille_disque
    }
  }
}
