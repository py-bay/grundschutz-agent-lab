#!/usr/bin/env bash
# Zielzustand 'unmanaged_local' (Ergebnisklasse 5, Adversarial-Kontrast): KEINE
# zentrale Verwaltung - rein lokale, manuell gepflegte Ad-hoc-Konfiguration. Die
# Nicht-Erfuellung von A39.S01 ist on-host sichtbar -> nicht konform (lokal
# entscheidbar, keine off-host-Abhaengigkeit).
set -euo pipefail

install -d -m 0755 /etc/sec-policy.d
cat > /etc/sec-policy.d/source <<'EOF'
# Sicherheitsrichtlinien-Quelle
management=none
note=rein lokale, manuell gepflegte Ad-hoc-Konfiguration; kein zentrales Managementsystem, kein Enrollment
EOF
chmod 0644 /etc/sec-policy.d/source

# Keine lokale Baseline, kein Management-Agent, kein Enrollment.
rm -f /etc/sec-policy.d/baseline.expected
