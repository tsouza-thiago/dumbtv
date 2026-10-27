# dumbtv — edição Fire TV Stick 3ª geração

Versão enxuta do [dumbtv](https://github.com/humblemuzzu/dumbtv) (commit `755991b`),
ajustada para **um único aparelho** e focada em **desempenho** com **risco baixo ou médio**.

| Item | Valor aceito |
|---|---|
| Aparelho | Fire TV Stick 3ª geração (`AFTSSS`) |
| Fire OS | 7.7.1.7 (`PS7717/5741`), SDK 28 |
| Tela inicial | `com.amazon.tv.launcher` 7321874.1 |

Os scripts conferem esses valores (`device.conf`) e **recusam** qualquer outro aparelho ou versão.

## O que faz

| Script | Risco | Muda a TV? | Função |
|---|---|---|---|
| `preflight.sh` | nenhum | não | Confere o aparelho, mostra o estado e salva o snapshot original |
| `measure.sh` | nenhum | não | Mede RAM, processos e armazenamento e compara com a medição anterior |
| `debloat.sh` | baixo | com `--apply` | Desativa 35 pacotes de anúncios/telemetria e aplica 13 ajustes de desempenho e privacidade |
| `lockdown.sh` | médio, opcional | com `--apply` | Corta o segundo plano de 3 pacotes que a Amazon não deixa desativar |
| `cache.sh` | baixo, opcional | com `--apply` | Limpa o cache dos apps para liberar armazenamento |
| `verify.sh` | nenhum | não | Confere o resultado e a saúde da TV |
| `restore.sh` | — | com `--apply` | Desfaz tudo o que foi registrado no journal |
| `all.sh` | — | com `--apply` | preflight → medição → debloat → (lockdown) → verify |

**Ajustes de desempenho:** sem vídeo automático na tela inicial, sem notificações flutuantes,
animações de janela e transição em 0,5. `animator_duration_scale` **não** é alterado.

## O que nunca faz

- Desinstalar qualquer coisa.
- Trocar a tela inicial, instalar apps, instalar VPN ou filtro DNS.
- Tocar na tela inicial, nas configurações, no controle remoto, no HDMI, no Bluetooth,
  na loja, no Prime Video ou no **atualizador do sistema** (`data/never-disable.txt`).
- Gravar em `/system`, usar root ou fazer restauração de fábrica.

## Guardrails

1. **Simulação por padrão.** Sem `--apply`, nada muda na TV; cada comando é só exibido.
2. **Perfil do aparelho.** Modelo e SDK divergentes bloqueiam sempre. Build ou tela inicial
   divergentes (por exemplo, depois de uma atualização) bloqueiam até você revisar e rodar
   com `ALLOW_UNTESTED=1`.
3. **Lista fechada de comandos.** `acmd` (em `scripts/lib.sh`) só aceita `pm disable-user`,
   `pm enable`, `settings put/delete` de chaves listadas, `appops` de segundo plano,
   `am force-stop` e `pm trim-caches`. Qualquer outro comando é recusado.
4. **Pacotes protegidos.** Recusa pacotes de `never-disable.txt`, pacotes fora das listas e
   nomes de risco (tela inicial, systemui, webview, atualizador, instalador, Bluetooth).
5. **Journal.** Cada mudança vai para `report/journal.tsv` com o valor anterior.
   O `restore.sh` desfaz na ordem inversa, mesmo se a execução parou no meio.
6. **Para na primeira surpresa.** Resposta inesperada da TV ou perda de conexão interrompe tudo.
7. **Saúde com desfazer automático.** Depois do reinício, confere os pacotes essenciais,
   o systemui e a tela inicial. Se algo falhar, desfaz tudo sozinho e reinicia.
8. **Uma execução por vez** (`report/.lock`) e `dumbtv.conf` lido sem executar código.

## Como usar

Pré-requisitos: `adb` no PATH e Depuração ADB ligada na TV
(Configurações → Minha Fire TV → Sobre → OK 7 vezes no nome → Opções do desenvolvedor → Depuração ADB).

```bash
adb connect IP_DA_TV:5555
```
```bash
./scripts/preflight.sh
```
```bash
./scripts/measure.sh antes
```
```bash
./scripts/debloat.sh
```
```bash
./scripts/debloat.sh --apply
```
Espere uns 5 minutos depois do reinício:
```bash
./scripts/measure.sh depois
```
```bash
./scripts/verify.sh
```
Para desfazer:
```bash
./scripts/restore.sh --apply
```

## Configuração opcional (`dumbtv.conf`)

```sh
ALEXA=1        # 0 desativa a Alexa e o botão de voz (libera RAM; risco médio)
LOCKDOWN=0     # 1 faz o all.sh rodar o lockdown.sh
KEEP_APPS=""   # pacotes das listas que você quer manter, separados por espaço
```

## Testes

O ambiente de testes usa um `adb` simulado (`tests/fake_adb.py`) que imita este aparelho.
Nenhuma TV é tocada.

```bash
python3 -I -m unittest discover -s tests -v
```

Os 25 testes cobrem: perfil errado, simulação sem mudanças, aplicação e restauração exata,
idempotência, falha de saúde com desfazer automático, TV caindo no meio, trava,
guardrail de comandos, `dumbtv.conf` malicioso, Alexa, lockdown, cache e medição.

## Limites conhecidos

- O simulador imita as respostas do Fire OS 7, mas não é a TV real. Rode a simulação
  (sem `--apply`) na TV antes de aplicar.
- Depois de uma atualização do Fire OS, os scripts param. Revise as listas antes de usar
  `ALLOW_UNTESTED=1`.
- Licença MIT (veja `LICENSE`). Listas de pacotes originais dos contribuidores do dumbtv.
