# ADR-0004 : Remplacement du CNI et Équilibrage de charge natif avec Cilium (eBPF)

## Statut

Accepté

## Contexte

Par défaut, la distribution K3s installe Flannel comme interface réseau (CNI), s'appuie sur `kube-proxy` (basé sur iptables) pour le routage interne, et nécessite l'ajout d'une solution tierce (comme MetalLB) pour attribuer des adresses IP routables sur le réseau local aux services de type `LoadBalancer`. Dans un contexte DevSecOps, nous recherchions une solution réseau offrant des performances optimales, une observabilité granulaire des flux, et une réduction de la complexité de la pile logicielle.

## Décision

Nous avons décidé de désactiver Flannel et `kube-proxy` lors de l'installation de K3s, et de les remplacer par **Cilium**, exécuté en mode `kubeProxyReplacement=true`. De plus, l'équilibrage de charge bare-metal sera géré nativement via la fonctionnalité **Cilium L2 Announcements**.

## Conséquences et Justifications

- **Performances eBPF :** Cilium exploite la technologie eBPF (Extended Berkeley Packet Filter) directement dans le noyau Linux de l'hôte. Cela permet d'attacher des règles de sécurité et de routage au niveau du noyau, offrant des débits réseaux supérieurs et une consommation processeur bien moindre comparé au routage traditionnel par iptables.
    
- **Unification de la pile (Consolidation) :** En activant les `l2announcements` via les ressources `CiliumLoadBalancerIPPool` (`172.16.17.20` à `.220`) et `CiliumL2AnnouncementPolicy` (sans filtre `serviceSelector` restrictif sur des labels inexistants, puisque `LoadBalancer` est un `spec.type`), Cilium prend en charge l'élection de leader et les réponses ARP sur l'interface `eth0` du réseau local. Cela élimine complètement le besoin d'installer, de configurer et de maintenir une solution tierce comme MetalLB.

- **Adaptation aux conteneurs système Incus/LXC :** Étant donné que les nœuds K3s s'exécutent dans des conteneurs LXC partageant le noyau hôte, le montage de `/sys/fs/bpf` en `rshared` et de `/proc/sys` en lecture/écriture est assuré en amont par un drop-in systemd (`10-incus-lxc.conf`), tandis que Cilium est déployé avec `bpf.autoMount.enabled=false`, `cgroup.autoMount.enabled=false` et `sysctlfix.enabled=false`. Sur le pont réseau Incus (`br0`), l'option `security.mac_filtering = "false"` autorise les annonces ARP des IPs virtuelles L2.
    
- **Observabilité Zero Trust :** L'écosystème Cilium inclut Hubble, un outil d'observabilité réseau qui permet de visualiser les flux de trafic inter-pods en temps réel et d'appliquer des politiques réseau (NetworkPolicies) strictes aux couches OSI 3, 4 et 7, une exigence absolue pour un environnement DevSecOps.
