# Image- & Modell-Pinning für den Hauptlauf (DZ5/DZ9)

Für die summative Evaluation müssen Ziel- und Agent-Image **bit-genau
reproduzierbar** sein — kein `apt-`/`npm-`Drift, kein wanderndes Modell. Der
Smoke-/Pilot-Stand nutzt `:latest` + apt-at-runtime; das ist für den Hauptlauf
durch Digests + feste Versionen zu ersetzen. Die Dockerfiles sind dafür über
`ARG` vorbereitet — Pinning ist ein `--build-arg`, kein Code-Eingriff.

> Operator-seitig auszuführen (Registry-/Cluster-Zugriff). Aus Sandbox/Automation
> **nicht** ba/pushbar.

## 1. Base-Digests auflösen

```bash
# Ubuntu-Base
docker buildx imagetools inspect ubuntu:24.04 | grep -i digest
# Node-Base
docker buildx imagetools inspect node:22-bookworm-slim | grep -i digest
```

Die ausgegebenen `sha256:...` festhalten (in dieser Datei unter „Gepinnte Werte"
protokollieren — Provenienz).

## 2. claude-code-Version festlegen

```bash
npm view @anthropic-ai/claude-code version    # aktuelle Version ermitteln
```

Die gewählte Version (z. B. `1.2.3`) als `CLAUDE_CODE_VERSION` pinnen.

## 3. Bauen mit gepinnten Werten + pushen

```bash
# Zielsystem
docker build \
  --build-arg UBUNTU_REF=ubuntu@sha256:<DIGEST> \
  -t git.k3s.pybay.de/gitsim/ubuntu-sshd:24.04 images/ubuntu-sshd
docker push git.k3s.pybay.de/gitsim/ubuntu-sshd:24.04

# Agent
docker build \
  --build-arg NODE_REF=node@sha256:<DIGEST> \
  --build-arg CLAUDE_CODE_VERSION=<VERSION> \
  -t git.k3s.pybay.de/gitsim/claude-code:<VERSION> images/claude-code
docker push git.k3s.pybay.de/gitsim/claude-code:<VERSION>
```

Nach dem Push den **Push-Digest** des eigenen Images notieren (`docker
buildx imagetools inspect <ref>` bzw. die Push-Ausgabe) und im Lauf **per Digest**
referenzieren.

## 4. Im Lauf per Digest referenzieren (kein Code-Edit nötig)

`run.sh`/`lib.sh` lesen `IMAGE` (Target) und `AGENT_IMAGE` (Agent) aus der
Umgebung. Für den Hauptlauf:

```bash
export IMAGE='git.k3s.pybay.de/gitsim/ubuntu-sshd@sha256:<PUSH_DIGEST>'
export AGENT_IMAGE='git.k3s.pybay.de/gitsim/claude-code@sha256:<PUSH_DIGEST>'
scripts/run_item.sh <scenario-id> --k 4 --mode agent-incluster
```

> Hinweis: Das gepinnte Target-Image bringt `openssh-server`/`sudo` bereits mit;
> der apt-Schritt im Pod-Bootstrap entfällt dann. Falls das Target-Template noch
> apt-at-runtime annimmt, vor dem Hauptlauf den Bootstrap auf „Image bringt alles
> mit" umstellen (`kubernetes/target-pod.tmpl.yaml`).

## 5. Modell-, Hintergrundmodell-, Effort- & Permission-Pin (separate DZ5-Stellschrauben!)

Das Image pinnt die **claude-code-CLI**, **nicht** das Modell — die Laufzeit-Pins
sind davon getrennt. Setzung für den Hauptlauf (festgelegt 2026-06):

| Stellschraube | Setzung | Mechanik |
|---|---|---|
| Hauptmodell | `claude-opus-4-8` | Env `ANTHROPIC_MODEL` (run.sh → Job-Template) |
| Hintergrund-/Small-Fast-Modell | `claude-opus-4-8` | Env `ANTHROPIC_DEFAULT_HAIKU_MODEL` (= Pin). Ohne dies nutzt Claude Code **Haiku 4.5** für Titel/Hintergrund → taucht im `modelUsage` auf (Pilot-Befund). Löst `ANTHROPIC_SMALL_FAST_MODEL` ab. |
| Reasoning-Effort | `high` | `claude -p --effort` (Entrypoint), Env `AGENT_EFFORT` (lib.sh-Default `high`) |
| Permissions | Bypass | `claude -p --dangerously-skip-permissions` (Entrypoint); Target bleibt read-only via sudoers-Whitelist |

**Wichtig — keine Temperatur:** Opus 4.8/4.7 **entfernen** `temperature`/`top_p`/
`top_k`; die API quittiert sie mit **400**. Es gibt kein „Temperatur 0" mehr.
Steuergröße ist stattdessen `effort` + adaptives Thinking. Die Rest-Stochastik
ist **inhärent** — genau deshalb wird sie via **pass^k** gemessen statt per
`temperature=0` wegparametrisiert (DZ5-Begründung).

Es existiert **kein** datierter Snapshot für Opus 4.8 — `claude-opus-4-8` ist die
kanonische ID. Reproduzierbarkeit ruht auf (a) Alias repointet nicht im Lab-Fenster
+ (b) gepinnter claude-code-Version (Image-Digest) + (c) den obigen Laufzeit-Pins.

> Da der Entrypoint für effort/permission geändert wurde, ist ein **Agent-Image-
> Rebuild + Push Pflicht** (Schritt 3) — fällt bequem mit dem Digest-Pinning zusammen.
> Exakte Flag-Namen (`--effort`, `--dangerously-skip-permissions`) vor dem Rebuild
> mit `claude --help` der gepinnten CLI-Version gegenprüfen.

## Gepinnte Werte (Protokoll — vor dem Hauptlauf ausfüllen)

| Artefakt | Pin | Aufgelöst am |
|----------|-----|--------------|
| ubuntu base | `ubuntu@sha256:________` | |
| node base | `node@sha256:________` | |
| claude-code | Version `______` | |
| ubuntu-sshd push | `@sha256:________` | |
| claude-code push | `@sha256:________` | |
| Hauptmodell | `claude-opus-4-8` (Alias, kein dat. Snapshot) | |
| Hintergrundmodell | `claude-opus-4-8` (`ANTHROPIC_DEFAULT_HAIKU_MODEL`) | |
| Effort | `high` (`--effort`) | |
| Permissions | `--dangerously-skip-permissions` | |
