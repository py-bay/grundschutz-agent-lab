# Reproduzierbares SSH-Zielsystem fuer die eigentliche Evaluation.
#
# Der Smoke-Test (scripts/run.sh) nutzt aktuell ubuntu:24.04 + apt-install
# zur Laufzeit, damit kein Registry-/Pull-Secret-Setup noetig ist. Fuer die
# wissenschaftliche Evaluation ist dieses gepinnte Image vorzuziehen
# (kein apt-Drift, fixe Versionen). Bauen + in die Forgejo-OCI-Registry
# pushen, dann in target-pod.tmpl.yaml IMAGE darauf zeigen lassen.
#
#   docker build -t git.k3s.pybay.de/gitsim/ubuntu-sshd:24.04 images/ubuntu-sshd
#   docker push  git.k3s.pybay.de/gitsim/ubuntu-sshd:24.04
#
# Pinning (s. ../PINNING.md): Base per Digest ueber
#   --build-arg UBUNTU_REF=ubuntu@sha256:...   (bit-genaue Reproduzierbarkeit, DZ5)
ARG UBUNTU_REF=ubuntu:24.04
FROM ${UBUNTU_REF}

RUN export DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get install -y --no-install-recommends openssh-server sudo ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash audit \
 && install -d -m 700 -o audit -g audit /home/audit/.ssh \
 && echo 'audit ALL=(root) NOPASSWD: /usr/sbin/sshd -T' > /etc/sudoers.d/audit \
 && chmod 440 /etc/sudoers.d/audit \
 && mkdir -p /run/sshd

# Variante (sshd_config) und authorized_keys werden zur Laufzeit gemountet;
# Host-Keys werden beim Start erzeugt (per-Pod).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
