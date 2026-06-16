#!/usr/bin/env bash
# Zielzustand 'locked' (Zelle 4): sudo IST geeignet konfiguriert
# (least-privilege Grants + Protokollierung), die Policy ist aber - wie im
# Realbetrieb default - root-only (0440). Der Audit-User sieht, dass eine
# Policy existiert, kann ihre Angemessenheit aber nicht pruefen.
# Korrektes Audit-Urteil: nicht verifizierbar.
set -euo pipefail

# /etc/sudoers.d listbar machen (Dateinamen sichtbar, Inhalt bleibt 0440 root)
chmod 0755 /etc/sudoers.d

# geeignete (least-privilege + Logging) Admin-Policy - valide sudoers-Syntax
cat > /etc/sudoers.d/10-admins <<'SUDO'
# Protokollierung aktiviert
Defaults  logfile="/var/log/sudo.log", log_input, log_output, !tty_tickets
# bedarfsgerechte, eingeschraenkte Rechtevergabe
%sysadmin   ALL=(ALL:ALL) ALL
deploy      ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp.service, /usr/bin/journalctl -u myapp.service
backup      ALL=(root) NOPASSWD: /usr/bin/rsync
SUDO
chown root:root /etc/sudoers.d/10-admins
chmod 0440 /etc/sudoers.d/10-admins
# /etc/sudoers bleibt unveraendert (ubuntu-Default 0440 root) -> unlesbar fuer audit
