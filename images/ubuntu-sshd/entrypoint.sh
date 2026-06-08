#!/bin/sh
set -e
# sshd_config + authorized_keys aus den gemounteten Lab-Objekten uebernehmen
if [ -f /etc/thesis/sshd_config ]; then
  cp /etc/thesis/sshd_config /etc/ssh/sshd_config
  chmod 644 /etc/ssh/sshd_config
fi
if [ -f /etc/thesis/authorized_keys ]; then
  install -m 600 -o audit -g audit /etc/thesis/authorized_keys /home/audit/.ssh/authorized_keys
fi
ssh-keygen -A
mkdir -p /run/sshd
exec /usr/sbin/sshd -D -e
