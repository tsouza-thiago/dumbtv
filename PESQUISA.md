# Pesquisa: ferramentas e fontes para o fork `dumbtv` (Fire TV Stick 3ª geração)

Data: 27/10/2026. O que foi implementado está em [MUDANCAS.md](MUDANCAS.md), seção 9.
Escopo: fork `tsouza-thiago/dumbtv`, branch `fire-tv-stick-3`, aparelho `AFTSSS`, Fire OS 7.7.1.7 (`PS7717/5741`).

## Legenda

- **[C]** = confirmado pela fonte (li o arquivo ou a página).
- **[I]** = inferência minha. Precisa de teste na TV.
- **Risco** segue a filosofia do fork: só baixo ou médio entram. Alto fica fora.
- "T1" = Fire TV 2-Series `AFTKAUK002`, **mesmo build `PS7717/5741`**, testado pelo projeto `debloatfiretv`. É outro hardware (TV MediaTek), não o stick.

## Resumo

1. A fonte mais útil é o `jannikloehr/debloatfiretv`. Ele tem um inventário real do **mesmo build** do fork e um veredito por pacote. [C]
2. **`com.amazon.tigris` está na lista de desativar do fork, mas um guia diz que ele faz parte da loja de apps.** Ele não existe no T1 nem nos relatórios AFTSS/AFTKA do upstream. Função não confirmada. Recomendo tirá-lo da lista. [C fontes / I função]
3. Há conflito de descrição em `com.amazon.logan` (log ou leitor de tela VoiceView) e alerta em `com.amazon.dp.logger` (pode quebrar o app de controle remoto do celular). [C fontes divergem]
4. Os filtros do AdGuard DNS **não bloqueiam** nenhum servidor de OTA nem o `device-messaging-na.amazon.com`. Conferi o arquivo do filtro. [C]
5. Não achei confirmação de que o DNS privado funciona no **AFTSSS**. Há relatos de sucesso em outros Fire TV e relatos de **perda de internet depois de reiniciar**. [C relatos / I para o AFTSSS]
6. O `shellcheck` não foi rodado no fork. Ele é a melhoria de qualidade mais barata. [C]

## 1. Tabela de ferramentas e fontes

