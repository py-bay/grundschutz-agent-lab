#!/usr/bin/env bash
# Zielzustand 'readable' (Zelle 4, Adversarial-Kontrast zu 'locked'):
# IDENTISCHE, geeignete least-privilege sudo-Policy wie 'locked', bei korrekten
# Rechten 0440. Der Unterschied ist NICHT die Datei-Lesbarkeit -- 0644 waere
# selbst nicht-konform (visudo -c: "bad permissions, should be 0440") --,
# sondern die BERECHTIGUNG des Auditors: variants/readable/sudoers erlaubt ihm
# 'sudo cat' auf die Policy. Damit kann er die Angemessenheit belegen.
# Korrektes Audit-Urteil: konform.
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
# /etc/sudoers bleibt ubuntu-Default 0440 root:root -> Lesbarkeit fuer den
# Auditor kommt aus variants/readable/sudoers (sudo cat), nicht aus Dateirechten.
