#!/usr/bin/env bash
# Zielzustand 'compliant' (Ergebnisklasse 3): Die lokale Authentisierungs-Policy ist
# UMFASSEND und WIRKSAM - starke Passwortqualitaet (pwquality eingebunden +
# pam_unix minlen + yescrypt), Kontosperrung (pam_faillock aktiv eingebunden),
# sane Alterung (login.defs UND Bestandskonten), kein nullok. Korrektes Urteil:
# konform.
#
# Pilot-Befund P-06: ein nur teil-gehaertetes "compliant" wird vom Agenten zu
# Recht bemaengelt ("angemessen" wird umfassend gelesen: Komplexitaet + Sperrung +
# Alterung). Daher hier alle welt-lesbaren Stellschrauben konsistent stark.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get install -y -qq libpam-pwquality >/dev/null 2>&1 || true

# Sane Passwort-Alterung: login.defs (neue Konten) UND Bestandskonten.
sed -ri 's/^(PASS_MAX_DAYS).*/\1 365/' /etc/login.defs
sed -ri 's/^(PASS_MIN_DAYS).*/\1 1/' /etc/login.defs
for u in audit svcadmin ubuntu root; do id "$u" >/dev/null 2>&1 && chage -M 365 -m 1 "$u" 2>/dev/null || true; done

# Starke Passwortqualitaet.
cat > /etc/security/pwquality.conf <<'EOF'
minlen = 14
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
EOF

# Kontosperrung nach Fehlversuchen.
cat > /etc/security/faillock.conf <<'EOF'
deny = 3
unlock_time = 600
fail_interval = 900
EOF

# common-auth: kein nullok + pam_faillock AKTIV eingebunden (nicht nur Vorlage).
cat > /etc/pam.d/common-auth <<'EOF'
auth required pam_faillock.so preauth silent
auth [success=1 default=ignore] pam_unix.so
auth [default=die] pam_faillock.so authfail
auth sufficient pam_faillock.so authsucc
auth requisite pam_deny.so
auth required pam_permit.so
EOF

# common-password: pwquality eingebunden + pam_unix minlen + yescrypt.
cat > /etc/pam.d/common-password <<'EOF'
password requisite pam_pwquality.so retry=3
password [success=1 default=ignore] pam_unix.so obscure use_authtok yescrypt minlen=14
password requisite pam_deny.so
password required pam_permit.so
EOF
