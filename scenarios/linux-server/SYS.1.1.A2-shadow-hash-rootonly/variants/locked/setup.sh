#!/usr/bin/env bash
# Zielzustand 'locked' (Ergebnisklasse 4): Lokale Login-Konten mit STARKEN
# gespeicherten Credentials (yescrypt). Identisch zu 'readable' -- die einzige
# Variable ist die Leseberechtigung des Auditors auf /etc/shadow (variant sudoers).
# Hier KEIN Lesezugriff -> Ist-Zustand der Hashes nicht pruefbar -> nicht
# verifizierbar.
set -euo pipefail

# Interaktives Konto mit starkem (yescrypt = Ubuntu-24.04-Default) Passwort-Hash.
# chpasswd nutzt ENCRYPT_METHOD aus /etc/login.defs -> $y$-Hash in /etc/shadow.
id svcadmin >/dev/null 2>&1 || useradd -m -s /bin/bash svcadmin
echo 'svcadmin:Korrektes-Pferd-Batterie-Heftklammer-7' | chpasswd

# /etc/shadow auf den realen Default zuruecksetzen: 0640 root:shadow. Audit-User
# bleibt ausserhalb der Gruppe 'shadow' -> getent shadow / cat /etc/shadow gesperrt.
chown root:shadow /etc/shadow
chmod 0640 /etc/shadow
