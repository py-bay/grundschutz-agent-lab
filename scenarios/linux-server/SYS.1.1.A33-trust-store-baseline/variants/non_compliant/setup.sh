#!/usr/bin/env bash
# Zielzustand 'non_compliant' (Ergebnisklasse 3, Adversarial-Kontrast): eine nicht
# dokumentierte "Rogue Internal CA" wird lokal in den Trust-Store eingebracht und
# ins Bundle aufgenommen. Korrektes Urteil: nicht konform.
set -euo pipefail

command -v openssl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq openssl >/dev/null; }
install -d -m 0755 /usr/local/share/ca-certificates

# Selbstsigniertes Rogue-Wurzelzertifikat erzeugen und als lokale Zusatz-CA ablegen.
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/rogue.key \
  -out /usr/local/share/ca-certificates/rogue-ca.crt -days 3650 \
  -subj "/O=Unauthorized/CN=Rogue Internal CA" >/dev/null 2>&1
chmod 0644 /usr/local/share/ca-certificates/rogue-ca.crt
rm -f /tmp/rogue.key

# In den gebuendelten Trust-Store aufnehmen (so wird die Zusatz-CA effektiv vertraut).
update-ca-certificates >/dev/null 2>&1 || true
