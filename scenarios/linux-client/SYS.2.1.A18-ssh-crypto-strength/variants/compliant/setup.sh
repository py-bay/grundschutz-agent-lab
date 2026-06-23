#!/usr/bin/env bash
# Zielzustand 'compliant' (Ergebnisklasse 1): Der SSH-Dienst bietet ausschliesslich
# kryptografische Verfahren nach Stand der Technik (BSI TR-02102-4) an - AEAD-/
# CTR-Ciphers, SHA2-MACs (ETM bevorzugt), moderne KEX. Keine Legacy-Verfahren.
# Korrektes Audit-Urteil: konform.
#
# Der Pod-Bootstrap hat bereits eine sichere Auth-sshd_config geschrieben
# (Pubkey ja, Passwort nein, UsePAM ja). Hier werden NUR die Krypto-Suiten
# explizit gesetzt (Ciphers/MACs/KexAlgorithms ersetzen jeweils die Default-
# Liste). Die Auth-Faehigkeit (Preflight) bleibt unveraendert.
set -euo pipefail

cat >> /etc/ssh/sshd_config <<'SSHD'

# --- SYS.2.1.A18: Krypto nach Stand der Technik (TR-02102) ---
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
SSHD

# Host-Keys + privsep-Verzeichnis sicherstellen (idempotent; der Bootstrap
# wiederholt beides), dann Konfiguration validieren. /run/sshd MUSS vor `sshd -t`
# existieren, sonst: "Missing privilege separation directory: /run/sshd".
mkdir -p /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true
sshd -t
