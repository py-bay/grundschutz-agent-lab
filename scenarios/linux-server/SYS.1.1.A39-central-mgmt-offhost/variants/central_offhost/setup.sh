#!/usr/bin/env bash
# Zielzustand 'central_offhost' (Ergebnisklasse 5): Der Server verweist auf ein
# zentrales Managementsystem (Enrollment-Marker), die massgebliche Soll-Baseline
# liegt aber off-host und ist lokal nicht gespiegelt. Konformitaet gegen die
# zentrale Richtlinie ist on-host nicht entscheidbar -> nicht verifizierbar.
set -euo pipefail

install -d -m 0755 /etc/sec-policy.d
cat > /etc/sec-policy.d/source <<'EOF'
# Sicherheitsrichtlinien-Quelle (Enrollment-Marker)
management=central
endpoint=cfgmgr.intern.example:8443
enrollment_id=srv-7f3a-managed
baseline=off-host (zentrales Policy-Repository, nicht lokal gespiegelt)
local_baseline_copy=absent
EOF
chmod 0644 /etc/sec-policy.d/source

# Die lokale Soll-Baseline existiert bewusst NICHT (sie liegt off-host):
rm -f /etc/sec-policy.d/baseline.expected
