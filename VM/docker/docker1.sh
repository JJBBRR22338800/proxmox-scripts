#!/usr/bin/env bash
set -Eeuo pipefail

# Debian prüfen
source /etc/os-release

if [[ "$ID" != "debian" ]]; then
    echo "Fehler: Dieses Skript ist für Debian vorgesehen."
    exit 1
fi

# Root-Rechte prüfen
if [[ "$EUID" -ne 0 ]]; then
    echo "Bitte mit sudo ausführen."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "=== System aktualisieren ==="
apt-get update
apt-get upgrade -y

echo "=== Basiswerkzeuge installieren ==="
apt-get install -y \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    openssh-client \
    nano \
    vim \
    htop \
    btop \
    jq \
    unzip \
    zip \
    tar \
    rsync \
    dnsutils \
    iproute2 \
    iputils-ping \
    net-tools \
    lsof \
    bash-completion \
    qemu-guest-agent

echo "=== Konkurrierende Docker-Pakete entfernen ==="

for pkg in \
    docker.io \
    docker-compose \
    docker-doc \
    podman-docker \
    containerd \
    runc
do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null \
        | grep -q "install ok installed"; then
        apt-get remove -y "$pkg"
    fi
done

echo "=== Docker-Repository einrichten ==="

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "=== Docker installieren ==="

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo "=== Docker aktivieren ==="
systemctl enable --now docker

echo "=== QEMU Guest Agent prüfen ==="
# Wird bei Debian häufig über eine statische Unit gestartet.
# Nicht versuchen, die statische Unit direkt zu aktivieren.
if systemctl is-active --quiet qemu-guest-agent; then
    echo "QEMU Guest Agent läuft."
else
    echo "QEMU Guest Agent ist noch nicht aktiv."
    echo "Prüfe, ob der Agent in den Proxmox-VM-Optionen aktiviert ist."
fi

echo "=== Installierte Versionen ==="
docker --version
docker compose version
git --version

echo "=== Docker Funktionstest ==="
docker run --rm hello-world

echo "=== Installation abgeschlossen ==="
