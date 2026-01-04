#!/bin/bash
set -euo pipefail

chmod 600 /home/vagrant/ubuntuadmin-pass.txt
chown -R vagrant:vagrant /home/vagrant/ubuntuadmin-pass.txt

timedatectl set-timezone Europe/Brussels
hostnamectl set-hostname sso-staff.interface3.be

cat >> /etc/hosts <<'EOF'
#LDAP
172.28.2.10 sso-server.interface3.be
172.28.2.11 sso-service.interface3.be
172.28.3.10 sso-compta.interface3.be
172.28.5.10 sso-staff.interface3.be
172.28.100.10 sso-desk.interface3.be
# Optionnel mgmt (pour le  ping/debug)
172.28.128.110 sso-server.interface3.be-mgmt
172.28.128.119 sso-service.interface3.be-mgmt
#Site-web
172.28.200.10 yuki.interface3.be
EOF

install -m 0644 /tmp/01-netplan.yaml /etc/netplan/01-netplan.yaml
# netplan: installer et verrouiller les permissions
install -o root -g root -m 0600 /tmp/01-netplan.yaml /etc/netplan/01-netplan.yaml

# Si Vagrant a généré un /etc/netplan/50-vagrant.yaml, on verrouille aussi
if [ -f /etc/netplan/50-vagrant.yaml ]; then
  chown root:root /etc/netplan/50-vagrant.yaml
  chmod 0600 /etc/netplan/50-vagrant.yaml
fi

netplan generate
netplan apply



chmod 0600 /home/vagrant/install.txt /home/vagrant/ubuntuadmin-pass.txt || true

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -qq -y debconf-utils
debconf-set-selections < /home/vagrant/install.txt
chmod 600 /home/vagrant/ubuntuadmin-pass.txt
chown -R vagrant:vagrant /home/vagrant/ubuntuadmin-pass.txt

apt-get install -qq -y sssd-ldap sssd-krb5 ldap-utils krb5-user libpam-mkhomedir

# SSSD config
mv /home/vagrant/sssd.conf /etc/sssd/sssd.conf
chmod 0600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
systemctl restart sssd

# Auto-create home dirs on login
pam-auth-update --enable mkhomedir || true

# Add host principal + keytab for GSSAPI SSH
printf "%s\n" "$(cat /home/vagrant/ubuntuadmin-pass.txt)" | kadmin -p ubuntu/admin -q "addprinc -randkey host/sso-staff.interface3.be" || true
printf "%s\n" "$(cat /home/vagrant/ubuntuadmin-pass.txt)" | kadmin -p ubuntu/admin -q "ktadd -k /etc/krb5.keytab host/sso-staff.interface3.be" || true

cat > /etc/ssh/sshd_config.d/50-gssapi.conf <<'EOF'
GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
EOF
systemctl restart sshd

echo "Client joined (SSSD+Kerberos). Try: getent passwd admin ; kinit admin"
