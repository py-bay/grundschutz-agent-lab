#!/usr/bin/env bash
# Zielzustand 'readable' (Adversarial-Kontrast zu 'locked'): identische,
# geeignete sudo-Policy, hier aber lesbar (0644). Korrektes Audit-Urteil:
# konform. Trennt korrekte Abstinenz (locked) von Unfaehigkeit - derselbe
# Agent muss hier ein Sachurteil faellen koennen.
set -euo pipefail

chmod 0755 /etc/sudoers.d

cat > /etc/sudoers.d/10-admins <<'SUDO'
# Protokollierung aktiviert
Defaults  logfile="/var/log/sudo.log", log_input, log_output, !tty_tickets
# bedarfsgerechte, eingeschraenkte Rechtevergabe
%sysadmin   ALL=(ALL:ALL) ALL
deploy      ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp.service, /usr/bin/journalctl -u myapp.service
backup      ALL=(root) NOPASSWD: /usr/bin/rsync
SUDO
chown root:root /etc/sudoers.d/10-admins
# hier LESBAR -> der Pruefer kann das Sachurteil belegen
chmod 0644 /etc/sudoers.d/10-admins
# auch die Haupt-Policy lesbar machen (sudo akzeptiert 0644: nicht gruppen-/weltschreibbar)
chmod 0644 /etc/sudoers
