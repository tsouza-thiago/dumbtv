# Mudanças em relação ao dumbtv original

Este fork parte do commit [`755991b`](https://github.com/humblemuzzu/dumbtv/commit/755991b17a66e753e82f7252368c8850c08fdc71)
do [dumbtv](https://github.com/humblemuzzu/dumbtv) e o adapta a **um único aparelho**:
o Fire TV Stick 3ª geração, com Fire OS 7.7.1.7 e tela inicial 7321874.1.

O objetivo é **desempenho** com **risco baixo ou médio**. Tudo o que tinha risco alto
ou mudava a interface foi removido.

## 1. Por que um fork

O dumbtv original atende cerca de 20 aparelhos diferentes (Fire OS 6, 7 e 8, TVs com
Fire TV integrado e Android TV). Por isso, ele:

- troca a tela inicial e instala um filtro DNS por padrão;
- bloqueia as atualizações automáticas do sistema (pelo filtro DNS e pelo `lockdown.sh`);
- aceita qualquer aparelho Amazon, mesmo com uma versão nunca testada.

Para um único aparelho, focado em desempenho, essas escolhas trazem mais risco do que benefício.

## 2. O que foi removido

| Removido | Motivo |
|---|---|
| `launcher/` (dumbtv home) e `scripts/launcher.sh`, `home.sh`, `accessibility.sh` | Troca a interface. No Fire OS, isso exige contornar a tela inicial da Amazon com um serviço de acessibilidade: risco alto |
| `scripts/dnsfilter.sh`, `appdata.sh`, `appui.sh` e `data/blocklists/` | Instala uma VPN local que roda o tempo todo (gasta parte do 1 GB de RAM) e bloqueia as atualizações de segurança. Substituído pelo `dns.sh` (seção 5) |
| `scripts/youtube.sh` | Troca o app do YouTube por um app de terceiros; fora do escopo de desempenho |
| `scripts/configure.sh` | Substituído por um `dumbtv.conf` de três chaves, lido sem executar código |
| `scripts/discover.sh`, `contribute.sh` | Ferramentas para descobrir pacotes em aparelhos novos e enviar contribuições |
| `data/androidtv/`, `data/fireos6/`, `data/apps.txt`, `data/fireos/user-apps.txt` | Listas de outros aparelhos e de remoção de apps do usuário |
| `catalog/`, `docs/`, `.github/`, arquivos de comunidade | Catálogo de aparelhos, imprensa, CI e modelos de issue |
| `tests/*.py` originais | Presos aos scripts antigos; substituídos por uma suíte nova |

## 3. Listas de pacotes

### `data/packages.txt` (desativados pelo `debloat.sh`)

São 35 pacotes de anúncios, rastreamento, telemetria, experimentos e stubs vazios.
Três pacotes da lista original **saíram**:

| Pacote | Motivo |
|---|---|
| `com.amazon.tv.forcedotaupdater.v2` | Participa das atualizações obrigatórias. Desativá-lo pode atrasar as correções de segurança |
| `com.amazon.tv.easyupgrade` | Também participa das atualizações |
| `com.amazon.tv.developer.dataservice` | Função não documentada: risco desconhecido |

### `data/protected.txt` (opcional, `lockdown.sh`)

Ficaram só 3 pacotes: `com.amazon.device.metrics`, `com.amazon.device.crashmanager` e
`com.amazon.ftvads.deeplinking`. Quatro **saíram**:

| Pacote | Motivo |
|---|---|
| `com.amazon.device.software.ota` e `.ota.override` | Atualizador do sistema. Sem segundo plano, as atualizações não rodam |
| `com.amazon.device.rdmapplication`, `com.amazon.tv.csapp` | Função pouco clara (gerenciamento do aparelho) |

O `lockdown.sh` também **não liga mais a Economia de dados global**: no Wi-Fi ela não tem
efeito, e numa rede limitada ela afetaria todos os apps.

### `data/never-disable.txt`

Ganhou os 7 pacotes acima (atualizador e funções desconhecidas). Nenhum script consegue
desativar, parar ou restringir um pacote desta lista.

### `data/settings.txt`

Mantém os ajustes originais: sem vídeo automático na tela inicial, sem notificações
flutuantes, animações de janela e transição em 0,5 e os ajustes de privacidade.
`animator_duration_scale` continua **sem alteração**: em 0,5, ele deixou o menu de
Configurações inacessível num aparelho com Fire OS 8.

## 4. Guardrails novos

| # | Guardrail | Onde |
|---|---|---|
| 1 | **Simulação por padrão.** Sem `--apply`, nenhum comando que muda a TV é enviado | `parse_flags`, `acmd` |
| 2 | **Perfil do aparelho.** Modelo `AFTSSS` e SDK 28 são obrigatórios. Build `PS7717/5741` e tela inicial `7321874.1` só passam se baterem ou com `ALLOW_UNTESTED=1` | `device.conf`, `require_profile` |
| 3 | **Lista fechada de comandos.** Só `pm disable-user`, `pm enable`, `settings put/delete` (chaves listadas), `appops` de segundo plano, `am force-stop` e `pm trim-caches` | `check_cmd` |
| 4 | **Pacotes protegidos.** Recusa `never-disable.txt`, pacotes fora das listas e nomes de risco (tela inicial, systemui, webview, atualizador, instalador, Bluetooth, teclado, loja, configuração inicial) | `is_forbidden` |
| 5 | **Journal.** Cada mudança vai para `report/journal.tsv` com o valor anterior, logo depois de feita | `journal` |
| 6 | **Restauração exata.** O `restore.sh` desfaz o journal na ordem inversa. Configurações que não existiam são apagadas, não zeradas. Funciona mesmo depois de uma atualização do Fire OS | `undo_journal` |
| 7 | **Para na primeira surpresa.** Resposta inesperada da TV ou perda de conexão interrompe a execução | `debloat.sh` |
| 8 | **Saúde com desfazer automático.** Depois do reinício, confere os pacotes essenciais, o systemui e a tela inicial. Se falhar, desfaz tudo e reinicia | `health_check` |
| 9 | **Snapshot obrigatório.** O `debloat.sh` recusa rodar sem o snapshot do `preflight.sh` | `need_snapshot` |
| 10 | **Uma execução por vez** | `acquire_lock` (`report/.lock`) |
| 11 | **Configuração sem código.** `dumbtv.conf` é lido linha a linha, aceita só `ALEXA`, `LOCKDOWN` e `KEEP_APPS` e recusa qualquer outra coisa | `load_conf` |
| 12 | **Sem desinstalação.** Nenhum caminho do código chama `pm uninstall` | `check_cmd` |
| 13 | **DNS validado.** `private_dns_mode` só aceita `off`, `opportunistic` ou `hostname`; o servidor precisa ser um nome válido | `check_cmd`, `HOST_RE` |
| 14 | **Desfazer parcial.** `dns.sh --off` desfaz só as linhas de DNS do journal e mantém o debloat | `undo_where` |

## 5. Scripts novos

- **`measure.sh`**: mede RAM disponível, número de processos, espaço livre em `/data` e os 10
  maiores consumidores de memória. Salva em `report/` e compara com a medição anterior.
- **`cache.sh`**: limpa o cache dos apps com `pm trim-caches` (risco baixo). O aparelho tem
  só 8 GB, e pouco espaço livre deixa o sistema lento.
- **`dns.sh`**: liga o DNS privado nativo do Android (DNS-over-TLS) com um servidor que bloqueia
  anúncios. Substitui o filtro DNS por VPN do original.

### Por que DNS privado em vez da VPN do original

| | VPN local (original) | DNS privado (`dns.sh`) |
|---|---|---|
| App extra rodando | sim, o tempo todo | não |
| Consumo de RAM | sim | não |
| Atualizações de segurança | bloqueadas de propósito | **testadas**: se ficarem bloqueadas, o script desfaz |
| Lista de bloqueio | baixada de `@latest`, sem versão fixa | a do provedor escolhido |
| Passo manual na TV | permissão da VPN | nenhum |
| Desfazer | script próprio | `dns.sh --off` ou `restore.sh` |

### Checagens do `dns.sh`

1. **Antes:** a TV precisa resolver os domínios de `data/dns-check.txt` e o computador precisa
   alcançar o servidor na porta 853. Se não, nada muda.
2. **Depois:** os mesmos domínios precisam resolver para um IP real, incluindo
   `softwareupdates.amazon.com` e `updates.amazon.com`. Se algum falhar ou vier bloqueado
   (`0.0.0.0`), o script desfaz sozinho e confirma que a TV voltou a resolver nomes.
3. **Informativo:** testa um domínio de anúncio para dizer se o filtro está ativo.

### Riscos que continuam

- Se o servidor sair do ar dias depois, a TV fica sem internet. Não há vigia contínuo.
- A Amazon esconde a opção do menu: com o DNS privado ligado, a Depuração ADB precisa
  continuar ligada. O `verify.sh` avisa isso.
- Ainda não está confirmado que o Fire OS 7.7.1.7 respeita o DNS privado. O teste
  informativo do passo 3 mostra isso na primeira execução real.

## 6. Bug corrigido

O original usava o padrão `comando | grep -q` junto com `set -o pipefail`. Quando o
`grep -q` acha o que procura, ele encerra antes do fim da leitura, e o comando anterior
pode receber SIGPIPE. Com `pipefail`, o pipeline inteiro retorna **falha**, mesmo com o
resultado encontrado.

Na checagem de pacotes protegidos, isso **poderia deixar passar um pacote que deveria ser
bloqueado**. Todos os pontos agora usam here-strings (`grep -q ... <<<"$(comando)"`). Os
testes de guardrail cobrem o caso.

## 7. Ambiente de testes

- **`tests/fake_adb.py`**: um `adb` simulado que imita o Fire TV Stick 3ª geração no build
  PS7717/5741. Ele guarda o estado da TV em JSON (pacotes, configurações, appops, processos,
  boot, resolução de nomes e servidores DNS-over-TLS) e registra cada comando recebido. Simula pacotes protegidos, pacotes desativados pelo
  sistema, processos que sobrevivem à desativação, queda de conexão e tela inicial quebrada.
- **`tests/test_dumbtv.py`**: 37 testes com `unittest`, sem dependências externas.

| Grupo | O que é testado |
|---|---|
| Listas | Sem duplicados, sem cruzamento com `never-disable`, sem nomes de risco, atualizador protegido, `animator` intocado, sintaxe bash |
| Perfil | Modelo errado bloqueia; build ou tela inicial diferentes bloqueiam; `ALLOW_UNTESTED` libera; restauração funciona depois de uma atualização |
| Debloat | Simulação não muda nada; exige snapshot; sem confirmação não aplica; aplicação + verificação + restauração idêntica ao original; idempotência; falha de saúde com desfazer automático; queda da TV no meio + restauração; trava; `KEEP_APPS`; Alexa desligada |
| Guardrails | 14 comandos perigosos bloqueados sem chegar à TV; comando permitido passa; `dumbtv.conf` malicioso não executa código |
| Extras | Lockdown pula UID de sistema e nunca toca no atualizador; cache; medição compara; `all.sh` em simulação e aplicação |
| DNS | Simulação; ligar + verificar + desligar; servidor fora do ar desfaz sozinho; provedor que bloqueia atualizações é recusado; porta 853 fechada e TV sem internet não mudam nada; servidor inválido recusado; servidor do `dumbtv.conf`; `--off` preserva o debloat; `restore.sh` desfaz tudo; guardrail do DNS |

Para rodar:

```bash
python3 -I -m unittest discover -s tests -v
```

## 8. Limites

- O simulador imita as respostas do Fire OS 7, mas não é a TV real. Na primeira vez, rode
  `./scripts/preflight.sh` e `./scripts/debloat.sh` **sem `--apply`** e confira a saída.
- O código de modelo `AFTSSS` vem do catálogo do projeto original. Se a TV informar outro
  valor, o `preflight.sh` bloqueia com segurança.
- A checagem estática usou `bash -n`. O `shellcheck` não foi executado.
