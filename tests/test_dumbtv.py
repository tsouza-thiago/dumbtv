"""Testes dos scripts contra o adb simulado (tests/fake_adb.py).

Rode com:  python3 -I -m unittest discover -s tests -v
Nenhuma TV de verdade é usada: ADB aponta para o simulador.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAKE = ROOT / 'tests' / 'fake_adb.py'
SCRIPTS = ROOT / 'scripts'
LAUNCHER = 'com.amazon.tv.launcher/.ui.HomeActivity'
MUTATING = re.compile(r'^(pm (disable-user|enable|uninstall|trim-caches|clear|install)|'
                      r'settings (put|delete)|appops set|am force-stop|svc power reboot|'
                      r'reboot|rm |setprop|cmd netpolicy)')
FORBIDDEN = re.compile(r'^(pm (uninstall|clear|install)|rm |setprop|cmd netpolicy|wipe|remount)')
RISKY = re.compile(r'(\.launcher$|homestarter|systemui|webview|packageinstaller|permissioncontroller|'
                   r'inputmethod|bluetooth|software\.ota|otaupdater|easyupgrade|venezia|oobe|'
                   r'settings\.v2|settings\.core)')


def listing(name):
    rows = []
    for line in (ROOT / 'data' / name).read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if line:
            rows.append(line.split())
    return rows


def names(name):
    return [r[0] for r in listing(name)]


def fixture():
    """Estado inicial de um AFTSSS de fábrica no build PS7717/5741."""
    pkgs = {}
    uid = 10100
    for p in names('packages.txt') + names('alexa.txt') + names('never-disable.txt'):
        uid += 1
        pkgs[p] = {'state': 0, 'uid': uid}
    del pkgs['com.amazon.tv.acr']                         # ausente no stick
    pkgs['com.amazon.perfc']['protected'] = True          # a Amazon recusa
    pkgs['com.android.nfc']['state'] = 2                  # desativado pelo sistema
    # UIDs lidos num AFTSSS real (pm list packages -U).
    pkgs['com.amazon.device.metrics'] = {'state': 0, 'uid': 10182, 'protected': True}
    pkgs['com.amazon.device.crashmanager'] = {'state': 0, 'uid': 10016, 'protected': True}
    pkgs['com.amazon.ftvads.deeplinking'] = {'state': 0, 'uid': 10103, 'protected': True}
    pkgs['com.netflix.ninja'] = {'state': 0, 'uid': 10200}
    running = ['init', 'surfaceflinger', 'com.android.systemui', 'com.amazon.tv.launcher',
               'com.amazon.ceviche', 'com.amazon.hedwig', 'com.amazon.device.metrics',
               'com.amazon.ftvads.deeplinking', 'com.amazon.aca']
    return {
        'props': {
            'ro.product.manufacturer': 'Amazon', 'ro.product.model': 'AFTSSS',
            'ro.build.version.sdk': '28', 'ro.build.version.name': 'Fire OS 7.7.1.7 (PS7717/5741)',
            'ro.build.display.id': 'PS7717.5741N', 'sys.boot_completed': '1',
        },
        'launcher_version': '7321874.1',
        'pkgs': pkgs,
        'settings': {
            'secure': {'limit_ad_tracking': '0', 'USAGE_METRICS_UPLOAD_ENABLED': '1',
                       'usage_metrics_marketing_enabled': '1', 'non_amz_limit_ad_tracking': '0'},
            'global': {'window_animation_scale': '1.0', 'transition_animation_scale': '1.0',
                       'animator_duration_scale': '1.0', 'heads_up_notifications_enabled': '1',
                       'com.amazon.tv.settings.featured_item_video_enabled': '1'},
        },
        'appops': {},
        'running': list(running), 'base_running': list(running),
        'sticky': ['com.amazon.hedwig'],                  # continua vivo após desativar
        'boot_id': '1', 'front': LAUNCHER, 'calls': 0, 'offline_after': None,
        'internet': True,
        'dot': {'dns.adguard-dns.com': {'up': True, 'blocks': ['doubleclick.net', 'mads.amazon.com']}},
    }


class TV(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='dumbtv-test-'))
        self.state = self.tmp / 'state.json'
        self.log = self.tmp / 'adb.log'
        self.conf = self.tmp / 'dumbtv.conf'
        self.report = self.tmp / 'report'
        self.write(fixture())
        self.log.touch()
        self.initial = self.read()

    def write(self, st):
        self.state.write_text(json.dumps(st))

    def read(self):
        return json.loads(self.state.read_text())

    def tweak(self, fn):
        st = self.read()
        fn(st)
        self.write(st)

    def run_script(self, name, *args, env=None, conf=None, inp=''):
        if conf is not None:
            self.conf.write_text(conf)
        e = {'PATH': os.environ['PATH'], 'HOME': str(self.tmp), 'ADB': str(FAKE),
             'FAKE_TV_STATE': str(self.state), 'FAKE_TV_LOG': str(self.log),
             'REPORT': str(self.report), 'CONF': str(self.conf), 'DUMBTV_TEST': '1'}
        e.update(env or {})
        return subprocess.run(['bash', str(SCRIPTS / name), *args], env=e, input=inp,
                              capture_output=True, text=True, timeout=120)

    def ok(self, name, *args, **kw):
        r = self.run_script(name, *args, **kw)
        self.assertEqual(r.returncode, 0, f'{name} falhou:\n{r.stdout}\n{r.stderr}')
        return r

    def commands(self):
        return self.log.read_text().splitlines()

    def mutations(self):
        return [c for c in self.commands() if MUTATING.match(c)]

    def assert_no_forbidden(self):
        bad = [c for c in self.commands() if FORBIDDEN.match(c)]
        self.assertEqual(bad, [], 'comando proibido chegou à TV')
        for c in self.commands():
            m = re.match(r'pm disable-user --user 0 (\S+)', c)
            if m:
                self.assertNotIn(m.group(1), names('never-disable.txt'))
                self.assertIsNone(RISKY.search(m.group(1)), m.group(1))

    def assert_back_to_initial(self):
        now = self.read()
        for key in ('pkgs', 'settings', 'appops'):
            self.assertEqual(now[key], self.initial[key], f'{key} não voltou ao original')

    def state_of(self, p):
        return self.read()['pkgs'][p]['state']


class Lists(unittest.TestCase):
    def test_listas_sem_conflito(self):
        never = set(names('never-disable.txt'))
        for lst in ('packages.txt', 'alexa.txt', 'protected.txt'):
            items = names(lst)
            self.assertEqual(len(items), len(set(items)), f'duplicado em {lst}')
            self.assertEqual(never & set(items), set(), f'{lst} cruza com never-disable')
            for p in items:
                self.assertIsNone(RISKY.search(p), f'{p} casa com o padrão de risco')

    def test_atualizador_fora_de_qualquer_acao(self):
        never = names('never-disable.txt')
        for p in ('com.amazon.device.software.ota', 'com.amazon.tv.forcedotaupdater.v2',
                  'com.amazon.tv.easyupgrade', 'com.amazon.tv.launcher'):
            self.assertIn(p, never)

    def test_animator_nao_muda(self):
        keys = [r[1] for r in listing('settings.txt')]
        self.assertNotIn('animator_duration_scale', keys)

    def test_tigris_fora_de_qualquer_acao(self):
        # Ligado à loja de apps segundo a pesquisa; desativá-lo pode parar as atualizações dos apps.
        self.assertIn('com.amazon.tigris', names('never-disable.txt'))

    def test_shellcheck(self):
        sc = os.environ.get('SHELLCHECK') or shutil.which('shellcheck')
        if not sc:
            self.skipTest('shellcheck não instalado (sudo apt install shellcheck)')
        scripts = sorted(str(s) for s in SCRIPTS.glob('*.sh'))
        r = subprocess.run([sc, '-x', '-P', str(SCRIPTS), '-S', 'warning', *scripts],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_sintaxe_bash(self):
        for s in SCRIPTS.glob('*.sh'):
            r = subprocess.run(['bash', '-n', str(s)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, f'{s.name}: {r.stderr}')


class Perfil(TV):
    def test_modelo_errado_bloqueia(self):
        self.tweak(lambda s: s['props'].update({'ro.product.model': 'AFTMM'}))
        r = self.run_script('preflight.sh')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('AFTMM', r.stderr)
        self.assertEqual(self.mutations(), [])

    def test_build_nao_testado_bloqueia_e_override_libera(self):
        self.tweak(lambda s: s['props'].update({'ro.build.version.name': 'Fire OS 7.7.1.8 (PS7718/5800)',
                                                'ro.build.display.id': 'PS7718.5800N'}))
        self.assertNotEqual(self.run_script('preflight.sh').returncode, 0)
        r = self.ok('preflight.sh', env={'ALLOW_UNTESTED': '1'})
        self.assertIn('não testada', r.stderr)

    def test_versao_da_tela_inicial_diferente_bloqueia(self):
        self.tweak(lambda s: s.update({'launcher_version': '7400000.1'}))
        r = self.run_script('preflight.sh')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('tela inicial', r.stderr)

    def test_restore_funciona_mesmo_apos_atualizacao(self):
        self.ok('preflight.sh')
        self.ok('debloat.sh', '--apply', '-y')
        self.tweak(lambda s: s.update({'launcher_version': '7400000.1'}))
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()


class Debloat(TV):
    def test_simulacao_nao_muda_nada(self):
        self.ok('preflight.sh')
        r = self.ok('debloat.sh')
        self.assertIn('[simulação] pm disable-user --user 0 com.amazon.ceviche', r.stderr)
        self.assertEqual(self.mutations(), [])
        self.assert_back_to_initial()

    def test_exige_snapshot(self):
        r = self.run_script('debloat.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('preflight', r.stderr)
        self.assertEqual(self.mutations(), [])

    def test_sem_confirmacao_nao_aplica(self):
        self.ok('preflight.sh')
        r = self.run_script('debloat.sh', '--apply', inp='n\n')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_aplica_verifica_e_restaura(self):
        self.ok('preflight.sh')
        self.ok('debloat.sh', '--apply', '-y')
        self.assertEqual(self.state_of('com.amazon.ceviche'), 3)
        self.assertEqual(self.state_of('com.amazon.perfc'), 0)          # protegido
        self.assertEqual(self.state_of('com.android.nfc'), 2)           # do sistema
        self.assertEqual(self.state_of('com.amazon.aca'), 0)            # Alexa mantida
        for p in names('never-disable.txt'):
            self.assertEqual(self.state_of(p), 0, p)
        st = self.read()
        self.assertEqual(st['settings']['global']['window_animation_scale'], '0.5')
        self.assertEqual(st['settings']['global']['animator_duration_scale'], '1.0')
        self.assertEqual(st['settings']['secure']['amz_limit_ad_tracking'], '1')
        self.assertEqual(st['appops']['com.amazon.hedwig|RUN_ANY_IN_BACKGROUND'], 'ignore')
        self.assertEqual(st['boot_id'], '3')                             # svc + reboot
        self.ok('verify.sh')
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()
        self.assertNotIn('amz_limit_ad_tracking', self.read()['settings']['secure'])
        self.assert_no_forbidden()

    def test_idempotente(self):
        self.ok('preflight.sh')
        self.ok('debloat.sh', '--apply', '-y')
        lines = (self.report / 'journal.tsv').read_text()
        self.ok('debloat.sh', '--apply', '-y')
        self.assertEqual((self.report / 'journal.tsv').read_text(), lines)
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()

    def test_falha_de_saude_desfaz_sozinho(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s.update({'break_home': True}))
        r = self.run_script('debloat.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('desfeitas', r.stderr)
        self.assert_back_to_initial()

    def test_systemui_parado_depois_do_reinicio_desfaz(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s['base_running'].remove('com.android.systemui'))
        r = self.run_script('debloat.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('systemui não está rodando', r.stderr)
        self.assertIn('desfeitas', r.stderr)
        self.assert_back_to_initial()

    def test_tv_cai_no_meio_e_restore_recupera(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s.update({'offline_after': s['calls'] + 40}))
        r = self.run_script('debloat.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertGreater(len((self.report / 'journal.tsv').read_text().splitlines()), 0)
        self.tweak(lambda s: s.update({'offline_after': None}))
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()

    def test_trava_impede_execucao_simultanea(self):
        self.ok('preflight.sh')
        (self.report / '.lock').mkdir()
        r = self.run_script('debloat.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_servico_de_acessibilidade_e_pulado(self):
        self.ok('preflight.sh')
        def a11y(s):
            s['pkgs']['com.amazon.dp.logger']['a11y'] = True
            s['running'].append('com.amazon.dp.logger')
        self.tweak(a11y)
        r = self.ok('debloat.sh', '--apply', '-y')
        self.assertIn('PULADO (serviço de acessibilidade)', r.stdout)
        self.assertEqual(self.state_of('com.amazon.dp.logger'), 0)
        self.assertEqual(self.state_of('com.amazon.ceviche'), 3)
        self.assertEqual([c for c in self.mutations() if 'com.amazon.dp.logger' in c], [])

    def test_keep_apps(self):
        self.ok('preflight.sh')
        self.ok('debloat.sh', '--apply', '-y', conf='KEEP_APPS="com.amazon.sneakpeek"\n')
        self.assertEqual(self.state_of('com.amazon.sneakpeek'), 0)
        self.assertEqual(self.state_of('com.amazon.ceviche'), 3)

    def test_alexa_desligada(self):
        self.ok('preflight.sh', conf='ALEXA=0\n')
        self.ok('debloat.sh', '--apply', '-y')
        self.assertEqual(self.state_of('com.amazon.aca'), 3)
        self.assertEqual(self.read()['settings']['secure']['voice_disabled'], '1')
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()


class Guardrails(TV):
    def acmd(self, *cmd):
        script = (f'source "{SCRIPTS}/lib.sh"; SERIAL=fake-tv:5555; load_conf; APPLY=1; '
                  'acmd "$@"')
        e = {'PATH': os.environ['PATH'], 'ADB': str(FAKE), 'FAKE_TV_STATE': str(self.state),
             'FAKE_TV_LOG': str(self.log), 'CONF': str(self.conf), 'REPORT': str(self.report)}
        return subprocess.run(['bash', '-c', script, 'x', *cmd], env=e, capture_output=True, text=True)

    def test_comandos_bloqueados(self):
        blocked = [
            ['pm', 'uninstall', 'com.amazon.ceviche'],
            ['pm', 'disable-user', '--user', '0', 'com.amazon.tv.launcher'],
            ['pm', 'disable-user', '--user', '0', 'com.amazon.device.software.ota'],
            ['pm', 'disable-user', '--user', '0', 'com.netflix.ninja'],
            ['pm', 'disable-user', '--user', '0', 'com.amazon.aca'],      # Alexa mantida
            ['settings', 'put', 'global', 'adb_enabled', '0'],
            ['settings', 'put', 'global', 'animator_duration_scale', '0.5'],
            ['settings', 'put', 'system', 'window_animation_scale', '0.5'],
            ['appops', 'set', 'com.amazon.device.software.ota', 'RUN_ANY_IN_BACKGROUND', 'ignore'],
            ['appops', 'set', 'com.amazon.ceviche', 'CAMERA', 'ignore'],
            ['am', 'force-stop', 'com.amazon.tv.launcher'],
            ['rm', '-rf', '/sdcard'],
            ['reboot', 'recovery'],
            ['setprop', 'persist.sys.x', '1'],
        ]
        for cmd in blocked:
            r = self.acmd(*cmd)
            self.assertNotEqual(r.returncode, 0, f'deveria bloquear: {cmd}')
            self.assertIn('guardrail', r.stderr)
        self.assertEqual(self.commands(), [], 'algum comando bloqueado chegou à TV')

    def test_comando_permitido_passa(self):
        r = self.acmd('pm', 'disable-user', '--user', '0', 'com.amazon.ceviche')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.state_of('com.amazon.ceviche'), 3)

    def test_conf_nao_executa_codigo(self):
        pwned = self.tmp / 'pwned'
        for conf in (f'ALEXA=1; touch {pwned}\n', f'$(touch {pwned})\n', 'FOO=1\n', 'ALEXA=2\n',
                     'KEEP_APPS="com.amazon.erro.de.digitacao"\n'):
            r = self.run_script('preflight.sh', conf=conf)
            self.assertNotEqual(r.returncode, 0, conf)
        self.assertFalse(pwned.exists())


class Extras(TV):
    def test_lockdown_pula_uid_de_sistema_e_restaura(self):
        self.tweak(lambda s: s['pkgs']['com.amazon.device.crashmanager'].update({'uid': 1000}))
        self.initial = self.read()
        self.ok('preflight.sh')
        self.ok('lockdown.sh', '--apply', '-y')
        ops = self.read()['appops']
        self.assertEqual(ops['com.amazon.device.metrics|RUN_ANY_IN_BACKGROUND'], 'ignore')
        self.assertEqual(ops['com.amazon.ftvads.deeplinking|RUN_IN_BACKGROUND'], 'ignore')
        self.assertFalse(any(k.startswith('com.amazon.device.crashmanager') for k in ops))
        self.assertFalse(any('software.ota' in c for c in self.mutations()))
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()

    def test_cache(self):
        self.ok('cache.sh')
        self.assertNotIn('cache_trimmed', self.read())
        r = self.ok('cache.sh', '--apply', '-y')
        self.assertTrue(self.read()['cache_trimmed'])
        self.assertIn('2.4G', r.stderr)

    def test_medicao_compara(self):
        self.ok('preflight.sh')
        self.ok('measure.sh', 'antes')
        self.ok('debloat.sh', '--apply', '-y')
        r = self.ok('measure.sh', 'depois')
        self.assertIn('comparado com measure-antes', r.stdout)
        self.assertRegex(r.stderr, r'quadros lentos\s+-\d+\.\d pontos')        # menos processos
        depois = (self.report / sorted(
            f.name for f in self.report.glob('measure-depois-*.txt'))[0]).read_text()
        self.assertIn('carga_cpu=1.20 0.95 0.80', depois)
        self.assertIn('cpu_audio_pct=23', depois)
        self.assertRegex(depois, r'boot_s=\d+\n')                    # cronometrado no reinício
        antes = (self.report / sorted(
            f.name for f in self.report.glob('measure-antes-*.txt'))[0]).read_text()
        self.assertIn('boot_s=n/d', antes)                             # nenhum reinício ainda
        avg = depois.split('# memória média nas últimas 3 h (procstats)\n')[1].splitlines()
        self.assertEqual(avg[0], '614 MB  com.example.raro')          # 1,2 GB × 50%
        self.assertEqual(avg[1], '61 MB  init')                        # 60,5 MB arredondado
        self.assertEqual(len(avg), 5)
        self.assertRegex(r.stderr, r'ram disponível\s+\d{3} MB\n')
        self.assertEqual(self.mutations()[-1:], ['reboot'])              # medir não muda nada

    def test_all_simulacao_e_aplicacao(self):
        self.ok('all.sh')
        self.assertEqual(self.mutations(), [])
        self.ok('all.sh', '--apply', '-y')
        self.assertEqual(self.state_of('com.amazon.ceviche'), 3)


class Dns(TV):
    def dns(self):
        return self.read()['settings']['global'].get('private_dns_mode'), \
            self.read()['settings']['global'].get('private_dns_specifier')

    def test_listas_do_dns(self):
        must = [r[1] for r in listing('dns-check.txt') if r[0] == 'must']
        self.assertIn('softwareupdates.amazon.com', must)
        self.assertIn('updates.amazon.com', must)
        self.assertIn('device-messaging-na.amazon.com', must)       # o Prime Video depende dele
        ota = [r[1] for r in listing('dns-check.txt') if r[0] == 'ota']
        self.assertIn('dubri19p4y5b.cloudfront.net', ota)
        self.assertEqual({r[0] for r in listing('dns-check.txt')}, {'must', 'ota', 'probe'})
        keys = [r[1] for r in listing('settings.dns.txt')]
        self.assertEqual(sorted(keys), ['private_dns_mode', 'private_dns_specifier'])

    def test_simulacao_nao_muda_nada(self):
        self.ok('preflight.sh')
        r = self.ok('dns.sh')
        self.assertIn('[simulação] settings put global private_dns_mode hostname', r.stderr)
        self.assertEqual(self.mutations(), [])

    def test_liga_verifica_e_desliga(self):
        self.ok('preflight.sh')
        r = self.ok('dns.sh', '--apply', '-y')
        self.assertEqual(self.dns(), ('hostname', 'dns.adguard-dns.com'))
        self.assertIn('filtro ativo', r.stderr)
        self.assertIn('NÃO desligue a Depuração ADB', r.stderr)
        v = self.run_script('verify.sh')               # sem debloat: só a parte do DNS importa aqui
        self.assertIn('a TV resolve nomes', v.stdout)
        self.assertIn('mantenha a Depuração ADB LIGADA', v.stderr)
        self.ok('dns.sh', '--off', '--apply', '-y')
        self.assertEqual(self.dns(), (None, None))
        self.assert_back_to_initial()

    def test_servidor_fora_do_ar_desfaz_sozinho(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s['dot']['dns.adguard-dns.com'].update({'up': False}))
        r = self.run_script('dns.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('NÃO RESOLVE', r.stdout)
        self.assert_back_to_initial()
        self.assertEqual((self.report / 'journal.tsv').read_text(), '')

    def test_provedor_que_bloqueia_atualizacoes_e_recusado(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s['dot']['dns.adguard-dns.com']['blocks'].append('softwareupdates.amazon.com'))
        r = self.run_script('dns.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('softwareupdates.amazon.com', r.stdout)
        self.assertIn('BLOQUEADO', r.stdout)
        self.assert_back_to_initial()

    def test_falha_depois_do_reinicio_desfaz_sozinho(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s['dot']['dns.adguard-dns.com'].update({'down_after_reboot': True}))
        r = self.run_script('dns.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('depois do reinício', r.stderr)
        self.assertIn('svc power reboot', self.commands())
        self.assert_back_to_initial()
        self.assertEqual((self.report / 'journal.tsv').read_text(), '')

    def test_sem_reinicio_avisa(self):
        self.ok('preflight.sh')
        r = self.ok('dns.sh', '--apply', '-y', '--no-reboot')
        self.assertIn('checagem depois do reinício não foi feita', r.stderr)
        self.assertNotIn('svc power reboot', self.commands())

    def test_cdn_de_atualizacao_bloqueado_desfaz(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s['dot']['dns.adguard-dns.com']['blocks'].append('amzdigital-a.akamaihd.net'))
        r = self.run_script('dns.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('amzdigital-a.akamaihd.net', r.stdout)
        self.assert_back_to_initial()

    def test_cdn_aposentado_nao_trava(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s.update({'dead_hosts': ['amzdigitaldownloads.edgesuite.net']}))
        r = self.ok('dns.sh', '--apply', '-y')
        self.assertIn('amzdigitaldownloads.edgesuite.net não resolve nem antes; ignorado', r.stderr)
        self.assertEqual(self.dns(), ('hostname', 'dns.adguard-dns.com'))
        v = self.run_script('verify.sh')
        self.assertIn('CDNs de atualização sem resposta', v.stderr)

    def test_porta_853_inacessivel_nao_muda_nada(self):
        self.ok('preflight.sh')
        r = self.run_script('dns.sh', '--apply', '-y', env={'DUMBTV_DOT_PROBE': 'fail'})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('853', r.stderr)
        self.assertEqual(self.mutations(), [])

    def test_tv_sem_internet_nao_muda_nada(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s.update({'internet': False}))
        r = self.run_script('dns.sh', '--apply', '-y')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_servidor_invalido_e_recusado(self):
        self.ok('preflight.sh')
        for host in ('evil;reboot', 'dns..x', '$(id)', 'localhost'):
            r = self.run_script('dns.sh', f'--host={host}', '--apply', '-y')
            self.assertNotEqual(r.returncode, 0, host)
        self.assertNotEqual(self.run_script('dns.sh', conf='DNS_HOST=x;y\n').returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_servidor_personalizado_pelo_conf(self):
        self.ok('preflight.sh')
        self.tweak(lambda s: s['dot'].update({'abc123.dns.nextdns.io': {'up': True, 'blocks': []}}))
        r = self.ok('dns.sh', '--apply', '-y', conf='DNS_HOST=abc123.dns.nextdns.io\n')
        self.assertEqual(self.dns(), ('hostname', 'abc123.dns.nextdns.io'))
        self.assertIn('o filtro pode não estar ativo', r.stderr)

    def test_desligar_dns_preserva_o_debloat(self):
        self.ok('preflight.sh')
        self.ok('debloat.sh', '--apply', '-y')
        self.ok('dns.sh', '--apply', '-y')
        self.ok('dns.sh', '--off', '--apply', '-y')
        self.assertEqual(self.dns(), (None, None))
        self.assertEqual(self.state_of('com.amazon.ceviche'), 3)
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()

    def test_restore_desfaz_tudo_inclusive_o_dns(self):
        self.ok('preflight.sh')
        self.ok('debloat.sh', '--apply', '-y')
        self.ok('dns.sh', '--apply', '-y')
        self.ok('restore.sh', '--apply', '-y')
        self.assert_back_to_initial()

    def test_guardrail_do_dns(self):
        g = Guardrails('test_comando_permitido_passa')
        g.state, g.log, g.conf, g.report = self.state, self.log, self.conf, self.report
        for cmd in (['settings', 'put', 'global', 'private_dns_mode', 'strict'],
                    ['settings', 'put', 'global', 'private_dns_specifier', 'a;b'],
                    ['settings', 'put', 'global', 'http_proxy', '1.2.3.4:8080']):
            r = g.acmd(*cmd)
            self.assertNotEqual(r.returncode, 0, cmd)
        self.assertEqual(self.commands(), [])


if __name__ == '__main__':
    unittest.main()
