# Pruefagent-Image: Claude Code headless als k8s-Job im Cluster (laptop-frei).
#
# Der Agent ist der PRUEFGEGENSTAND. Er erhaelt ausschliesslich Pruef-Prompt
# (ConfigMap, ohne Ground Truth) + privaten SSH-Key (Secret) -- KEIN Repo-,
# GT- oder Host-Mount. DZ2 traegt damit ueber Dateisystem-/Mount-Isolation:
# die Ground Truth liegt nur operator-seitig im Dateisystem, in keinem Pod.
# Siehe docs/architektur.md und docs/design-principles.md (DP2).
#
#   docker build -t git.k3s.pybay.de/gitsim/claude-code:latest images/claude-code
#   docker push  git.k3s.pybay.de/gitsim/claude-code:latest
#
# TODO vor dem Hauptlauf: claude-code-Version + node-Base per Digest pinnen
# (@sha256:...) -- Reproduzierbarkeit, kein npm-Drift (DZ5/DZ9).
FROM node:22-bookworm-slim

RUN export DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get install -y --no-install-recommends openssh-client ca-certificates jq \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g @anthropic-ai/claude-code \
 && useradd -m -s /bin/bash agent

COPY agent-entrypoint.sh /usr/local/bin/agent-entrypoint.sh
RUN chmod +x /usr/local/bin/agent-entrypoint.sh

# non-root: der Agent braucht keine Root-Rechte im eigenen Pod.
USER agent
WORKDIR /home/agent
ENTRYPOINT ["/usr/local/bin/agent-entrypoint.sh"]