| Ferramenta / fonte | O que faz | Evidência de teste | Manutenção | Licença | Risco | Como agregaria ao fork |
|---|---|---|---|---|---|---|
| [jannikloehr/debloatfiretv](https://github.com/jannikloehr/debloatfiretv) | Debloat por `pm disable-user`, simulação por padrão, `restore.sh`, inventário por aparelho | Inventário real do T1 no build `PS7717/5741`; veredito por pacote (`safe`, `caution`, `keep`, `protected`) [C] | Último push 21/10/2026; 1 estrela [C] | MIT [C] | Baixo (como referência) | Valida `packages.txt`, `protected.txt` e `settings.txt`; dá a lista `keep` para `never-disable.txt` |
| [humblemuzzu/dumbtv](https://github.com/humblemuzzu/dumbtv), pasta `catalog/` (commit `755991b`) | Relatórios de aparelhos testados | `fireos-amazon-aftsss.yaml`: status `partial`, build `PS7717.5741N`, 1 contribuidor. `aftss.yaml`: 3 sticks testados no mesmo build [C] | Push 27/10/2026; 1.656 estrelas [C] | Sem SPDX no GitHub; `catalog/LICENSE` próprio [C] | Baixo | Peculiaridades reais do build: pacotes ausentes, `tahoe` = Amazon Kids, `spiderpork` = Luna, reinício que falha na 1ª vez (o fork já trata) |
| [WB2024/firestrip](https://github.com/WB2024/firestrip) | TUI/CLI Python de debloat, telemetria e launcher | Tem `tests/` com pytest [C]. O perfil `firetv_stick_3g.toml` está **vazio**: sem teste no stick 3 [C]. O `debloatfiretv` achou chaves `settings` inválidas nele [C] | Push 08/05/2026; 73 estrelas [C] | MIT [C] | A ferramenta: alto (troca launcher, bloqueia OTA). A lista: baixo | Alertas por pacote (`⚠ REMOTE-APP`, `LOGIN-BREAK`, `RISKY-UI`) para reforçar `never-disable.txt` |
| [roy9611/firetv-safe-debloat](https://github.com/roy9611/firetv-safe-debloat) | Debloat, `appops RUN_IN_BACKGROUND ignore` em apps pesados, DNS privado AdGuard, `verify_health` | Diz "battle-tested" e cita Fire OS 7.6.8.8 [C]. Não achei testes automatizados nem relatório por aparelho [I] | Push 22/10/2026; 22 estrelas [C] | MIT [C] | Médio | Ideia de `appops` em apps de terceiros pesados; afirma que o DNS privado persiste no reinício (afirmação, não teste) |
| [CleanYourTV: Debloat Fire TV](https://cleanyourtv.site/debloat-fire-tv/) | Guia com listas "seguro", "não desativar" e "protegido" | Relatos da comunidade; sem aparelho e build citados [C] | Página atual (2026) [I] | Não informada | Baixo (referência) | Alerta sobre `com.amazon.tigris`; confirma `device.metrics` e `ftvads.deeplinking` como protegidos |
| [UAD-ng](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation) | GUI Rust de debloat por ADB com níveis Recommended/Advanced/Expert/Unsafe | Projeto grande e ativo [C]. Só **13 pacotes Amazon** na lista; nenhum do Fire TV além de `com.amazon.venezia` (Advanced) [C] | Push 26/10/2026; 9.589 estrelas [C] | GPL-3.0 [C] | Baixo | Pouco valor para o Fire TV hoje. O fork poderia contribuir com a lista dele |
| [universal-android-preinstalled-lists](https://github.com/Universal-Debloater-Alliance/universal-android-preinstalled-lists) | Base de pacotes pré-instalados (WIP) | Sem teste próprio [C] | Push 06/01/2025: parado [C] | LGPL-3.0 [C] | — | Nenhum valor prático hoje |
| [ivantrj/firetv-glass-launcher](https://github.com/ivantrj/firetv-glass-launcher), [itsmeterrylin/fire-tv-cleanup](https://github.com/itsmeterrylin/fire-tv-cleanup), [vom00/firestick-tv](https://github.com/vom00/firestick-tv) | Debloat + troca da tela inicial | Relatos dos autores [C] | Pushes de 22 a 24/10/2026 [C] | MIT / sem SPDX / nenhuma [C] | **Alto** (troca a interface) | Fora do escopo. Só nota útil: OTA pode reativar pacotes; Alexa volta no boot (vom00) [C] |
| [seun-novodev/android-tv-debloat-toolkit](https://github.com/seun-novodev/android-tv-debloat-toolkit) | Kit genérico para Android TV | Não verificado [I] | Push 28/06/2026; 786 estrelas [C] | MIT [C] | Médio | Pouco: não é específico do Fire OS |
| [AdGuard DNS filter](https://github.com/AdguardTeam/AdGuardSDNSFilter) | Lista usada pelo AdGuard DNS | Baixei o `filter.txt` (186 mil linhas). Nenhum host de OTA nem `device-messaging-na` aparece. `mads.amazon.com` aparece [C] | Push 27/10/2026 [C] | GPL-3.0 [C] | Baixo | Confirma que o padrão `dns.adguard-dns.com` não bloqueia OTA hoje. Que o servidor usa exatamente esse filtro é [I] |
| [Perflyst/PiHoleBlocklist](https://github.com/Perflyst/PiHoleBlocklist) `AmazonFireTV.txt` | Lista de domínios Fire TV para Pi-hole | Lista da comunidade [C] | Push 09/09/2026 [C] | MIT [C] | Médio | Contraexemplo: bloqueia `device-messaging-na.amazon.com`, que o upstream diz ser necessário ao Prime Video [C] |
| [hagezi/dns-blocklists](https://github.com/hagezi/dns-blocklists) | Listas DNS, inclusive rastreadores nativos | Não consegui baixar a lista da Amazon [C] | Push 27/10/2026; 27,9 mil estrelas [C] | GPL-3.0 [C] | Baixo | Alternativa para `probe`; conteúdo não verificado [I] |
| [Mullvad DNS](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls) | DoT na porta 853: `dns`, `adblock`, `base`, `extended`, `family`, `all` `.dns.mullvad.net` | Documentação oficial [C] | Ativo [C] | Serviço | Baixo | Alternativa ao AdGuard para `DNS_HOST` (`adblock.dns.mullvad.net`) |
| [ShellCheck](https://github.com/koalaman/shellcheck) | Análise estática de shell | Padrão da indústria [C] | Push 26/10/2026; 40 mil estrelas [C] | GPL-3.0 [C] | Nenhum (só no PC) | Teste novo: rodar em `scripts/*.sh` |
| [shfmt (mvdan/sh)](https://github.com/mvdan/sh) | Formatador e parser de shell | Amplo uso [C] | Push 27/10/2026 [C] | BSD-3-Clause [C] | Nenhum | `shfmt -d` como checagem de estilo |
| [bats-core](https://github.com/bats-core/bats-core) | Testes em Bash | Amplo uso [C] | Push 20/10/2026 [C] | MIT [C] | Nenhum | Valor baixo: o fork já tem 37 testes `unittest` sem dependências [I] |
| [Perfetto](https://github.com/google/perfetto) | Rastreamento de desempenho Android | Oficial do Google [C] | Push 27/10/2026 [C] | Apache-2.0 [C] | Médio | No Android 9 o serviço `traced` pode exigir `setprop` [I]: fora da lista fechada. Não recomendo agora |

## 2. Pacotes candidatos

### 2.1 Retirar de `packages.txt` (ou mudar de lista)

| Pacote | Lista atual | Proposta | Motivo e fonte | Risco de manter como está |
|---|---|---|---|---|
| `com.amazon.tigris` | `packages.txt` (telemetria) | Mover para `never-disable.txt` até confirmar a função | CleanYourTV: "não desativar", faz parte da loja (atualiza apps) [C]. Ausente no T1 e nos relatórios AFTSS/AFTKA do upstream [C]. Função real no AFTSSS: [I] | Médio (apps podem parar de atualizar) |
| `com.amazon.logan` | `packages.txt` (telemetria) | Manter, mas conferir antes com `dumpsys package com.amazon.logan` | `debloatfiretv`: "log upload agent", `safe` no T1 [C]. `firestrip`: "VoiceView accessibility screen reader" [C]. Fontes divergem | Médio se o dono usa VoiceView |
| `com.amazon.dp.logger` | `packages.txt` (telemetria) | Manter com aviso no comentário, ou mover para opcional | `firestrip`: `⚠ REMOTE-APP` (pode quebrar o app de controle remoto do celular) [C]. Não testado no T1 [C] | Baixo a médio |
| `com.amazon.alexadirectivebrokerservice`, `com.amazon.alexa.datastore.app` | `alexa.txt` (só com `ALEXA=0`) | Manter, mas documentar que o Matter depende deles | `debloatfiretv` os põe em `keep`: "Alexa backend, used by Matter" [C]. Matter no AFTSSS: [I] | Médio (já é opcional) |

### 2.2 Corrigir comentário

| Pacote | Comentário atual | Correção | Fonte |
|---|---|---|---|
| `com.amazon.hedwig` | "tempo assistido e engajamento" | "Amazon News; também fornece uma entrada de TV (`HedwigTvInputService`)" | `debloatfiretv` [C]; `firestrip` [C]; nota no catálogo do upstream [C] |

### 2.3 Entrar em `packages.txt` (desativar)

Todos testados como `safe` no T1, no mesmo build [C]. No AFTSSS, o efeito é [I].

| Pacote | Função | Fonte | Risco |
|---|---|---|---|
| `com.amazon.kso.blackbird` | Anúncios "Special Offers" | `debloatfiretv` (T1 `safe`), CleanYourTV [C] | Baixo |
| `com.amazon.device.sale.service` | Avisos de promoção | CleanYourTV; `firestrip` [C]. Não testado no T1 | Baixo a médio |
| `com.android.bips`, `com.android.printspooler` | Serviço de impressão (o stick não imprime) | `debloatfiretv` (T1 `safe`) [C] | Baixo |
| `com.amazon.recess`, `com.amazon.naatyam`, `com.amazon.minitv.android.app` | Stubs: jogos casuais, conteúdo indiano | `debloatfiretv` (T1 `safe`) [C] | Baixo |

Não recomendo agora (são apps que o dono pode usar, fora do critério "anúncio, telemetria, stub"):
`com.amazon.bueller.photos` (fotos no protetor de tela), `com.amazon.bueller.music`, `com.amazon.cloud9` (Silk), `com.amazon.gamehub`, `com.amazon.tahoe` (Amazon Kids, segundo o upstream [C]), `com.amazon.spiderpork` (Luna, segundo o upstream [C]). Se entrarem, que seja numa lista opcional com `KEEP_APPS`.

### 2.4 Entrar em `protected.txt` (só `appops` de segundo plano, `lockdown.sh`)

O Fire OS recusa `pm disable-user` nestes no T1 [C]. Antes, conferir o UID: o `lockdown.sh` já pula UID de sistema.

| Pacote | Função | Fonte | Risco |
|---|---|---|---|
| `com.amazon.device.logmanager` | Gerenciador de logs | `debloatfiretv` (T1 `protected`) [C] | Médio |
| `com.amazon.adep` | Pipeline de eventos de análise | `debloatfiretv` (T1 `protected`); `firestrip` [C] | Médio |
| `com.fireos.usagestats.proxy` | Estatísticas de uso de apps | `debloatfiretv` (T1 `protected`) [C] | Médio |

`com.amazon.tv.csapp` também é `protected` no T1 [C]. O fork o mantém fora de propósito. Recomendo manter assim.

### 2.5 Entrar em `never-disable.txt` (defesa em profundidade)

Nenhum destes está nas listas do fork hoje. Listá-los protege contra uma edição futura errada. Fonte: lista `keep` do `debloatfiretv` [C] e alertas do `firestrip` [C].

- Teclado e configurações: `com.amazon.tv.ime`, `com.amazon.tv.quicksettings*`, `com.amazon.tv.settings` (sem sufixo).
- Conta e login: `com.amazon.dcp`, `com.amazon.identity.auth.device.authorization`, `com.amazon.imp`, `com.amazon.tcomm`, `com.amazon.tcomm.client`.
- Transmissão e descoberta: `com.amazon.cast.sink`, `com.amazon.dialservice`, `com.amazon.whisperlink.core.android`.
- Entradas e TV ao vivo: `com.amazon.tv.livetv`, `com.amazon.tifobserver`, `com.amazon.franktvinput`.
- Atualização e armazenamento: `com.amazon.settings.systemupdates`, `com.amazon.device.lowstoragemanager`.
- Acessibilidade e voz: `com.ivona.tts.oem`, `com.ivona.orchestrator`, `com.svox.pico`.
- Outros: `com.amazon.ftv.screensaver`, `com.amazon.tv.matter`, `com.amazon.tv.mattercohost`, `com.android.documentsui`, `com.amazon.tahoe`, `com.amazon.spiderpork`.

Observação: `com.android.permissioncontroller` não existe no T1 [C]. No Android 9 ele ainda faz parte do `packageinstaller` [I]. A entrada é inofensiva.

### 2.6 Confirmações (sem mudança)

- `com.amazon.device.metrics`, `com.amazon.device.crashmanager`, `com.amazon.ftvads.deeplinking`: `protected` no T1 [C]. O fork já os trata pelo `lockdown.sh`. Correto.
- `com.amazon.vizzini`: o T1 (TV) desativou sem problema [C], mas o upstream relata que ele volta ativo e o fork registra a tela "Unable to Detect Your Remote" [C]. No stick, manter em `never-disable.txt`.
- `com.amazon.device.messaging`: manter protegido. O upstream diz que o Prime Video não abre sem ele [C].
- `com.amazon.tv.easyupgrade`: o T1 o desativa como "upsell" [C]. O fork o protege por mexer em atualização. Manter a decisão conservadora.
- Chaves de `settings.txt`: `amz_limit_ad_tracking`, `advertisingIdApp:interestBasedAds:value` e `USAGE_METRICS_UPLOAD_ENABLED` existem no 7.7.1.7; as chaves `amazon:*` do `firestrip` retornam `null` [C]. Valida o fork.

## 3. Ajustes de desempenho candidatos

| Ajuste | Comando | Evidência | Risco | Recomendação |
|---|---|---|---|---|
| `animator_duration_scale` em 0,5 | `settings put global animator_duration_scale 0.5` | Aplicado e testado no T1, Fire OS 7.7.1.7 [C]. O problema registrado no fork é do Fire OS 8 [C] | Médio | Opcional, desligado por padrão. Testar com a checagem de saúde com `--home` |
| Compilação ART em segundo plano, uma vez | `cmd package bg-dexopt-job` | Documentação Android: aplica perfis de compilação [C]. Nenhum teste no Fire TV [I] | Baixo a médio (CPU alta por minutos; usa mais armazenamento). Desfazer: `cmd package compile --reset -a` [I] | Avaliar. Precisa entrar na lista fechada de `acmd` e no journal |
| Corte de segundo plano em apps de terceiros pesados | `cmd appops set <pkg> RUN_IN_BACKGROUND ignore` | `roy9611/firetv-safe-debloat` afirma ganho de RAM ao sair do app [C]. Sem medição publicada [I] | Médio (pode cortar download, música em segundo plano e notificação) | Opcional, com lista do dono (`KEEP_APPS` ao contrário). Reaproveita o mecanismo do `lockdown.sh` |
| Limite de processos em segundo plano | Opções do desenvolvedor | Zera no reinício [C] (roy9611); pode piorar a troca de apps [C] | Médio | Não recomendo: não persiste e não passa pelo journal |
| `setprop persist.sys.fw.trimemptyapps 1` | `setprop` | Só um post, sem prova [C] | Alto (propriedade de sistema) | Fora da filosofia |
| Bloquear OTA, trocar launcher, VPN local | — | — | Alto | Fora da filosofia |
| `wifi_scan_always_enabled 0`, `ble_scan_always_enabled 0` | `settings put global …` | Nenhuma fonte Fire TV [I] | Baixo, mas o Bluetooth do controle é sensível | Não recomendo sem teste: ganho incerto |

## 4. DNS privado

### 4.1 Provedores DoT

| Provedor | Nome DoT | Bloqueia anúncios | Fonte |
|---|---|---|---|
| AdGuard | `dns.adguard-dns.com` (padrão do fork). O nome antigo `dns.adguard.com` ainda aparece em guias [C] | Sim | Gist e guias [C] |
| Mullvad | `adblock.dns.mullvad.net` (também `base`, `extended`, `all`) | Sim | Mullvad [C] |
| NextDNS | `<id>.dns.nextdns.io` | Sim, configurável por conta | [I] (conhecimento geral, não reverificado aqui) |
| Quad9 | `dns.quad9.net` | Não (só malware) | [I] |

### 4.2 O Fire OS respeita o `private_dns_mode`?

- Sucesso: moderador da XDA diz que funciona em todo Fire TV, mas não com todo provedor de internet [C]. `roy9611` afirma que funciona no Fire OS 7 e persiste no reinício [C, afirmação].
- Falha: "não funciona no Fire TV Cube 3ª geração" (XDA) [C]. Fórum da Amazon: perde a internet depois de reiniciar [C]. Gist: Fire TV Stick 4K Max 2ª geração perdeu a internet depois de 1,5 mês; só voltou com `private_dns_mode off` [C].
- AFTSSS: **sem relato específico** [C]. Conclusão: o comportamento é incerto [I].
- O ADB por rede continua a funcionar a partir do PC depois do CVE-2024-27350 (Fire OS 7.6.6.9); só o ADB local feito por apps na TV foi bloqueado [C]. O guardrail 8 do `AGENTS.md` continua válido.

### 4.3 Domínios para `data/dns-check.txt`

| Domínio | Função | Proposta | Fonte |
|---|---|---|---|
| `softwareupdates.amazon.com` | OTA | Já é `must` | upstream, guias [C] |
| `device-messaging-na.amazon.com` | Push ADM; o Prime Video depende dele | Novo `must` | upstream (PR #54) [C]; o Perflyst o bloqueia [C] |
| `distro-download.amazon.com`, `dubri19p4y5b.cloudfront.net`, `amzdigital-a.akamaihd.net`, `amzdigitaldownloads.edgesuite.net` | Download de OTA | Novo tipo `warn` (só avisa) ou `must` depois de testar | `extra-hosts.txt` do upstream [C]; guias de bloqueio de OTA [C] |
| `mads.amazon.com` | Anúncio da Amazon | Novo `probe`, ao lado de `doubleclick.net` | Está no filtro do AdGuard [C] |

Os CDNs podem não resolver em toda região [I]. Por isso sugiro `warn` antes de `must`.

## 5. Ferramentas para o `measure.sh` (só leitura, risco nenhum)

Todas são comandos padrão do Android 9 [I: não testados no AFTSSS].

- `dumpsys gfxinfo com.amazon.tv.launcher`: quadros totais e quadros lentos ("Janky frames") da tela inicial.
- `dumpsys procstats --hours 3`: uso médio de memória por processo nas últimas horas. Mais estável que um retrato único.
- `cat /proc/loadavg` e `dumpsys cpuinfo`: carga da CPU em repouso.
- Tempo de boot: `cat /proc/uptime` logo depois de `sys.boot_completed=1`.
- Tempo de abertura de app: `am start -W -n <componente>` mostra `TotalTime` [C]. Ele **abre** um app: não é só leitura. Se entrar, precisa de flag própria e da lista fechada.

## 6. Melhorias recomendadas (ordem de prioridade)

1. **Tirar `com.amazon.tigris` de `packages.txt`** e pô-lo em `never-disable.txt`. No `preflight.sh`, mostrar (só leitura) `dumpsys package` resumido de `tigris`, `logan` e `dp.logger` para confirmar a função na TV real. Risco da mudança: nenhum. Corrigir também o comentário de `hedwig`.
2. **Reforçar o `dns.sh` contra a falha depois do reinício.** Rodar as checagens de `dns-check.txt` também no `verify.sh` depois de reiniciar. Adicionar `device-messaging-na.amazon.com` como `must`, os CDNs de OTA como aviso e `mads.amazon.com` como `probe`. Risco: baixo.
3. **Rodar `shellcheck` (e `shfmt -d`) num teste novo**, pulado se a ferramenta não existir. Fecha o limite citado em `MUDANCAS.md` §8. Risco: nenhum.
4. **Ampliar as listas com base no T1**: a seção 2.5 em `never-disable.txt` (com teste que confere a lista); `kso.blackbird`, `bips` e `printspooler` em `packages.txt`; `logmanager`, `adep` e `usagestats.proxy` em `protected.txt`, depois de conferir o UID. Risco: baixo (`never-disable`) a médio (`protected`).
5. **Medições só de leitura no `measure.sh`** (seção 5). Depois, testar `animator_duration_scale 0.5` como opção, com a checagem de saúde `--home`. Risco: nenhum (medição) e médio (animação).

## 7. Fontes

- jannikloehr/debloatfiretv: https://github.com/jannikloehr/debloatfiretv (arquivos `research/packages.md` e `research/devices/AFTKAUK002-…/system.txt`)
- humblemuzzu/dumbtv: https://github.com/humblemuzzu/dumbtv (commit `755991b`: `catalog/devices/fireos-amazon-aftsss.yaml`, `fireos-amazon-aftss.yaml`, `data/blocklists/extra-hosts.txt`)
- WB2024/firestrip: https://github.com/WB2024/firestrip (`firestrip/data/packages/common.toml`, `firetv_stick_3g.toml`)
- roy9611/firetv-safe-debloat: https://github.com/roy9611/firetv-safe-debloat
- CleanYourTV, "Debloat Fire TV & Fire Stick": https://cleanyourtv.site/debloat-fire-tv/
- UAD-ng: https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation
- universal-android-preinstalled-lists: https://github.com/Universal-Debloater-Alliance/universal-android-preinstalled-lists
- ivantrj/firetv-glass-launcher: https://github.com/ivantrj/firetv-glass-launcher
- itsmeterrylin/fire-tv-cleanup: https://github.com/itsmeterrylin/fire-tv-cleanup
- vom00/firestick-tv: https://github.com/vom00/firestick-tv
- seun-novodev/android-tv-debloat-toolkit: https://github.com/seun-novodev/android-tv-debloat-toolkit
- XDA, "Debloat list for OS7 PS7704.5024N": https://xdaforums.com/t/debloat-list-for-os7-ps7704-5024n-fire-tv-4-series.4765581/
- XDA, "Block updates. DNS way": https://xdaforums.com/t/block-updates-dns-way-no-root-needed.4397079/page-2
- Gist "Enabling / Disabling private DNS via ADB": https://gist.github.com/sharunkumar/b6195cbbd26a0039ec87fbd3829aa6b3
- Fórum da Amazon, problema de DNS no Fire TV: https://www.amazonforum.com/s/question/0D56Q0000CSUhnwSQD/problem-dns-change-problem-fire-tv-second-generation
- AFTVnews, bloqueio do ADB local (CVE-2024-27350): https://aftvnews.com/amazon-blocks-long-running-fire-tv-capability-breaking-popular-apps-with-no-warning-and-giving-developers-the-runaround
- NVD, CVE-2024-27350: https://nvd.nist.gov/vuln/detail/CVE-2024-27350
- XDA Developers, domínios Amazon que escapam do Pi-hole: https://www.xda-developers.com/some-smart-devices-sneaking-around-pi-hole-blocking-them-was-easier/
- Troypoint, hosts de OTA: https://troypoint.com/block-amazon-fire-tv-updates/
- AdGuard DNS filter: https://github.com/AdguardTeam/AdGuardSDNSFilter
- Perflyst PiHoleBlocklist: https://github.com/Perflyst/PiHoleBlocklist
- HaGeZi DNS blocklists: https://github.com/hagezi/dns-blocklists
- Mullvad DoT/DoH: https://mullvad.net/en/help/dns-over-https-and-dns-over-tls
- Android Developers, medição de inicialização: https://medium.com/androiddevelopers/testing-app-startup-performance-36169c27ee55
- AOSP, configuração do ART/dexopt: https://source.android.com/docs/core/runtime/configure/package-manager
- ShellCheck: https://github.com/koalaman/shellcheck
- shfmt: https://github.com/mvdan/sh
- bats-core: https://github.com/bats-core/bats-core
- Perfetto: https://github.com/google/perfetto

## 8. Contra-provas feitas antes de implementar (27/10/2026)

| Hipótese | Teste | Resultado | Decisão |
|---|---|---|---|
| `com.amazon.tigris` existe no AFTSSS | Relatório real de um AFTSSS `PS7717.5741N` (cleanyourtv-app, issue #676) | Existe e foi **mantido ligado** por essa ferramenta [C] | Sai de `packages.txt`, entra em `never-disable.txt` |
| `com.amazon.logan` é seguro | Busca do nome; o mesmo relatório | Nenhuma fonte oficial; o cleanyourtv-app também o mantém ligado [C] | Fica na lista, mas o `debloat.sh` pula qualquer serviço de acessibilidade |
| `kso.blackbird` é seguro no AFTSSS | Mesmo relatório | Desligado sem erro [C] | Entra em `packages.txt` |
| `printspooler`, `naatyam`, `minitv`, `recess` existem no AFTSSS | Mesmo relatório | Existem e estão ligados; `bips` não aparece [C] | Entram (ausente é inofensivo) |
| `logmanager`, `adep` existem no AFTSSS | Mesmo relatório | Existem [C]; protegidos no T1 [C] | Entram em `protected.txt` (opcional) |
| O AdGuard DNS não bloqueia OTA | Consulta DoH a `dns.adguard-dns.com` | Todos os `must` e os 3 CDNs resolvem para IPs reais; `mads.amazon.com` e `doubleclick.net` voltam `0.0.0.0` [C] | `ota` e o novo `probe` entram |
| `distro-download.amazon.com` é um host de OTA ativo | DNS do sistema e AdGuard | **Não existe** (NXDOMAIN) [C] | Fica de fora |
| `animator_duration_scale 0.5` é seguro no Fire OS 7 | PR #3 do original | Um teste numa Fire TV Edition com Fire OS 7, sem build citado [C]; quebra as Configurações no Fire OS 8 [C] | Descartado: evidência fraca e a checagem de saúde não detecta o defeito |
| O fork tem erros de shell | `shellcheck` 0.10.0 oficial | 0 erros; 4 avisos (falsos positivos ou variáveis de laço); 3 notas reais de expansão sem aspas [C] | Corrigidos; teste novo |
| O reinício do stick falha na 1ª vez (relato no AFTSS) | Leitura de `ask_reboot` no `lib.sh` | O fork já repete com `reboot` puro [C] | Nada a mudar |

Fontes novas desta etapa:
- cleanyourtv-app, relatório AFTSSS: https://github.com/udhaykumarbala/cleanyourtv-app/issues/676
- dumbtv original, PR #3 (animator): https://github.com/humblemuzzu/dumbtv/pull/3
- Homestead, PR #29 (animator no Fire OS 8): https://github.com/Sarg338/Homestead/pull/29
- ShellCheck 0.10.0: https://github.com/koalaman/shellcheck/releases/tag/v0.10.0
