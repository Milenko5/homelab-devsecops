FROM ubuntu:26.04

# Activation stricte du mode Fail-Fast pour toutes les couches RUN
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# Évite les prompts interactifs lors de l'installation des paquets apt
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV EDITOR=vim

# Versions figées des outils (Reproductibilité ADR-0009)
ARG OPENTOFU_VERSION="1.13.2"
ARG KUBECTL_VERSION="v1.37.1"
ARG HELM_VERSION="v4.3.1"
ARG FLUX_VERSION="2.10.0"
ARG CILIUM_CLI_VERSION="v0.20.2"
ARG SOPS_VERSION="v3.13.3"
ARG SYFT_VERSION="1.56.0"
ARG GRYPE_VERSION="0.121.1"
ARG CHECKOV_VERSION="3.4.3"
ARG COSIGN_VERSION="v3.1.4"
ARG KUBECONFORM_VERSION="v0.8.0"
ARG TFLINT_VERSION="v0.65.0"

# 1. Paquets système de base, réseau, Python/Pipx/Ansible et Age
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    locales \
    curl \
    wget \
    git \
    vim \
    unzip \
    tar \
    gzip \
    jq \
    gnupg \
    openssh-client \
    iputils-ping \
    dnsutils \
    netcat-openbsd \
    bash-completion \
    age \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    ansible-core \
    ansible-lint \
    && rm -rf /var/lib/apt/lists/*

# 2. Installation de la collection Ansible requise par le rôle os_prep (sysctl, mount eBPF et modprobe)
RUN ansible-galaxy collection install ansible.posix community.general

# 3. Installation d'OpenTofu + Vérification SHA-256 (Hard-Fail) (avec lien symbolique 'terraform' pour la compatibilité CLI)
RUN ARCHIVE="tofu_${OPENTOFU_VERSION}_linux_amd64.zip" \
    && BASE_URL="https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}" \
    && curl -fsSLO "${BASE_URL}/${ARCHIVE}" \
    && curl -fsSLO "${BASE_URL}/tofu_${OPENTOFU_VERSION}_SHA256SUMS" \
    && sha256sum -c --ignore-missing "tofu_${OPENTOFU_VERSION}_SHA256SUMS" \
    && unzip "${ARCHIVE}" tofu \
    && mv tofu /usr/local/bin/tofu \
    && chmod +x /usr/local/bin/tofu \
    && ln -s /usr/local/bin/tofu /usr/local/bin/terraform \
    && rm -f "${ARCHIVE}" "tofu_${OPENTOFU_VERSION}_SHA256SUMS"

# 4. Installation de kubectl + Vérification SHA-256 (Hard-Fail)
RUN curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
    && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - \
    && mv kubectl /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && rm -f kubectl.sha256

# 5. Installation de Helm + Vérification SHA-256 (Hard-Fail)
RUN ARCHIVE="helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && curl -fsSLO "https://get.helm.sh/${ARCHIVE}" \
    && curl -fsSLO "https://get.helm.sh/${ARCHIVE}.sha256sum" \
    && sha256sum -c "${ARCHIVE}.sha256sum" \
    && tar -zxvf "${ARCHIVE}" \
    && mv linux-amd64/helm /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && rm -rf "${ARCHIVE}" "${ARCHIVE}.sha256sum" linux-amd64

# 6. Installation de Flux CLI + Vérification SHA-256 (Hard-Fail) (GitOps)
RUN ARCHIVE="flux_${FLUX_VERSION}_linux_amd64.tar.gz" \
    && BASE_URL="https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}" \
    && curl -fsSLO "${BASE_URL}/${ARCHIVE}" \
    && curl -fsSLO "${BASE_URL}/flux_${FLUX_VERSION}_checksums.txt" \
    && sha256sum -c --ignore-missing "flux_${FLUX_VERSION}_checksums.txt" \
    && tar -zxvf "${ARCHIVE}" -C /usr/local/bin/ flux \
    && chmod +x /usr/local/bin/flux \
    && rm -f "${ARCHIVE}" "flux_${FLUX_VERSION}_checksums.txt"

# 7. Installation de Cilium CLI + Vérification SHA-256 (Hard-Fail) (Gestion et dépannage eBPF / L2)
RUN ARCHIVE="cilium-linux-amd64.tar.gz" \
    && BASE_URL="https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}" \
    && curl -fsSLO "${BASE_URL}/${ARCHIVE}" \
    && curl -fsSLO "${BASE_URL}/${ARCHIVE}.sha256sum" \
    && sha256sum -c "${ARCHIVE}.sha256sum" \
    && tar -zxvf "${ARCHIVE}" -C /usr/local/bin/ cilium \
    && chmod +x /usr/local/bin/cilium \
    && rm -f "${ARCHIVE}" "${ARCHIVE}.sha256sum"

# 8. Installation de Mozilla SOPS + Vérification SHA-256 (Hard-Fail) (Chiffrement des secrets GitOps)
RUN BINAIRE="sops-${SOPS_VERSION}.linux.amd64" \
    && BASE_URL="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}" \
    && curl -fsSLO "${BASE_URL}/${BINAIRE}" \
    && curl -fsSLO "${BASE_URL}/sops-${SOPS_VERSION}.checksums.txt" \
    && sha256sum -c --ignore-missing "sops-${SOPS_VERSION}.checksums.txt" \
    && mv "${BINAIRE}" /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops \
    && rm -f "sops-${SOPS_VERSION}.checksums.txt"

# 9. Outils DevSecOps & Qualité (Anchore Syft, Anchore Grype, Checkov, Cosign, Kubeconform, TFLint) + Vérification SHA-256
RUN SYFT_ARC="syft_${SYFT_VERSION}_linux_amd64.tar.gz" \
    && curl -fsSLO "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/${SYFT_ARC}" \
    && curl -fsSLO "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_checksums.txt" \
    && sha256sum -c --ignore-missing "syft_${SYFT_VERSION}_checksums.txt" \
    && tar -zxvf "${SYFT_ARC}" -C /usr/local/bin/ syft \
    && rm -f "${SYFT_ARC}" "syft_${SYFT_VERSION}_checksums.txt" \
    \
    && GRYPE_ARC="grype_${GRYPE_VERSION}_linux_amd64.tar.gz" \
    && curl -fsSLO "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/${GRYPE_ARC}" \
    && curl -fsSLO "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_checksums.txt" \
    && sha256sum -c --ignore-missing "grype_${GRYPE_VERSION}_checksums.txt" \
    && tar -zxvf "${GRYPE_ARC}" -C /usr/local/bin/ grype \
    && rm -f "${GRYPE_ARC}" "grype_${GRYPE_VERSION}_checksums.txt" \
    \
    && COSIGN_BIN="cosign-linux-amd64" \
    && curl -fsSLO "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/${COSIGN_BIN}" \
    && curl -fsSLO "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign_checksums.txt" \
    && sha256sum -c --ignore-missing cosign_checksums.txt \
    && mv "${COSIGN_BIN}" /usr/local/bin/cosign \
    && chmod +x /usr/local/bin/cosign \
    && rm -f cosign_checksums.txt \
    \
    && KUBE_ARC="kubeconform-linux-amd64.tar.gz" \
    && curl -fsSLO "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/${KUBE_ARC}" \
    && curl -fsSLO "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/CHECKSUMS" \
    && sha256sum -c --ignore-missing CHECKSUMS \
    && tar -zxvf "${KUBE_ARC}" -C /usr/local/bin/ kubeconform \
    && rm -f "${KUBE_ARC}" CHECKSUMS \
    \
    && TFLINT_ARC="tflint_linux_amd64.zip" \
    && curl -fsSLO "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/${TFLINT_ARC}" \
    && curl -fsSLO "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/checksums.txt" \
    && sha256sum -c --ignore-missing checksums.txt \
    && unzip "${TFLINT_ARC}" -d /usr/local/bin/ \
    && rm -f "${TFLINT_ARC}" checksums.txt \
    \
    && PIPX_BIN_DIR=/usr/local/bin pipx install "checkov==${CHECKOV_VERSION}"

# 10. Confort d'utilisation (Alias kubectl, autocomplétion Bash et terminal GPG)
RUN echo 'source /usr/share/bash-completion/bash_completion' >> /root/.bashrc \
    && echo 'source <(kubectl completion bash)' >> /root/.bashrc \
    && echo 'source <(flux completion bash)' >> /root/.bashrc \
    && echo 'export GPG_TTY=$(tty)' >> /root/.bashrc \
    && echo 'alias k=kubectl' >> /root/.bashrc \
    && echo 'complete -o default -F __start_kubectl k' >> /root/.bashrc

WORKDIR /workspaces
