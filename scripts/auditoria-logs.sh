#!/usr/bin/env bash
# =============================================================
#  Auditoría de bitácoras de GIDN
#  Detecta intentos fallidos de acceso y eventos críticos
#  usando el pipeline:  grep | sort | uniq -c
#
#  Uso:  sudo ./auditoria-logs.sh            (lee el journal de sshd)
#        sudo ./auditoria-logs.sh archivo.log  (lee una bitácora en texto)
# =============================================================
if [ -n "$1" ]; then
  leer() { cat "$1"; }
  LOG_SUDO() { grep sudo "$1"; }
else
  leer() { journalctl -u sshd --no-pager -o short; }
  LOG_SUDO() { journalctl _COMM=sudo --no-pager -o short; }
fi

echo "== Intentos fallidos de SSH por IP de origen =="
# grep  : solo las líneas de fallos
# grep -o: extrae "from <IP>"; cut se queda con la IP
# sort | uniq -c : cuenta cuántas veces aparece cada IP
# sort -rn : de mayor a menor
leer "$1" | grep -E "Failed (password|publickey)|Invalid user" \
  | grep -oE "from [0-9a-fA-F.:]+" | cut -d" " -f2 \
  | sort | uniq -c | sort -rn

echo
echo "== Usuarios con los que intentaron entrar =="
leer "$1" | grep -E "Invalid user|Failed (password|publickey) for" \
  | grep -oE "(Invalid user|for( invalid user)?) [^ ]+" | awk '{print $NF}' \
  | sort | uniq -c | sort -rn

echo
echo "== Conexiones cortadas antes de autenticarse (posibles escaneos) =="
leer "$1" | grep -E "Connection (closed|reset) by .*\[preauth\]|Timeout before authentication" \
  | grep -oE "(by|from) ([a-z]+ user [^ ]+ )?([0-9]{1,3}\.){3}[0-9]{1,3}" | awk '{print $NF}' \
  | sort | uniq -c | sort -rn

echo
echo "== Accesos exitosos por usuario e IP =="
leer "$1" | grep "Accepted" | grep -oE "for [^ ]+ from [^ ]+" \
  | sort | uniq -c | sort -rn

echo
echo "== Uso de sudo por usuario =="
LOG_SUDO "$1" | grep -E "COMMAND=" | grep -oE "sudo\[[0-9]+\]: +[^ ]+" | awk '{print $2}' \
  | sort | uniq -c | sort -rn

echo
echo "== Correo bloqueado hacia el exterior (DLP) =="
grep -hE "reject:|status=bounced" /var/log/maillog 2>/dev/null \
  | grep -oE "to=<[^>]+>" | sort | uniq -c | sort -rn

echo
echo "== Errores críticos del sistema (hoy) =="
journalctl -p err --since today --no-pager -o cat | sort | uniq -c | sort -rn | head -15
