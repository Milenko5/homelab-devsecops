output "recapitulatif_noeuds_k3s" {
  description = "Liste des nœuds K3s provisionnés et leurs adresses IP sur le LAN"
  value = {
    for nom, details in var.noeuds_k3s :
    nom => {
      hote_physique = details.remote_incus
      ip_lan        = details.adresse_ip
      ram_allouee   = details.limite_ram
    }
  }
}

# Génération automatique de l'inventaire pour Ansible
resource "local_file" "inventaire_ansible" {
  filename = "${path.module}/../ansible/inventory/hosts.yml"
  content  = <<-EOF
    ---
    # Fichier généré automatiquement par Terraform - Ne pas modifier manuellement
    k3s_cluster:
      children:
        server:
          hosts:
            k3s-srv-01:
              ansible_host: ${var.noeuds_k3s["k3s-srv-01"].adresse_ip}
              k3s_init_node: true
            k3s-srv-02:
              ansible_host: ${var.noeuds_k3s["k3s-srv-02"].adresse_ip}
              k3s_init_node: false
            k3s-srv-03:
              ansible_host: ${var.noeuds_k3s["k3s-srv-03"].adresse_ip}
              k3s_init_node: false
      vars:
        ansible_user: ansible
        ansible_ssh_private_key_file: ~/.ssh/id_ed25519_homelab
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
        k3s_api_vip: "${var.noeuds_k3s["k3s-srv-01"].adresse_ip}"
  EOF
}
