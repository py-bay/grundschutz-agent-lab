# Scenario: SYS.1.3.A8 - SSH Zertifikat statt Passwort

## BSI-Anforderung

- **Requirement ID:** SYS.1.3.A8 (Modul SYS.1.3 - Server unter Linux und Unix)
- **Titel:** Verschluesselter Zugriff ueber Secure Shell
- **Stufe:** Standard (SOLLTE)
- **Kategorie:** A (technisch ablesbar)

## Zielsystem

Ubuntu-24.04-Server mit `openssh-server`, als ephemerer k3s-Pod auf dem
Lab-Node (`role=lab`).

## Ground Truth

Siehe [`ground_truth.md`](./ground_truth.md) - pre-committed und pro Lauf
gehasht. Zwei Referenzzustaende:

- [x] konform     -> `variants/compliant/sshd_config`
- [x] nicht konform -> `variants/non_compliant/sshd_config`

## Reproduktion

```bash
# Variante hochziehen (Pod + ConfigMap + Secret + Manifest, dann Port-Forward):
scripts/run.sh SYS.1.3.A8-ssh-cert-vs-password compliant
scripts/run.sh SYS.1.3.A8-ssh-cert-vs-password non_compliant

# run.sh druckt am Ende das fertige `claude`-Kommando (mit run.id-Tagging)
# und den read-only SSH-Zugang. Agent laufen lassen, dann:
scripts/teardown.sh <run_id> --verdict <konform|nicht_konform> --notes "..."
```

Der Pruef-Prompt fuer den Agenten: [`check-prompt.md`](./check-prompt.md)
(enthaelt bewusst keine Ground Truth).
