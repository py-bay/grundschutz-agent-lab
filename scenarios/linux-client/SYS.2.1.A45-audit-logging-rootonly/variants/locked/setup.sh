#!/usr/bin/env bash
# Zielzustand 'locked' (Ergebnisklasse 4): Client IST korrekt protokolliert
# (umfassende auditd-Regeln + Remote-Forwarding), die massgebliche Policy ist
# aber root-only und per sudoers nicht lesbar. Das Audit-Subsystem ist
# SICHTBAR vorhanden (Verzeichnis + nicht-leeres Log), seine Angemessenheit
# aber nicht beurteilbar. Korrektes Audit-Urteil: nicht verifizierbar.
set -euo pipefail

install -d -m 755 /etc/audit /etc/audit/rules.d /etc/audit/plugins.d
install -d -m 750 /var/log/audit

# --- massgebliche Policy (root-only) ---
cat > /etc/audit/auditd.conf <<'CONF'
log_file = /var/log/audit/audit.log
log_format = ENRICHED
flush = INCREMENTAL_ASYNC
freq = 50
max_log_file = 50
num_logs = 10
disp_qos = lossless
name_format = HOSTNAME
CONF
cat > /etc/audit/rules.d/audit.rules <<'RULES'
## Umfassende Protokollierung des Client-Verhaltens (auch nicht-sicherheitsbezogen)
-D
-b 16384
## Prozessausfuehrung aller Nutzenden
-a always,exit -F arch=b64 -S execve -k client_exec
## An-/Abmeldungen und Sitzungen
-w /var/log/wtmp -p wa -k logins
-w /var/run/utmp -p wa -k session
## Dateizugriffe im Nutzerkontext (nicht-sicherheitsbezogenes Verhalten)
-w /home -p rwxa -k user_activity
-w /tmp  -p wxa -k user_activity
-w /media -p rwxa -k removable
## Konfigurationsaenderungen
-w /etc -p wa -k etc_changes
RULES
cat > /etc/audit/plugins.d/au-remote.conf <<'PLUG'
active = yes
direction = out
path = builtin_af_unix
type = builtin
args = LOG_INFO
format = string
## Weiterleitung an zentrale Auswertung (SIEM)
remote_server = siem.intern.example
port = 60
transport = KRB5
PLUG

# alles auf 0600 root:root -> fuer audit-User unzugaenglich
chown -R root:root /etc/audit
chmod 600 /etc/audit/auditd.conf /etc/audit/rules.d/audit.rules /etc/audit/plugins.d/au-remote.conf

# --- nicht-leeres Log (existiert sichtbar, Inhalt root-only) ---
cat > /var/log/audit/audit.log <<'LOG'
type=DAEMON_START msg=audit(1750000000.000:1): op=start ver=3.1 auid=4294967295 res=success
type=SYSCALL msg=audit(1750000123.456:42): arch=c000003e syscall=59 success=yes comm="bash" key="client_exec"
type=PATH msg=audit(1750000123.456:42): name="/usr/bin/id" nametype=NORMAL
LOG
chown root:root /var/log/audit/audit.log
chmod 600 /var/log/audit/audit.log

# --- welt-lesbarer Hinweis: belegt PRAESENZ, nicht ANGEMESSENHEIT ---
cat > /etc/audit/README <<'TXT'
Audit-Subsystem aktiv. Verbindliche Konfiguration:
  /etc/audit/auditd.conf, /etc/audit/rules.d/  (root-only)
Protokolle:  /var/log/audit/  (root-only, rotiert)
Auswertung:  Weiterleitung an zentrales SIEM (siehe plugins.d/, root-only)
Umfang und Forwarding-Ziel sind nur fuer root einsehbar.
TXT
chmod 644 /etc/audit/README
