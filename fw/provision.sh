#!/bin/bash
set -euo pipefail

sudo timedatectl set-timezone Europe/Brussels
sudo hostnamectl set-hostname fw

# IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ipforward.conf >/dev/null

# Appliquer netplan (contourne le bug Vagrant)
sudo cp /tmp/01-fw-netplan.yaml /etc/netplan/01-fw-netplan.yaml
sudo chmod 600 /etc/netplan/01-fw-netplan.yaml
sudo chown root:root /etc/netplan/01-fw-netplan.yaml
# Supprimer les confs parasites générées
sudo rm -f /etc/netplan/50-vagrant.yaml

sudo netplan generate
sudo netplan apply

# nftables
sudo apt-get update
sudo apt-get install -y nftables tcpdump traceroute

sudo cp /tmp/nftables.conf /etc/nftables.conf
sudo systemctl enable --now nftables
sudo nft -f /etc/nftables.conf

echo "FW OK: netplan appliqué + nftables chargé."

# --- Swap (évite OOM pendant apt install) ---
if ! swapon --show | grep -q "/swapfile"; then
  sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi
############
# --- Snort install ---
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y snort snort-common snort-common-libraries snort-rules-default

# --- Overlay conf prof SANS supprimer /etc/snort ---
# (Comme ça on garde unicode.map, threshold.conf, etc. si présents)
sudo rsync -a /tmp/snort/ /etc/snort/
sudo chown -R root:root /etc/snort

# --- Corriger chemins dynamiques via symlinks (portable) ---
# Ton snort.conf attend:
#   /usr/lib/snort_dynamicpreprocessor/
#   /usr/lib/snort_dynamicengine/...
#   /usr/lib/snort_dynamicrules
# Sur Jammy, libs sont ici:
#   /usr/lib/snort/snort_dynamicpreprocessor
#   /usr/lib/snort/snort_dynamicengine
#   /usr/lib/snort/snort_dynamicrules (souvent vide mais ok)

sudo ln -snf /usr/lib/snort/snort_dynamicpreprocessor /usr/lib/snort_dynamicpreprocessor
sudo ln -snf /usr/lib/snort/snort_dynamicengine       /usr/lib/snort_dynamicengine
sudo ln -snf /usr/lib/snort/snort_dynamicrules        /usr/lib/snort_dynamicrules

# Certains snort.conf utilisent aussi x86_64-linux-gnu
sudo mkdir -p /usr/lib/x86_64-linux-gnu || true
sudo ln -snf /usr/lib/snort/snort_dynamicpreprocessor /usr/lib/x86_64-linux-gnu/snort_dynamicpreprocessor
sudo ln -snf /usr/lib/snort/snort_dynamicengine       /usr/lib/x86_64-linux-gnu/snort_dynamicengine
sudo ln -snf /usr/lib/snort/snort_dynamicrules        /usr/lib/x86_64-linux-gnu/snort_dynamicrules

# --- Fichiers attendus par snort.conf ---
sudo mkdir -p /etc/snort
sudo mkdir -p /var/log/snort
sudo chown -R snort:snort /var/log/snort || true

# threshold.conf doit exister (snort.conf: include threshold.conf)
if [ ! -f /etc/snort/threshold.conf ]; then
  sudo touch /etc/snort/threshold.conf
  sudo chmod 644 /etc/snort/threshold.conf
fi

# unicode.map doit exister (http_inspect iis_unicode_map unicode.map)
# Si absent, on le récupère depuis le paquet snort-common
if [ ! -f /etc/snort/unicode.map ]; then
  tmpdir="$(mktemp -d)"
  (
    cd "$tmpdir"
    apt-get download snort-common >/dev/null
    dpkg-deb -x snort-common_*.deb "$tmpdir/extract"
    sudo cp "$tmpdir/extract/etc/snort/unicode.map" /etc/snort/unicode.map
    sudo chmod 644 /etc/snort/unicode.map
  )
  rm -rf "$tmpdir"
fi

# --- Service systemd Snort DMZ ---
sudo cp /tmp/snort-dmz.service /etc/systemd/system/snort-dmz.service
sudo chmod 644 /etc/systemd/system/snort-dmz.service

sudo systemctl daemon-reload

# --- Test de config (évite boot “silent fail”) ---
sudo snort -T -i vlan_dmz -c /etc/snort/snort.conf

sudo systemctl enable --now snort-dmz
echo "FW OK: snort-dmz service"
sudo systemctl --no-pager status snort-dmz || true

############
