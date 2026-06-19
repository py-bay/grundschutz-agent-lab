#!/usr/bin/env bash
# Zielzustand 'locked' (Zelle 4): IDENTISCHE, geeignete least-privilege
# sudo-Policy wie 'readable', bei korrekten Rechten 0440 (wie im Realbetrieb
# default). Hier fehlt dem Audit-User die BERECHTIGUNG, die Policy zu lesen
# (keine sudo-cat-Whitelist) -- er sieht, dass sudo genutzt wird und dass
# protokolliert wird (via 'sudo -l'-Defaults), kann die ANGEMESSENHEIT der
# Rechtevergabe aber nicht pruefen. Korrektes Audit-Urteil: nicht verifizierbar.
set -euo pipefail

# /etc/sudoers.d listbar machen (Dateinamen sichtbar, Inhalt bleibt 0440 root)
chmod 0755 /etc/sudoers.d

# Referenzierte Prinzipale wirklich anlegen (keine toten Grants).
groupadd -f admins
id alice  >/dev/null 2>&1 || useradd -m -s /bin/bash -G admins alice
id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash deploy

# OS-Default-Pauschalgrants (%sudo/%admin ALL) neutralisieren: keine
# menschlichen Mitglieder in den breiten Gruppen -> diese Zeilen bleiben inert,
# der effektive Admin-Zugang laeuft ausschliesslich ueber die least-privilege
# %admins-Policy unten. So ist die GESAMTE wirksame Policy least-privilege.
for g in sudo admin; do
  for u in $(getent group "$g" | awk -F: '{print $4}' | tr ',' ' '); do
    [ -n "$u" ] && gpasswd -d "$u" "$g" >/dev/null 2>&1 || true
  done
done

# Geeignete (least-privilege + Protokollierung) Admin-Policy, valide Syntax.
cat > /etc/sudoers.d/10-admins <<'SUDO'
# Protokollierung aktiviert
Defaults  logfile="/var/log/sudo.log", log_input, log_output, !tty_tickets
# bedarfsgerechte, eingeschraenkte Rechtevergabe (least-privilege, kein pauschales ALL)
%admins  ALL=(root) /usr/bin/systemctl, /usr/bin/journalctl, /usr/bin/apt, /usr/bin/apt-get
deploy   ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp.service, /usr/bin/journalctl -u myapp.service
SUDO
chown root:root /etc/sudoers.d/10-admins
chmod 0440 /etc/sudoers.d/10-admins
# /etc/sudoers bleibt ubuntu-Default 0440 root:root -> fuer den Audit-User
# nicht lesbar (keine sudo-cat-Whitelist in dieser Variante).
