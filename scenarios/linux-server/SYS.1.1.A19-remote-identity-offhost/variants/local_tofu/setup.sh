#!/usr/bin/env bash
# Zielzustand 'local_tofu' (Ergebnisklasse 5, Adversarial-Kontrast): KEINE
# kryptografische Absicherung der Remote-Host-Identitaet - Trust-on-first-use,
# `StrictHostKeyChecking no`, keine CA. Remote-Identitaeten werden ungeprueft
# akzeptiert -> on-host sichtbar nicht konform.
set -euo pipefail

install -d -m 0755 /etc/ssh/ssh_config.d

cat > /etc/ssh/ssh_config.d/20-remote-trust.conf <<'EOF'
# Keine kryptografische Absicherung der Remote-Host-Identitaet (TOFU/blind)
StrictHostKeyChecking no
EOF
chmod 0644 /etc/ssh/ssh_config.d/20-remote-trust.conf

cat > /etc/ssh/remote-trust.policy <<'EOF'
remote_host_identity=tofu (StrictHostKeyChecking=no)
central_ca=none
note=Remote-Host-Schluessel werden ungeprueft akzeptiert; keine CA, kein Pinning
EOF
chmod 0644 /etc/ssh/remote-trust.policy

# Kein lokaler Trust-Anker, keine zentrale Delegation.
rm -f /etc/ssh/trusted-ca-authority.json
