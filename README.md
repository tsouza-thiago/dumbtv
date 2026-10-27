# dumbtv — edição Fire TV Stick 3ª geração

Versão enxuta do [dumbtv](https://github.com/humblemuzzu/dumbtv) (commit `755991b`),
ajustada para **um único aparelho** e focada em **desempenho** com **risco baixo ou médio**.
Todas as diferenças em relação ao original, com os motivos, estão em [MUDANCAS.md](MUDANCAS.md).
A pesquisa de fontes e as contra-provas que embasam as listas estão em [PESQUISA.md](PESQUISA.md).

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
| `measure.sh` | nenhum | não | Mede RAM, processos, armazenamento, carga da CPU e quadros lentos da tela inicial, e compara com a medição anterior |
| `debloat.sh` | baixo | com `--apply` | Desativa 40 pacotes de anúncios/telemetria/stubs e aplica 13 ajustes de desempenho e privacidade |
| `lockdown.sh` | médio, opcional | com `--apply` | Corta o segundo plano de 5 pacotes que a Amazon não deixa desativar |
| `cache.sh` | baixo, opcional | com `--apply` | Limpa o cache dos apps para liberar armazenamento |
| `dns.sh` | baixo a médio, opcional | com `--apply` | Liga o DNS privado com bloqueio de anúncios, com checagens e desfazer automático |
| `verify.sh` | nenhum | não | Confere o resultado e a saúde da TV |
| `restore.sh` | — | com `--apply` | Desfaz tudo o que foi registrado no journal |
| `all.sh` | — | com `--apply` | preflight → medição → debloat → (lockdown) → verify |

**Ajustes de desempenho:** sem vídeo automático na tela inicial, sem notificações flutuantes,
animações de janela e transição em 0,5. `animator_duration_scale` **não** é alterado.

## O que nunca faz

- Desinstalar qualquer coisa.
- Trocar a tela inicial, instalar apps ou instalar VPN.
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

## DNS privado (opcional, `dns.sh`)

Liga o DNS privado nativo do Android (DNS-over-TLS) apontando para um servidor com
bloqueio de anúncios e rastreamento. Não instala app, não usa VPN e não gasta RAM.
O padrão é `dns.adguard-dns.com`; troque com `DNS_HOST` no `dumbtv.conf` ou `--host=`.

```bash
./scripts/dns.sh
```
```bash
./scripts/dns.sh --apply
```
Para desligar:
```bash
./scripts/dns.sh --off --apply
```

**Proteções:**
- Antes de mudar: confere se a TV tem internet e se o servidor responde na porta 853.
  Se algo falhar, nada é alterado.
- Depois de mudar: confere se os domínios de `data/dns-check.txt` resolvem, **incluindo os
  servidores de atualização do Fire OS**. Se algum não resolver ou vier bloqueado,
  desfaz sozinho.
- Depois de mudar: reinicia a TV e repete as checagens. Há relatos de Fire TV que só
  perdem a internet depois de reiniciar com o DNS privado. Se falhar, desfaz sozinho.
  `--no-reboot` pula esse passo (com aviso).
- Também confere os CDNs de download das atualizações e o `device-messaging-na.amazon.com`
  (o Prime Video depende dele).
- Informa se o filtro está mesmo ativo (o Fire OS pode ignorar o DNS privado; isso
  ainda não foi confirmado neste build).
- `--off` desfaz só o DNS; o debloat continua aplicado.

**Riscos que continuam:**
- Se o servidor sair do ar **dias depois**, a TV fica sem internet. Não há vigia contínuo.
- A Amazon esconde a opção do menu. **Enquanto o DNS privado estiver ligado, mantenha a
  Depuração ADB ligada**: é a única forma de desligá-lo sem restauração de fábrica.
  O ADB local funciona mesmo sem DNS, porque usa o IP.
- Apps com anúncios no meio do vídeo podem não reproduzir.
- O provedor de DNS vê os endereços que a TV consulta.

## Configuração opcional (`dumbtv.conf`)

```sh
ALEXA=1        # 0 desativa a Alexa, o botão de voz e o home theater com Echo (libera RAM; risco médio)
LOCKDOWN=0     # 1 faz o all.sh rodar o lockdown.sh
KEEP_APPS=""   # pacotes das listas que você quer manter, separados por espaço
DNS_HOST=dns.adguard-dns.com   # servidor do dns.sh (ex.: SEU-ID.dns.nextdns.io)
```

## Testes

O ambiente de testes usa um `adb` simulado (`tests/fake_adb.py`) que imita este aparelho.
Nenhuma TV é tocada.

```bash
python3 -I -m unittest discover -s tests -v
```

Os 44 testes cobrem: perfil errado, simulação sem mudanças, aplicação e restauração exata,
idempotência, falha de saúde com desfazer automático, TV caindo no meio, trava,
guardrail de comandos, `dumbtv.conf` malicioso, Alexa, lockdown, cache, medição e DNS
privado (servidor fora do ar, provedor que bloqueia atualizações, porta 853 fechada,
TV sem internet, servidor inválido, desligar só o DNS).

## Limites conhecidos

- O simulador imita as respostas do Fire OS 7, mas não é a TV real. Rode a simulação
  (sem `--apply`) na TV antes de aplicar.
- Depois de uma atualização do Fire OS, os scripts param. Revise as listas antes de usar
  `ALLOW_UNTESTED=1`.
- Licença MIT (veja `LICENSE`). Listas de pacotes originais dos contribuidores do dumbtv.
