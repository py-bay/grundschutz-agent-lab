#!/usr/bin/env bash
#
# target-bootstrap.sh - PID-1-Bootstrap des lokalen Docker-Targets. Wird von
# target-docker.sh read-only nach /mnt/boot/bootstrap.sh gemountet und als
# `bash /mnt/boot/bootstrap.sh` gestartet. Inhaltlich identisch zum Bootstrap
# in kubernetes/target-pod.tmpl.yaml (gleicher openssh-Bootstrap, audit-User,
# read-only sudoers-Whitelist, setup.sh-Etablierung).
#
# Quellen (bind-mounts):
#   /mnt/stage          Szenario-Dateien (setup.sh, audit_sudoers) - wie ConfigMap
#   /mnt/authkeys       authorized_keys (ephemerer Pubkey)         - wie Secret
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# apt-Listen IMMER bereitstellen (szenario-eigene setup.sh installiert ggf.
# Zusatzpakete); sshd nur installieren, wenn nicht vorhanden.
apt-get update -qq
if [ ! -x /usr/sbin/sshd ]; then
  apt-get install -y -qq openssh-server sudo >/dev/null
fi

# Szenario-Dateien root-only ablegen (Anti-Leakage, entspricht ConfigMap 0600):
# der audit-User (uid 1001) kann das erwartete Urteil nicht aus setup.sh/sudoers
# ablesen.
install -d -m 700 /root/thesis
cp /mnt/stage/* /root/thesis/ 2>/dev/null || true

id audit >/dev/null 2>&1 || useradd -m -s /bin/bash audit
install -d -m 700 -o audit -g audit /home/audit/.ssh
install -m 600 -o audit -g audit /mnt/authkeys/authorized_keys /home/audit/.ssh/authorized_keys

# Sichere Default-sshd_config (Pubkey-Login fuer audit, kein Passwort). UsePAM yes
# ist noetig: das frische audit-Konto hat ein gesperrtes Passwort (!); ohne PAM
# lehnt sshd auch Pubkey ab. setup.sh darf die Datei szenariospezifisch ueberschreiben.
cat > /etc/ssh/sshd_config <<'SSHD'
Port 22
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
PermitRootLogin no
AuthorizedKeysFile /home/audit/.ssh/authorized_keys
Subsystem sftp /usr/lib/openssh/sftp-server
SSHD
chmod 644 /etc/ssh/sshd_config

# read-only Tool-Layer: szenario-eigene Kommando-Whitelist (DZ6)
install -m 440 /root/thesis/audit_sudoers /etc/sudoers.d/audit

# Zielzustand etablieren (laeuft als root)
bash /root/thesis/setup.sh

ssh-keygen -A
mkdir -p /run/sshd
echo "[target] sshd startet (run=${RUN_ID:-?})"
exec /usr/sbin/sshd -D -e
