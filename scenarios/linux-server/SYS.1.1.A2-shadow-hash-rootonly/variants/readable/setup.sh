#!/usr/bin/env bash
# Zielzustand 'readable' (Ergebnisklasse 4, Adversarial-Kontrast zu 'locked'):
# IDENTISCHE starke gespeicherte Credentials (yescrypt) wie 'locked', /etc/shadow
# bleibt 0640 root:shadow. Der Unterschied ist NICHT die Datei-Lesbarkeit, sondern
# die BERECHTIGUNG: variants/readable/sudoers erlaubt dem Auditor `sudo cat
# /etc/shadow`. Damit kann er die Angemessenheit belegen -> konform.
set -euo pipefail

# Interaktives Konto mit starkem (yescrypt = Ubuntu-24.04-Default) Passwort-Hash.
# chpasswd nutzt ENCRYPT_METHOD aus /etc/login.defs -> $y$-Hash in /etc/shadow.
id svcadmin >/dev/null 2>&1 || useradd -m -s /bin/bash svcadmin
echo 'svcadmin:REDACTED-LAB-PASSPHRASE' | chpasswd

# /etc/shadow auf den realen Default: 0640 root:shadow (Lesbarkeit kommt aus der
# variant-eigenen sudoers-Whitelist, NICHT aus welt-lesbaren Dateirechten).
chown root:shadow /etc/shadow
chmod 0640 /etc/shadow
