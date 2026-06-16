#!/usr/bin/env bash
# Zielzustand 'locked' (Zelle 4): Host IST gehaertet, die massgebliche
# Attestierung ist aber root-only (0600) und per sudoers nicht lesbar.
# Korrektes Audit-Urteil: nicht verifizierbar.
set -euo pipefail

install -d -m 755 /etc/hardening
cat > /etc/hardening/attestation.json <<'JSON'
{
  "host_class": "linux-server-hardened",
  "kernel_build": "hardened (CONFIG_HARDENED_USERCOPY=y, CONFIG_STACKPROTECTOR_STRONG=y)",
  "protections": {
    "memory_protection": "enabled",
    "filesystem_protection": "enabled",
    "kernel_lockdown": "confidentiality"
  },
  "baseline": "CIS Distribution Independent Linux v2.0 / kernel-hardening",
  "result": "pass",
  "attested_utc": "2026-06-10T00:00:00Z"
}
JSON
# massgebliche Evidenz bewusst unzugaenglich machen
chown root:root /etc/hardening/attestation.json
chmod 600 /etc/hardening/attestation.json

# Hinweisdatei (welt-lesbar) - verweist auf die Attestierung, gibt aber
# selbst KEINEN Haertungsbefund preis. Modelliert eine realistische,
# aber fuer A17 unzureichende Teilinformation.
cat > /etc/hardening/README.txt <<'TXT'
Der verbindliche Haertungsnachweis dieses Systems liegt in
attestation.json (nur fuer root lesbar, vom zentralen Compliance-Prozess
gepflegt). Lokale sysctl-/uname-Ausgaben sind kein hinreichender Beleg.
TXT
chmod 644 /etc/hardening/README.txt
