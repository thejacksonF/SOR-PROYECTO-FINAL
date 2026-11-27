# Infraestructura Soberana — GIDN

Proyecto final de **Sistemas Operativos de Red (SOR)**, Universidad La Salle Chihuahua.
Infraestructura on-premise de **Grupo Industrial Del Norte (GIDN)** sobre **Rocky Linux 10.3**, dominio `gidn-equipo1.local`.

| Integrante | Parte a cargo |
|---|---|
| Cristhian Loya | Red base, SSH Ed25519, permisos 3770, enlaces e inodos, auditoría de bitácoras |
| Sebas | DHCP (Kea), DNS autoritativo directo e inverso, portal HTTPS |
| Mario | Correo local aislado (Postfix, Dovecot, Roundcube), nube privada Nextcloud |

> Este repositorio **no contiene llaves privadas ni contraseñas reales**. Los archivos con secretos se publican como `*.ejemplo`, con los valores reemplazados por `***OCULTO***`.

---

## 1. Esquema de direccionamiento IP

Red LAN de GIDN: **`192.168.1.0/24`** (VMware VMnet2, solo host, sin DHCP de VMware).

| Elemento | Dirección / valor |
|---|---|
| Servidor `servidor.gidn-equipo1.local` (tarjeta `ens224`) | `192.168.1.10/24`, IP estática |
| Puerta de enlace entregada por DHCP | `192.168.1.10` |
| DNS entregado por DHCP | `192.168.1.10` |
| Pool DHCP | `192.168.1.100` – `192.168.1.150` |
| Exclusión dentro del pool | `192.168.1.120` – `192.168.1.130` |
| Reserva por MAC | `cliente1` → `192.168.1.50` |
| Tarjeta `ens160` | NAT de VMware, DHCP. Solo para salida a Internet y administración remota |
| Zona inversa | `1.168.192.in-addr.arpa` |

```
                 Internet
                    │
          [ NAT de VMware · ens160 ]
                    │
   ┌────────────────┴────────────────┐
   │  servidor.gidn-equipo1.local    │
   │  Rocky Linux 10.3               │
   │  ens224 · 192.168.1.10/24       │
   └────────────────┬────────────────┘
                    │  LAN GIDN 192.168.1.0/24 (VMnet2)
        ┌───────────┴───────────┐
   cliente1 (reserva)     clientes DHCP
   192.168.1.50           .100–.119 · .131–.150
```

## 2. Registros DNS (`gidn-equipo1.local`)

| Nombre | Tipo | Valor |
|---|---|---|
| `@` | SOA / NS | `ns1.gidn-equipo1.local.` |
| `@` | MX 10 | `mail.gidn-equipo1.local.` |
| `ns1`, `servidor`, `www`, `mail`, `cloud` | A | `192.168.1.10` |
| `cliente1` | A | `192.168.1.50` |
| `portal` | CNAME | `www` |
| `webmail` | CNAME | `mail` |
| `nube` | CNAME | `cloud` |
| `10` (zona inversa) | PTR | `servidor.gidn-equipo1.local.` |
| `50` (zona inversa) | PTR | `cliente1.gidn-equipo1.local.` |

Forwarders para nombres externos: `8.8.8.8` y `1.1.1.1`.

## 3. Servicios y puertos activos

| Servicio | Software | Puerto | Estado |
|---|---|---|---|
| Acceso remoto | OpenSSH (solo llave Ed25519) | 22/tcp | ✅ |
| DNS autoritativo | BIND 9.18 (`named`) | 53/tcp, 53/udp | ✅ Validado desde el servidor. Pendiente prueba desde el cliente |
| DHCP | Kea (`kea-dhcp4`) | 67/udp | ⏳ Configuración validada. Pendientes arranque, reserva por MAC y prueba DORA |
| Portal web | Apache httpd + mod_ssl | 80/tcp (redirige) · 443/tcp | ✅ HTTP 301 y HTTPS 200 verificados desde el servidor. Pendiente prueba desde el cliente |
| Correo (MTA) | Postfix, solo entrega local | 25/tcp | ⏳ Parte 3 |
| Buzones (MDA / IMAP) | Dovecot | 143/tcp, 993/tcp | ⏳ Parte 3 |
| Webmail | Roundcube sobre MariaDB | 443/tcp (`mail.`) | ⏳ Parte 3 |
| Nube privada | Nextcloud sobre MariaDB | 443/tcp (`cloud.`) | ⏳ Parte 3 |
| Base de datos | MariaDB 10.11 | 3306/tcp (solo `127.0.0.1`) | ✅ |
| SMTP saliente | **Bloqueado** (política firewalld `dlp-smtp-salida`) | 25, 465, 587 de salida | ⏳ Parte 3 |


