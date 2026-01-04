#!/bin/bash
set -euo pipefail

chmod 600 /home/vagrant/secrets/*.txt
chown -R vagrant:vagrant /home/vagrant/secrets

timedatectl set-timezone Europe/Brussels
hostnamectl set-hostname sso-server.interface3.be

cat > /etc/hosts <<'EOF'
127.0.0.1 localhost
172.28.2.10 sso-server.interface3.be
172.28.128.17 fw-mgmt
172.28.2.254 fw-servers-gw
172.28.3.254 fw-compta-gw
172.28.5.254 fw-staff-gw
172.28.100.254 fw-admincl-gw
172.28.128.110 sso-server.interface3.be-mgmt
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


export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -qq -y debconf-utils

debconf-set-selections < /home/vagrant/install-krb5.txt || true
debconf-set-selections < /home/vagrant/install-slapd.txt || true

apt-get install -qq -y slapd ldap-utils krb5-kdc krb5-admin-server krb5-user

cat /home/vagrant/ldap.conf >> /etc/ldap/ldap.conf

# KDC DB create (NON-interactive)
REALM_PASS="$(tr -d '\n' < /home/vagrant/secrets/realm-pass.txt)"
if [ ! -f /var/lib/krb5kdc/principal ]; then
  kdb5_util create -s -r INTERFACE3.BE -P "$REALM_PASS"
fi
systemctl restart krb5-kdc krb5-admin-server

# kadmin ACL
grep -q "INTERFACE3.BE" /etc/krb5kdc/kadm5.acl 2>/dev/null || echo "*/admin@INTERFACE3.BE        *" >> /etc/krb5kdc/kadm5.acl
systemctl restart krb5-admin-server

PASSFILE=/home/vagrant/secrets/ubuntu-pass.txt
ADMINPASSFILE=/home/vagrant/secrets/ubuntuadmin-pass.txt
DEFAULTPASSFILE=/home/vagrant/secrets/default-user-pass.txt

printf "%s\n%s\n" "$(cat "$PASSFILE")" "$(cat "$PASSFILE")" | kadmin.local -q "addprinc ubuntu" || true
printf "%s\n%s\n" "$(cat "$ADMINPASSFILE")" "$(cat "$ADMINPASSFILE")" | kadmin.local -q "addprinc ubuntu/admin" || true

# Host keytab (GSSAPI SSH)
printf "%s\n" "$(cat "$ADMINPASSFILE")" | kadmin -p ubuntu/admin -q "addprinc -randkey host/sso-server.interface3.be" || true
printf "%s\n" "$(cat "$ADMINPASSFILE")" | kadmin -p ubuntu/admin -q "ktadd -k /etc/krb5.keytab host/sso-server.interface3.be" || true

cat > /etc/ssh/sshd_config.d/50-gssapi.conf <<'EOF'
GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
EOF
systemctl restart sshd

# LDAP content
ldapadd -x -D "cn=admin,dc=interface3,dc=be" -y /home/vagrant/secrets/ldap-admin-pass.txt -f /home/vagrant/ldifs/00-base.ldif
ldapadd -x -D "cn=admin,dc=interface3,dc=be" -y /home/vagrant/secrets/ldap-admin-pass.txt -f /home/vagrant/ldifs/10-groups.ldif
ldapadd -x -D "cn=admin,dc=interface3,dc=be" -y /home/vagrant/secrets/ldap-admin-pass.txt -f /home/vagrant/ldifs/20-users.ldif
ldapadd -x -D "cn=admin,dc=interface3,dc=be" -y /home/vagrant/secrets/ldap-admin-pass.txt -f /home/vagrant/ldifs/30-memberships.ldif

# Kerberos principals for LDAP users (all: Ephec.com)
DEFAULT_PASS="$(tr -d '\n' < "$DEFAULTPASSFILE")"
for u in admin johan fatima ibtissam saliha.compta olivier.compta julie.staff sven.staff elise.admiclass stephanie.admiclass nisrine.techclass alessia.techclass; do
  printf "%s\n%s\n" "$DEFAULT_PASS" "$DEFAULT_PASS" | kadmin.local -q "addprinc $u" || true
done

echo "ldap-server done."

