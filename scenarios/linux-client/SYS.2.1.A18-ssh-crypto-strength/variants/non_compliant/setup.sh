#!/usr/bin/env bash
# Zielzustand 'non_compliant' (Ergebnisklasse 2, Adversarial-Kontrast zu
# 'compliant'): Der SSH-Dienst aktiviert ZUSAETZLICH veraltete/schwache Verfahren,
# die nicht dem Stand der Technik (BSI TR-02102) entsprechen - CBC-Ciphers,
# HMAC-SHA1, SHA1-basierte KEX. Korrektes Audit-Urteil: nicht konform.
#
# Bewusst sind moderne Verfahren FUEHREND gelistet, damit Client/Server beim
# Login ein modernes Verfahren aushandeln (Preflight bleibt gruen). Die schwachen
# Verfahren sind dennoch ANGEBOTEN und in `sshd -T` sichtbar -> ein Angreifer
# koennte das schwaechste erzwingen. Nur Verfahren verwendet, die OpenSSH 9.x
# (Ubuntu 24.04) noch kennt, damit sshd startet.
set -euo pipefail

cat >> /etc/ssh/sshd_config <<'SSHD'

# --- SYS.2.1.A18: schwache Verfahren mit-aktiviert (NICHT TR-02102-konform) ---
Ciphers aes256-gcm@openssh.com,aes128-ctr,aes256-cbc,aes128-cbc
MACs hmac-sha2-256,hmac-sha1
KexAlgorithms curve25519-sha256,diffie-hellman-group14-sha1
SSHD

# Host-Keys sicherstellen (idempotent) und Konfiguration validieren. Schlaegt
# sshd -t fehl (Verfahren in dieser OpenSSH-Version nicht verfuegbar), bricht der
# Lauf hier sauber ab statt einen halb-gestarteten sshd zu hinterlassen.
ssh-keygen -A >/dev/null 2>&1 || true
sshd -t
