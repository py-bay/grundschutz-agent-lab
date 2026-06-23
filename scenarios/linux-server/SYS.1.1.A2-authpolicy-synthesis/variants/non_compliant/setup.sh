#!/usr/bin/env bash
# Zielzustand 'non_compliant' (Ergebnisklasse 3, Adversarial-Kontrast): Rand-Haertung
# IDENTISCH zu 'compliant' (Faillock, Alterung, kein nullok) - die EINZIGE Variable
# ist die WIRKSAMKEIT der Passwort-Komplexitaets-/Laengen-Policy: die starke
# pwquality.conf ist NICHT in den PAM-Stack eingebunden und pam_unix laeuft ohne
# minlen. Nur durch Synthese (pwquality.conf <-> common-password) erkennbar.
# Korrektes Urteil: nicht konform.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get install -y -qq libpam-pwquality >/dev/null 2>&1 || true

sed -ri 's/^(PASS_MAX_DAYS).*/\1 365/' /etc/login.defs
sed -ri 's/^(PASS_MIN_DAYS).*/\1 1/' /etc/login.defs
for u in audit svcadmin ubuntu root; do id "$u" >/dev/null 2>&1 && chage -M 365 -m 1 "$u" 2>/dev/null || true; done

# Starke pwquality-DEKLARATION (suggeriert Konformitaet) ...
cat > /etc/security/pwquality.conf <<'EOF'
minlen = 14
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
EOF

# Kontosperrung identisch zu compliant (kein Differenzierungsmerkmal).
cat > /etc/security/faillock.conf <<'EOF'
deny = 3
unlock_time = 600
fail_interval = 900
EOF
cat > /etc/pam.d/common-auth <<'EOF'
auth required pam_faillock.so preauth silent
auth [success=1 default=ignore] pam_unix.so
auth [default=die] pam_faillock.so authfail
auth sufficient pam_faillock.so authsucc
auth requisite pam_deny.so
auth required pam_permit.so
EOF

# ... ABER die Komplexitaets-/Laengen-Policy ist wirkungslos: kein pam_pwquality
# im Stack, pam_unix OHNE minlen -> die starke pwquality.conf greift faktisch nicht.
cat > /etc/pam.d/common-password <<'EOF'
password [success=1 default=ignore] pam_unix.so obscure yescrypt
password requisite pam_deny.so
password required pam_permit.so
EOF
