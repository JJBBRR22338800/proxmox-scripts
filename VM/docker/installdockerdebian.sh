#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "FEHLER: Installation in Zeile $LINENO abgebrochen." >&2' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Bitte mit sudo ausführen: sudo bash $0" >&2
  exit 1
fi

source /etc/os-release
if [[ ${ID:-} != debian ]]; then
  echo "Dieses Skript unterstützt nur Debian." >&2
  exit 1
fi

if [[ ${VERSION_CODENAME:-} != trixie ]]; then
  echo "Hinweis: Dieses Skript ist für Debian 13 (trixie) ausgelegt. Gefunden: ${PRETTY_NAME:-unbekannt}." >&2
  read -r -p 'Trotzdem fortfahren? [j/N] ' confirm
  [[ $confirm == [jJyY] ]] || exit 1
fi

# GitHub-Schlüssel gehört dem normalen Benutzer, nicht root.
TARGET_USER=${SUDO_USER:-}
if [[ -z $TARGET_USER || $TARGET_USER == root ]]; then
  read -r -p 'Normalen Debian-Benutzer für den GitHub-SSH-Schlüssel eingeben: ' TARGET_USER
fi
if ! id "$TARGET_USER" &>/dev/null || [[ $TARGET_USER == root ]]; then
  echo "Fehler: Ein existierender Benutzer ungleich root ist erforderlich." >&2
  exit 1
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -z $TARGET_HOME || ! -d $TARGET_HOME ]]; then
  echo "Home-Verzeichnis des Benutzers nicht gefunden." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo '=== System aktualisieren ==='
apt-get update
apt-get upgrade -y

echo '=== Basiswerkzeuge installieren ==='
apt-get install -y ca-certificates curl wget git gnupg openssh-client nano vim htop btop jq unzip zip tar rsync dnsutils iproute2 iputils-ping net-tools lsof bash-completion qemu-guest-agent

echo '=== Konkurrierende Docker-Pakete entfernen ==='
for pkg in docker.io docker-compose docker-doc podman-docker containerd runc; do
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -qx 'install ok installed'; then
    apt-get remove -y "$pkg"
  fi
done

echo '=== Offizielles Docker-Repository einrichten ==='
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Logrotation vor dem ersten Containerstart konfigurieren.
echo '=== Docker-Logging konfigurieren ==='
mkdir -p /etc/docker
if [[ ! -e /etc/docker/daemon.json ]]; then
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local"
}
EOF
else
  echo 'Bestehende /etc/docker/daemon.json bleibt unverändert. Logrotation bitte selbst prüfen.'
fi
systemctl enable --now docker
systemctl restart docker

echo '=== GitHub-SSH-Schlüssel vorbereiten ==='
SSH_DIR="$TARGET_HOME/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"
install -d -m 700 -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$SSH_DIR"
if [[ -e $KEY_FILE || -e $KEY_FILE.pub ]]; then
  if [[ -f $KEY_FILE.pub ]]; then
    echo 'Vorhandener GitHub-/SSH-Schlüssel wird nicht überschrieben.'
  else
    echo 'Schlüsseldatei existiert teilweise. Kein neuer Schlüssel erzeugt.'
  fi
else
  echo 'Erstelle einen neuen SSH-Schlüssel für GitHub.'
  echo 'Für zusätzliche Sicherheit eine Passphrase vergeben (Eingabeaufforderung folgt).'
  runuser -u "$TARGET_USER" -- ssh-keygen -t ed25519 -C "${TARGET_USER}@$(hostname)-github" -f "$KEY_FILE"
fi

echo '=== Versionen ==='
docker --version
docker compose version
git --version

echo '=== Docker-Funktionstest ==='
docker run --rm hello-world

echo '=== QEMU Guest Agent ==='
if systemctl is-active --quiet qemu-guest-agent; then
  echo 'QEMU Guest Agent ist aktiv.'
else
  echo 'QEMU Guest Agent noch nicht aktiv: Proxmox > VM > Optionen > QEMU Guest Agent aktivieren und VM ggf. vollständig neu starten.'
fi

echo
echo '============================================================'
echo "GitHub: Öffentlicher SSH-Schlüssel für Benutzer $TARGET_USER"
echo '============================================================'
if [[ -f $KEY_FILE.pub ]]; then
  cat "$KEY_FILE.pub"
else
  echo 'Kein öffentlicher Schlüssel verfügbar. Bitte Schlüsseldateien prüfen.'
fi
echo
echo 'GitHub: https://github.com/settings/keys'
echo "SSH-Test (als $TARGET_USER, ohne sudo): ssh -T git@github.com"
echo 'Fertig. Den privaten Schlüssel niemals veröffentlichen.'