**Validación de la Parte 2.** Se comprobaron los registros A y PTR con respuesta autoritativa (`aa`), además de SOA, NS, MX, CNAME y
la resolución de un dominio externo. El portal respondió con una redirección HTTP `301` y un `200` por HTTPS tras validar el certificado del equipo.
En `VMnet2` queda pendiente confirmar que el DHCP de VMware esté desactivado y obtener la MAC del cliente para asignarle la reserva `192.168.1.50` y capturar DORA.

## 4. Estructura del repositorio

```
configs/
  red/       lan-gidn.nmconnection        IP estática de la LAN
  ssh/       00-gidn.conf                 sshd: solo llaves, sin contraseña ni root
  dhcp/      kea-dhcp4.conf               pool, exclusión y reserva por MAC
  dns/       named.conf y zonas           directa e inversa
  web/       gidn.conf                    VirtualHosts HTTPS y redirección
  correo/    main.cf, solo_dominio_local  aislamiento del correo (DLP)
  firewall/  políticas y zonas            incluye bloqueo de SMTP saliente
  nube/      config.php.ejemplo           Nextcloud sin secretos
scripts/
  auditoria-logs.sh                       auditoría de bitácoras (grep | sort | uniq -c)
docs/                                     reporte técnico y capturas
```

## 5. Seguridad del servidor (Parte 1)

**SSH** (`configs/ssh/00-gidn.conf`): `PasswordAuthentication no`, `PermitRootLogin no`, `AuthenticationMethods publickey` y solo algoritmos `ssh-ed25519`. Permisos: `~/.ssh` en `700`, `authorized_keys` y la llave privada en `600`.

**Carpeta colaborativa de Operaciones** `/srv/gidn/operaciones`, permisos **`3770`** (`drwxrws--T root:operaciones`):

- `2` SetGID: los archivos nuevos heredan el grupo `operaciones`.
- `1` Sticky bit: cada usuario solo puede borrar sus propios archivos.
- `770`: dueño y grupo con acceso total; el resto, ninguno.

Grupos de área en Linux: `operaciones`, `administracion` y `sistemas`.

## 6. Comandos de verificación rápida

```bash
# Red
ip -br a                                   # ens224 con 192.168.1.10/24
ip route

# SSH
sudo sshd -T | grep -Ei "^(passwordauthentication|permitrootlogin|authenticationmethods)"
ssh -o PubkeyAuthentication=no usuario@192.168.1.10   # debe dar Permission denied (publickey)

# Permisos e inodos
stat -c "%a %A %U:%G %n" /srv/gidn/operaciones        # 3770 drwxrws--T
sudo ls -li /srv/gidn/operaciones                     # duro = mismo inodo; simbólico = otro

# Auditoría de bitácoras
sudo ./scripts/auditoria-logs.sh

# DNS (bandera aa = respuesta autoritativa)
dig @192.168.1.10 www.gidn-equipo1.local
dig @192.168.1.10 gidn-equipo1.local MX
dig @192.168.1.10 -x 192.168.1.10

# DHCP
sudo journalctl -u kea-dhcp4 | grep DHCP4_LEASE_ALLOC
sudo cat /var/lib/kea/kea-leases4.csv

# Web
curl -I  http://www.gidn-equipo1.local                # 301 a https
curl -kI https://www.gidn-equipo1.local               # 200

# Correo aislado
sudo postconf default_transport                       # error:Politica DLP...
sudo firewall-cmd --info-policy dlp-smtp-salida

# Estado de todos los servicios
systemctl is-active sshd named kea-dhcp4 httpd postfix dovecot mariadb
sudo firewall-cmd --list-all
```
