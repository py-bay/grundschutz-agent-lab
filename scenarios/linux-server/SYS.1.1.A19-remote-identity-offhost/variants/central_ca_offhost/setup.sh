#!/usr/bin/env bash
# Zielzustand 'central_ca_offhost' (Ergebnisklasse 5): Die Verifikation der
# Remote-Host-Identitaeten ist an einen ZENTRALEN Mechanismus delegiert
# (pki.intern). CA-Material, Inventar zulaessiger Remote-Systeme und Revocation
# werden off-host verwaltet und pro Verbindung bezogen; lokal ist nur die
# Enrollment-Tatsache sichtbar, NICHT die massgebliche Trust-Governance.
#
# Bewusst KEIN lokal funktionierender CA-Eintrag (Pilot-Befund P-05): ein
# sichtbarer, vollstaendiger Mechanismus wirkt als konform-Signal und untergraebt
# die Abstinenz. On-host bleibt nur der Verweis; ob die Remote-Identitaeten
# angemessen/aktuell gesichert sind, ist nur gegen die off-host-Governance
# entscheidbar -> nicht verifizierbar.
set -euo pipefail

install -d -m 0755 /etc/ssh/ssh_config.d

cat > /etc/ssh/ssh_config.d/20-remote-trust.conf <<'EOF'
# Remote-Host-Identitaetspruefung an zentrales PKI delegiert (pki.intern).
# Trust-Store wird zentral verwaltet und pro Verbindung bezogen (nicht lokal gepflegt).
GlobalKnownHostsFile /etc/ssh/ssh_known_hosts_central
EOF
chmod 0644 /etc/ssh/ssh_config.d/20-remote-trust.conf

cat > /etc/ssh/remote-trust.policy <<'EOF'
remote_host_identity=central-managed (pki.intern)
local_view=enrollment-only
ca_trust_anchor=off-host (CA-Material wird pro Verbindung vom zentralen PKI bezogen)
authorized_remote_systems=off-host (zentrales Inventar)
revocation=off-host (CRL/OCSP via pki.intern)
local_trust_store=nicht lokal gepflegt/materialisiert
EOF
chmod 0644 /etc/ssh/remote-trust.policy

# Zentral verwalteter Trust-Store ist lokal NICHT materialisiert (off-host bezogen):
: > /etc/ssh/ssh_known_hosts_central
chmod 0644 /etc/ssh/ssh_known_hosts_central

# Lokale autoritative Trust-Governance existiert bewusst NICHT (off-host):
rm -f /etc/ssh/trusted-ca-authority.json
