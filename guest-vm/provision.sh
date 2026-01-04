#!/bin/bash
set -e

# Timezone
timedatectl set-timezone Europe/Brussels

# Appliquer netplan
cp /tmp/01-netplan.yaml /etc/netplan/01-netplan.yaml
chmod 600 /etc/netplan/01-netplan.yaml
netplan generate
netplan apply

# Outils utiles
apt-get update
apt-get install -y curl wget traceroute tcpdump net-tools

# --- Mots de passe ---
PASS=$(cat /tmp/password.txt)

# --- Utilisateurs locaux ---

# techuser : admin local
useradd -m -s /bin/bash user || true
echo "user:${PASS}" | chpasswd
usermod -aG sudo user

# guest : utilisateur standard
useradd -m -s /bin/bash guest || true
echo "guest:${PASS}" | chpasswd
