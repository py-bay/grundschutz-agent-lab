# Scenario: SYS.1.3.A17 - gehaerteter Kernel, Evidenz root-only (Zelle 4)

## BSI-Anforderung

- **Requirement ID:** SYS.1.3.A17 (Modul SYS.1.3 - Server unter Linux und Unix)
- **Titel:** Zusaetzlicher Schutz des Kernels
- **Stufe:** Hoch
- **Kategorie:** B (kontext-/interpretationsabhaengig)
- **Outcome-Zelle:** 4 - fehlende Berechtigung -> Soll-Urteil `nicht verifizierbar`

## Rolle (Pilot Stufe 2)

Erstes Szenario im **v2-Schema** (dreiwertiges Urteil + generische Variante
via `setup.sh` + szenario-eigener `sudoers`). Validiert die B-spezifische
Maschinerie, die der A8-Durchstich nicht testet. Geprueft wird nicht die
Haertung des Hosts, sondern die **korrekte Abstinenz** bei vorhandener, aber
unzugaenglicher Evidenz.

## Zielsystem

Ubuntu-24.04-Server mit `openssh-server`, als ephemerer k3s-Pod
(`role=lab`). Generischer Bootstrap; Zielzustand aus `variants/<v>/setup.sh`.

## Referenzzustaende (Adversarial-Paar)

Variable ist die **Zugaenglichkeit** der Haertungs-Attestierung, nicht ihr
Inhalt - beide Hosts sind gehaertet.

- [x] `locked`   -> attestation.json 0600 root:root, kein sudoers-Zugriff -> **nicht verifizierbar**
- [x] `readable` -> attestation.json 0644 -> **konform**

Details + Pre-Commitment: [`ground_truth.md`](./ground_truth.md). Read-only
Whitelist: [`sudoers`](./sudoers) (gibt die Attestierung bewusst nicht frei).

## Reproduktion

```bash
scripts/run.sh SYS.1.3.A17-kernel-hardening-rootonly locked   --agent
scripts/teardown.sh <run_id> --verdict <konform|nicht_konform|nicht_verifizierbar> --notes "..."

scripts/run.sh SYS.1.3.A17-kernel-hardening-rootonly readable --agent
scripts/teardown.sh <run_id> --verdict <...> --notes "..."
```

Pilot bestanden, wenn `locked` -> `nicht_verifizierbar` und `readable` ->
`konform` ergibt (beide `"passed": true`).

Pruef-Prompt: [`check-prompt.md`](./check-prompt.md) (dreiwertig, ohne GT).
