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
