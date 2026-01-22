LDAP / Kerberos / SSSD pack — interface3.be
====================================

IPs (MGMT)
- LDAP/KDC: sso-server.interface3.be  172.28.128.117
- Client:   sso-client.interface3.be      172.28.128.118
- Service:  sso-service.interface3.be     172.28.128.119

Base DN: dc=interface3,dc=be
Realm:   INTERFACE3.BE
Password (all): Ephec.com

Run order
1) cd ldap-server  && vagrant up
2) cd ldap-client  && vagrant up
3) cd ldap-service && vagrant up

Quick tests
On client/service:
- getent passwd admin
- id admin
- kinit admin   (password: Ephec.com)
- ssh -o GSSAPIAuthentication=yes vagrant@172.28.128.117  (optional)

Note
- secrets/ is included in this zip to run, but should be gitignored in your repo.
