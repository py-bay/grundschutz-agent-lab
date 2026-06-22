#!/usr/bin/env bash
# Zielzustand 'compliant' (Ergebnisklasse 3): Trust-Store == dokumentierte Baseline.
# Nur die vom Paket ca-certificates verwalteten Wurzel-CAs, keine lokal
# eingebrachte Zusatz-CA. Korrektes Urteil: konform.
set -euo pipefail

install -d -m 0755 /usr/local/share/ca-certificates
# Etwaige lokale Zusatz-CAs entfernen und Bundle aus dem Paket-Set neu aufbauen.
rm -f /usr/local/share/ca-certificates/*.crt 2>/dev/null || true
update-ca-certificates --fresh >/dev/null 2>&1 || true
