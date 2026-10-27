#!/usr/bin/env -S python3 -I
"""adb simulado: imita um Fire TV Stick 3ª geração (AFTSSS, Fire OS 7.7.1.7).

Lê e grava o estado da TV em FAKE_TV_STATE (JSON) e registra cada comando
`shell` em FAKE_TV_LOG, para os testes verem exatamente o que os scripts fariam.
Nenhuma TV de verdade é tocada.
"""
import json
import os
import sys
from pathlib import Path

LAUNCHER = 'com.amazon.tv.launcher/.ui.HomeActivity'
state_path = Path(os.environ['FAKE_TV_STATE'])
log_path = Path(os.environ['FAKE_TV_LOG'])
st = json.loads(state_path.read_text())
args = sys.argv[1:]


def save():
    state_path.write_text(json.dumps(st, indent=1, sort_keys=True))


def out(*lines):
    for line in lines:
        print(line)


def offline():
    lim = st.get('offline_after')
    return lim is not None and st['calls'] >= lim


def reboot():
    st['boot_id'] = str(int(st['boot_id']) + 1)
    enabled = {p for p, i in st['pkgs'].items() if i['state'] in (0, 1)}
    st['running'] = [p for p in st['base_running'] if p in enabled or '.' not in p
                     or p not in st['pkgs']]
    st['front'] = 'com.example.broken/.Main' if st.get('break_home') else LAUNCHER
    for srv in st.get('dot', {}).values():            # servidor que falha só depois do boot
        if srv.get('down_after_reboot'):
            srv['up'] = False


def resolve(host):
    """Resolução de nomes: rede normal, ou o servidor DNS-over-TLS configurado."""
    if not st.get('internet', True):
        return None
    if host in st.get('dead_hosts', []):              # domínio que deixou de existir
        return None
    g = st['settings'].get('global', {})
    if g.get('private_dns_mode') == 'hostname':
        srv = st.get('dot', {}).get(g.get('private_dns_specifier'))
        if not srv or not srv.get('up'):
            return None
        if host in srv.get('blocks', []):
            return '0.0.0.0'
    return '93.184.216.34'


# --- comandos fora do shell ---------------------------------------------------
if args == ['start-server'] or args[:1] in (['connect'], ['disconnect']):
    sys.exit(0)
if args == ['devices']:
    out('List of devices attached', 'fake-tv:5555\tdevice')
    sys.exit(0)
if args[-1:] == ['get-state']:
    out('offline' if offline() else 'device')
    sys.exit(0)
if len(args) < 3 or args[0] != '-s' or args[2] != 'shell':
    print(f'fake adb: comando não simulado: {args}', file=sys.stderr)
    sys.exit(91)

cmd = ' '.join(args[3:])
with log_path.open('a') as f:
    f.write(cmd + '\n')
st['calls'] += 1
if offline():
    save()
    print('error: device offline', file=sys.stderr)
    sys.exit(1)

w = cmd.split()
pkgs = st['pkgs']
rc = 0

if w[:1] == ['echo']:
    out(' '.join(w[1:]))
elif w[:1] == ['getprop']:
    out(st['props'].get(w[1], ''))
elif w[:2] == ['pm', 'path']:
    if w[2] in pkgs:
        out(f'package:/system/priv-app/{w[2]}/{w[2]}.apk')
elif w[:3] == ['pm', 'list', 'packages']:
    for p in sorted(pkgs):
        if '-d' in w and pkgs[p]['state'] not in (2, 3):
            continue
        out(f'package:{p}')
elif w[:2] == ['pm', 'disable-user'] and w[2:4] == ['--user', '0'] and len(w) == 5:
    p = w[4]
    if p not in pkgs:
        out(f'Error: Unknown package: {p}')
    elif pkgs[p].get('protected'):
        out(f'Error: java.lang.SecurityException: Cannot disable a protected package: {p}')
    elif pkgs[p]['state'] == 2:
        out(f'Error: java.lang.SecurityException: Shell cannot change component state for {p} to 3')
    else:
        pkgs[p]['state'] = 3
        if p not in st['sticky']:
            st['running'] = [r for r in st['running'] if r != p]
        out(f'Package {p} new state: disabled-user')
elif w[:2] == ['pm', 'enable'] and w[2:4] == ['--user', '0'] and len(w) == 5:
    p = w[4]
    if p in pkgs:
        pkgs[p]['state'] = 0
        out(f'Package {p} new state: enabled')
elif w[:2] == ['pm', 'trim-caches']:
    st['cache_trimmed'] = True
elif w[:2] == ['pm', 'uninstall']:
    pkgs.pop(w[-1], None)          # dano real: os testes exigem que isso nunca aconteça
    out('Success')
elif w[:2] == ['dumpsys', 'package']:
    p = w[2]
    if p in pkgs:
        i = pkgs[p]
        ver = st['launcher_version'] if p == 'com.amazon.tv.launcher' else '1.0'
        out(f'  Package [{p}] (abc123):', f'    userId={i["uid"]}', f'    versionName={ver}',
            f'    User 0: ceDataInode=1 installed=true hidden=false suspended=false '
            f'stopped=false notLaunched=false enabled={i["state"]}')
        if i.get('a11y'):
            out('  Service Resolver Table:', '    Non-Data Actions:',
                '      android.accessibilityservice.AccessibilityService:',
                f'        abc123 {p}/.ScreenReaderService filter def456')
elif w[:3] == ['dumpsys', 'activity', 'activities']:
    out(f'  ResumedActivity: ActivityRecord{{1a2b u0 {st["front"]} t5}}')
