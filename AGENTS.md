# AGENTS.md

Instruções para um agente (Claude Code ou outro) que opera este projeto numa TV.

## Regras invioláveis

1. Rode `./scripts/preflight.sh` e a simulação (`./scripts/debloat.sh` sem `--apply`) antes de qualquer `--apply`.
2. Só use `--apply` depois que o dono aprovar, na conversa, aquela execução específica.
3. Nunca rode comandos `adb shell` que mudam a TV fora dos scripts. Os guardrails estão em `scripts/lib.sh`.
4. Nunca edite `device.conf`, `data/never-disable.txt` ou o guardrail (`check_cmd`) para contornar um bloqueio. Pare e explique o bloqueio ao dono.
5. Nunca use `ALLOW_UNTESTED=1` sem o dono pedir.
6. Nunca desinstale, nunca grave em `/system`, nunca use root e nunca faça restauração de fábrica.
7. Resposta inesperada ou TV sem resposta: pare e sugira `./scripts/restore.sh --apply`.
8. Rode os testes (`python3 -I -m unittest discover -s tests`) depois de mudar qualquer script.
