#!/bin/bash

# Variables
NOMBRE_MAQUINA="clientedebian"
DOMINIO="ruben.com"
USUARIO_DOMINIO="administrador"
CONTRASENA_DOMINIO="Dpto1!"
IP_AD="192.168.1.13"
DOMINIO_S_MIN=$(echo $DOMINIO | cut -d'.' -f1)
DOMINIO_S_MAY=${DOMINIO_S_MIN^^}
DOMINIO_C_MAY=${DOMINIO^^}

#Actualizamos sistema
sudo apt update -y
sudo apt upgrade -y

# Configuro IP estática /etc/network/interfaces
sudo sh -c "cat <<EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto enp0s3
iface enp0s3 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers $IP_AD
EOF"

# Reinicio interfaz de red
sudo ifdown enp0s3
sudo ifup enp0s3

# Modifico nombre maquina /etc/hostname
sudo hostnamectl set-hostname "$NOMBRE_MAQUINA"

# Actualizo el archivo /etc/hosts
sudo sh -c "cat <<EOF > /etc/hosts
127.0.0.1      localhost
$(hostname -I | cut -f1 -d' ')     $NOMBRE_MAQUINA.$DOMINIO $NOMBRE_MAQUINA
EOF"

# Configuramos /etc/resolv.conf
sudo mv /etc/resolv.conf /etc/resolv.conf.backup
sudo sh -c "cat <<EOF > /etc/resolv.conf
domain $DOMINIO
search $DOMINIO
nameserver $IP_AD
nameserver 8.8.8.8
EOF"

# Instalamos paquetes necesarios
sudo apt install -y samba winbind krb5-user krb5-config krb5-kdc realmd packagekit
sudo apt install -y libpam-winbind libnss-winbind smbclient cifs-utils

# Cambio /etc/nsswitch.conf
sudo sh -c "cat <<EOF > /etc/nsswitch.conf
passwd:         files systemd winbind
group:          files systemd winbind
shadow:         files systemd
gshadow:        files systemd

hosts:          files dns mdns4_minimal [NOTFOUND=return] mdns4
networks:       files

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files

netgroup:       nis
automount:      files
EOF"

# Configuramos Kerberos
sudo sh -c "cat <<EOF > /etc/krb5.conf
[libdefaults]
        default_realm = $DOMINIO_C_MAY
        dns_lookup_realm = false
        dns_lookup_kdc = true
        forwardable = true
        proxiable = true
        kdc_timesync = 1
        ccache_type = 4
[realms]
        $DOMINIO_C_MAY = {
                kdc = serverruben.$DOMINIO
                admin_server = serverruben.$DOMINIO
                default_domain = $DOMINIO
        }
[domain_realm]
 .ruben.com = RUBEN.COM
        ruben.com = RUBEN.COM
[appdefaults]
        pam = {
                debug = false
                ticket_lifetime = 36000
                renew_lifetime = 36000
                forwardable = true
                krb4_convert = true
        }
EOF"

# Conseguimos ticket
#echo "$CONTRASENA_DOMINIO" | sudo kinit $USUARIO_DOMINIO@$DOMINIO


# Configurar Samba /etc/samba/smb.conf
sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.backup
sudo sh -c "cat <<EOF > /etc/samba/smb.conf
[global]
   netbios name = clientedebian
   server role = MEMBER SERVER
   winbind refresh tickets = yes
   winbind nss info = template
   winbind expand groups = 2
   winbind nested groups = yes
   idmap config * : backend = tdb
   idmap config * : range = 10000-20000
   idmap config $DOMINIO_S_MAY : backend = rid
   idmap config $DOMINIO_S_MAY : range = 30000-40000
   workgroup = $DOMINIO_S_MAY
   security = ads
   realm = $DOMINIO_C_MAY
   winbind enum users = yes
   winbind enum groups = yes
   winbind use default domain = yes
   template homedir = /home/%U
   template shell = /bin/bash
EOF"

# Reinicio samba y winbind
sudo service smbd restart
sudo service winbind restart

# Me uno al dominio
sudo net ads join -U $USUARIO_DOMINIO%$CONTRASENA_DOMINIO