elif w == ['dumpsys', 'activity', 'services', 'com.android.systemui']:
    out('ACTIVITY MANAGER SERVICES (dumpsys activity services)', '  User 0 active services:')
    if 'com.android.systemui' in st['running']:       # hospedado em device.services, como no AFTSSS
        out('  * ServiceRecord{291548c u0 com.android.systemui/.SystemUIService}',
            '    intent={cmp=com.android.systemui/.SystemUIService}',
            '    app=ProcessRecord{c58d1cb 834:com.amazon.device.services/1000}')
elif w[:2] == ['dumpsys', 'meminfo']:
    out('Total PSS by process:')
    for n, p in enumerate(st['running']):
        out(f'    {90000 - n * 1000:,}K: {p} (pid {1000 + n})')
    out('', 'Free RAM: 300,000K')
elif w[:1] == ['settings'] and len(w) >= 3:
    ns = st['settings'].setdefault(w[2], {})
    if w[1] == 'get':
        out(ns.get(w[3], 'null'))
    elif w[1] == 'put' and len(w) == 5:
        ns[w[3]] = w[4]
    elif w[1] == 'delete':
        out(f'Deleted {1 if ns.pop(w[3], None) is not None else 0} rows')
    elif w[1] == 'list':
        out(*[f'{k}={v}' for k, v in sorted(ns.items())])
elif w[:2] == ['appops', 'get']:
    mode = st['appops'].get(f'{w[2]}|{w[3]}')
    out(f'{w[3]}: {mode}; time=+1m' if mode else 'No operations.')
elif w[:2] == ['appops', 'set']:
    key = f'{w[2]}|{w[3]}'
    if w[4] == 'default':
        st['appops'].pop(key, None)
    else:
        st['appops'][key] = w[4]
elif w[:2] == ['am', 'force-stop']:
    st['running'] = [r for r in st['running'] if r != w[2]]
elif w[:2] == ['am', 'start'] and 'android.intent.category.HOME' in w:
    st['front'] = 'com.example.broken/.Main' if st.get('break_home') else LAUNCHER
    for srv in st.get('dot', {}).values():            # servidor que falha só depois do boot
        if srv.get('down_after_reboot'):
            srv['up'] = False
elif w[:3] == ['ps', '-A', '-o']:
    out('NAME', *st['running'])
elif w[:1] == ['pidof']:
    # O SystemUI não tem processo próprio no Fire OS: pidof volta vazio.
    if w[1] in st['running'] and w[1] != 'com.android.systemui':
        out(str(1000 + st['running'].index(w[1])))
elif w == ['cat', '/proc/meminfo']:
    freed = sum(12 for p, i in pkgs.items() if i['state'] == 3)
    out('MemTotal:         999000 kB', 'MemFree:          100000 kB',
        f'MemAvailable:     {(300 + freed) * 1024} kB')
elif w == ['cat', '/proc/loadavg']:                  # bloqueado ao shell no Fire OS 7
    print('cat: /proc/loadavg: Permission denied', file=sys.stderr)
    rc = 1
elif w == ['uptime']:
    out(' 12:25:05 up 30 min,  0 users,  load average: 1.20, 0.95, 0.80')
elif w == ['cat', '/proc/uptime']:
    out('1800.50 3000.10')
elif w[:2] == ['dumpsys', 'gfxinfo']:
    n = len(st['running'])                            # menos processos, menos quadros lentos
    out(f'** Graphics info for pid 1234 [{w[2]}] **', '', 'Stats since: 123456789ns',
        'Total frames rendered: 1000', f'Janky frames: {n * 10} ({n:.2f}%)')
elif w == ['dumpsys', 'procstats', '--hours', '3']:   # formato e vírgula decimal do AFTSSS
    out('AGGREGATED OVER LAST 3 HOURS:')
    for n, p in enumerate(st['running']):
        out(f'  * {p} / u0a{n} / v1:',
            f'           TOTAL: 100% (40MB-{60 - n},5MB-70MB/1,7MB-2MB-3MB/40MB-80MB-90MB over 11)')
    out('  * com.example.raro / u0a99 / v1:',
        '           TOTAL: 50% (900KB-1,2GB-1,3GB/1MB-1MB-1MB/1MB-1MB-1MB over 2)')
elif w == ['dumpsys', 'cpuinfo']:
    out('Load: 1.20 / 0.95 / 0.80',
        'CPU usage from 334544ms to 187394ms ago:',
        '  23% 315/fireos.hardware.audio@2.0-service: 23% user + 0.1% kernel / faults: 12 minor',
        '  10% 527/system_server: 7.7% user + 3.2% kernel / faults: 137 minor')
elif w == ['logcat', '-d', '-b', 'events']:
    if st.get('boot_events', True):                   # o buffer gira: some horas depois do boot
        out('10-27 12:00:31.100   527   560 I boot_progress_enable_screen: 31100')
elif w == ['cat', '/proc/sys/kernel/random/boot_id']:
    out(st['boot_id'])
elif w[:2] == ['df', '-h']:
    free = '2.4G' if st.get('cache_trimmed') else '1.9G'
    out('Filesystem      Size  Used Avail Use% Mounted on',
        f'/dev/block/dm-1 5.2G  3.3G {free}  63% /data')
elif w in (['svc', 'power', 'reboot'], ['reboot']):
    reboot()
elif w[:1] == ['ping']:
    host = w[-1]
    ip = resolve(host)
    if ip:
        out(f'PING {host} ({ip}) 56(84) bytes of data.')
    else:
        print(f'ping: unknown host {host}', file=sys.stderr)
        rc = 2
else:
    print(f'/system/bin/sh: {w[0] if w else ""}: inaccessible or not found', file=sys.stderr)
    rc = 127

save()
sys.exit(rc)
