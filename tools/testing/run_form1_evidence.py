"""Compare identical Form 1 probes on #80 and candidate, loose and packed.

Runs the actual engine, retains raw diagnostics (including expected baseline
failures), and gates required art instead of accepting a missing-art fallback.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from run_godot_tests import run

BASE = '38839dc2bcc9c0a892740cb6deeec90322a91d24'
SCRIPTS = ('form1_animation_capture.gd', 'form1_resource_probe.gd',
           'form1_animation_runtime_test.gd', 'rebirth_gameplay_capture.gd')
EXPECTED_BEFORE = [
    'windup/strike/recovery preserve committed facing',
    'windup/strike/recovery preserve committed facing',
    'stopping during frame zero resets gait clock',
]


def expected_regression(result, log, expected):
    prefix = 'ERROR: [FORM1 ANIMATION RUNTIME] '
    actual = [line.strip().split(prefix, 1)[1] for line in log.splitlines() if prefix in line]
    return (result['exit_code'] == 1 and not result['timed_out']
            and result['engine_errors'] == len(expected) and actual == expected)


def validate_trace(trace, before):
    samples = trace['samples']
    if trace['failures'] != 0 or len(samples) != 157:
        raise RuntimeError('Incomplete animation capture')
    by_name = {x['name']: x for x in samples}
    if len(by_name) != 157:
        raise RuntimeError('Duplicate capture names')
    for direction in ('front', 'back', 'side-l', 'side-r'):
        walk = {'front': 'down', 'back': 'up', 'side-l': 'left', 'side-r': 'right'}[direction]
        for frame in range(6):
            s = by_name[f'walk-{direction}-{frame:02d}']
            assert s['source'] == 'canon_walk/' + walk and s['frame'] == frame and not s['shader']
        for action, name in ((3, 'windup'), (1, 'slash'), (2, 'rslash'), (4, 'heavy'), (5, 'recover')):
            for frame in range(8 if action == 4 else 6):
                s = by_name[f'attack-{direction}-{action}-{frame:02d}']
                assert s['source'] == f'approved/{name}_{direction}' and s['frame'] == frame
                assert s['approved'] and not s['shader']
    for name in ('continuity-1-strike', 'continuity-2-recovery'):
        assert by_name[name]['committed_facing'] == ([1, 0] if before else [0, 1])
    assert by_name['gait-0-stop']['walk_clock'] == (0.07 if before else 0)
    assert by_name['gait-1-restart']['frame'] == (1 if before else 0)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--headless-only', action='store_true', help='Local preflight; not graphical evidence')
    a = parser.parse_args()
    a.godot, a.before, a.after, out = (p.resolve() for p in (a.godot, a.before, a.after, a.output))
    out.mkdir(parents=True, exist_ok=False)
    manifest = {'status': 'INCOMPLETE', 'graphical': not a.headless_only, 'runs': [], 'packs': {}}
    env = os.environ.copy()
    original_cwd = Path.cwd()
    try:
        version, log = run(a.godot, ['--version'], out, 'version', 30, env)
        manifest['godot'] = log.strip()
        if version['result'] != 'PASS' or log.strip() != '4.3.stable.official.77dcf97d8':
            raise RuntimeError('Expected official Godot 4.3 stable')
        before_sha = subprocess.check_output(['git', '-C', str(a.before), 'rev-parse', 'HEAD'], text=True).strip()
        if before_sha != BASE:
            raise RuntimeError('Before checkout is not the audited #80 commit')
        manifest['before_commit'] = before_sha
        manifest['after_commit'] = subprocess.check_output(['git', '-C', str(a.after), 'rev-parse', 'HEAD'], text=True).strip()
        # Compare every existing Form 1 source asset, including both lineages.
        art = sorted((a.after / 'sprites/mollosar').rglob('form1*.png'))
        manifest['art_sha256'] = {str(p.relative_to(a.after)): sha(p) for p in art}
        if any(sha(a.before / rel) != value for rel, value in manifest['art_sha256'].items()):
            raise RuntimeError('Form 1 artwork changed')
        manifest['probe_sha256'] = {s: sha(a.after / 'scripts' / s) for s in SCRIPTS}
        for script in SCRIPTS:
            shutil.copyfile(a.after / 'scripts' / script, a.before / 'scripts' / script)
        for phase, project in [('before', a.before), ('after', a.after)]:
            lane = out / phase
            lane.mkdir()
            for key in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME'):
                directory = lane / 'userdata' / key
                directory.mkdir(parents=True)
                env[key] = str(directory)

            def invoke(name, args, timeout=180, expected=None):
                result, log = run(a.godot, args, lane, name, timeout, env)
                result['phase'] = phase
                if expected is not None:
                    accepted = expected_regression(result, log, expected)
                    result['expectation_matched'] = accepted
                else:
                    accepted = result['result'] == 'PASS'
                manifest['runs'].append(result)
                if not accepted:
                    raise RuntimeError(f'Unexpected result: {phase}/{name}')
                return log

            if os.name == 'nt':
                # Godot 4.3's Windows packtmp rename can fail in hosted runners.
                # Scope direct saves to disposable editor settings, never the
                # user's editor or game save files. Export errors still fail.
                settings = Path(env['APPDATA']) / 'Godot' / 'editor_settings-4.3.tres'
                settings.parent.mkdir(parents=True, exist_ok=True)
                settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
                    'filesystem/on_save/safe_save_on_backup_then_rename = false\n', encoding='utf-8')
                manifest['windows_export_direct_save'] = True
            invoke('import', ['--headless', '--path', project, '--import'], 600)
            pack = lane / 'form1.pck'
            invoke('export', ['--headless', '--path', project, '--export-pack', 'Windows', pack], 600)
            manifest['packs'][phase] = {'sha256': sha(pack), 'bytes': pack.stat().st_size}
            with tempfile.TemporaryDirectory(prefix='rebirth isolated pack ') as empty:
                for mode in ('source', 'packed'):
                    os.chdir(project if mode == 'source' else empty)
                    args = ['--path', project] if mode == 'source' else ['--path', empty, '--main-pack', pack]
                    report = lane / f'{mode}-resources.json'
                    invoke(mode + '-resources', ['--headless', *args, '--script', 'res://scripts/form1_resource_probe.gd', '--', mode, report])
                    resource_report = json.loads(report.read_text())
                    if resource_report['failures'] != 0 or resource_report['clips'] != 20:
                        raise RuntimeError('Required resource proof incomplete')
                    regression_log = invoke(mode + '-regressions', ['--headless', *args, '--script', 'res://scripts/form1_animation_runtime_test.gd'],
                           expected=EXPECTED_BEFORE if phase == 'before' else None)
                    marker = '[FORM1 ANIMATION RUNTIME] ' + ('FAIL' if phase == 'before' else 'PASS') + ' 943 checks'
                    if marker not in regression_log:
                        raise RuntimeError('Complete 943-check regression marker missing')
                    if not a.headless_only:
                        frames = lane / (mode + '-frames')
                        frames.mkdir()
                        log = invoke(mode + '-animation', [*args, '--audio-driver', 'Dummy', '--resolution', '512x512',
                                     '--fixed-fps', '60', '--script', 'res://scripts/form1_animation_capture.gd', '--', frames], 300)
                        if 'FORM1_ANIMATION_CAPTURE_COMPLETE frames=157 failures=0' not in log:
                            raise RuntimeError('Animation completion marker missing')
                        validate_trace(json.loads((frames / 'animation-trace.json').read_text()), phase == 'before')
                        if len(list(frames.glob('*.png'))) != 157:
                            raise RuntimeError('PNG roster incomplete')
                        # Real title -> New Game -> move -> sword, also in pack isolation.
                        gameplay = lane / (mode + '-gameplay')
                        gameplay.mkdir()
                        log = invoke(mode + '-gameplay', [*args, '--audio-driver', 'Dummy', '--resolution', '1280x720',
                                     '--fixed-fps', '60', '--script', 'res://scripts/rebirth_gameplay_capture.gd', '--', gameplay])
                        if 'REBIRTH_CAPTURE_COMPLETE' not in log or len(list(gameplay.glob('*.png'))) != 27:
                            raise RuntimeError('Gameplay completion evidence missing')
            os.chdir(original_cwd)
        # Fault injection: export without the manifest, retaining all textures.
        # Prove the delivery test rejects this pack. Restore the preset verbatim.
        phase = 'after'
        project = a.after
        lane = out / phase
        preset = project / 'export_presets.cfg'
        original = preset.read_bytes()
        missing_pack = lane / 'missing-manifest.pck'
        try:
            preset.write_bytes(original.replace(b'exclude_filter=""', b'exclude_filter="sprites/mollosar/approved/*.json"'))
            invoke('missing-manifest-export', ['--headless', '--path', project, '--export-pack', 'Windows', missing_pack], 600)
        finally:
            preset.write_bytes(original)
        with tempfile.TemporaryDirectory(prefix='rebirth missing manifest ') as empty:
            os.chdir(empty)
            invoke('missing-manifest-regression', ['--headless', '--path', empty, '--main-pack', missing_pack,
                   '--script', 'res://scripts/form1_animation_runtime_test.gd'], expected=['required approved set missing or rejected'])
        manifest['negative_gate_verified'] = True
        manifest['status'] = 'PASS'
        return 0
    except Exception as exc:
        manifest['status'] = 'FAIL'
        manifest['error'] = str(exc)
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        os.chdir(original_cwd)
        manifest['evidence_sha256'] = {str(p.relative_to(out)): sha(p) for p in out.rglob('*')
            if p.is_file() and 'userdata' not in p.parts and p.suffix != '.pck' and p.name != 'manifest.json'}
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        print('Form 1 evidence:', manifest['status'], out)


if __name__ == '__main__':
    sys.exit(main())
