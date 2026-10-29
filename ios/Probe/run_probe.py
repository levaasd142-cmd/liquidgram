#!/usr/bin/env python3
"""Runs the transport probe on one iOS simulator runtime and collects everything it produced.

The app runs twice on a new simulator device: `-ProbePhase main` checks every capability over both origins and stores
markers in website storage, then a relaunch with `-ProbePhase verify` reads the markers back. The reports, the page
snapshots, simulator screenshots, the app's log and any crash report go to <out-dir>, with a `runner.json` summary.

Usage: run_probe.py <app-path> <runtime-version-prefix> <out-dir> <run-id>
  runtime-version-prefix  such as `26.2` or `18.`; the newest available iOS runtime that matches is used
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

BUNDLE_ID = 'org.liquidgram.probe'
PROCESS_NAME = 'LiquidgramProbe'
PHASES = ('main', 'verify')
PHASE_TIMEOUT_SECONDS = {'main': 900, 'verify': 420}
BOOT_TIMEOUT_SECONDS = 600
INSTALL_TIMEOUT_SECONDS = 300
LOG_TIMEOUT_SECONDS = 240
POLL_SECONDS = 3
# Lets WebKit's processes of the terminated app exit before the next launch
AFTER_TERMINATE_SECONDS = 5
PREFERRED_DEVICE_NAMES = ('iPhone 16', 'iPhone 17', 'iPhone 16 Pro', 'iPhone 15')
MAX_LOG_BYTES = 4 * 1024 * 1024


def run(args, timeout=120, check=True):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode != 0:
        raise RuntimeError(f'{" ".join(args)} exited with {result.returncode}: {result.stderr.strip()[:500]}')
    return result.stdout


def simctl(*args, timeout=120, check=True):
    return run(['xcrun', 'simctl', *args], timeout=timeout, check=check)


def parse_version(text):
    return tuple(int(part) for part in text.split('.') if part.isdigit())


def find_runtime(prefix):
    runtimes = json.loads(simctl('list', '-j', 'runtimes'))['runtimes']
    candidates = [
        runtime for runtime in runtimes
        if runtime.get('isAvailable')
        and (runtime.get('platform') == 'iOS' or runtime.get('name', '').startswith('iOS '))
        and runtime.get('version', '').startswith(prefix)
    ]
    if not candidates:
        available = ', '.join(runtime.get('name', '?') for runtime in runtimes)
        raise RuntimeError(f'No iOS runtime matches {prefix}; available: {available}')
    return max(candidates, key=lambda runtime: parse_version(runtime['version']))


def pick_device_type(runtime):
    iphones = [
        device_type for device_type in runtime.get('supportedDeviceTypes', [])
        if device_type.get('productFamily') == 'iPhone' or device_type.get('name', '').startswith('iPhone')
    ]
    if not iphones:
        raise RuntimeError(f'{runtime["name"]} supports no iPhone')
    for name in PREFERRED_DEVICE_NAMES:
        for device_type in iphones:
            if device_type['name'] == name:
                return device_type
    return iphones[0]


def is_running(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def run_phase(udid, phase, run_id, out_dir):
    started = time.time()
    output = simctl(
        'launch', '--terminate-running-process', udid, BUNDLE_ID, '-ProbePhase', phase, '-ProbeRunId', run_id,
    )
    # `simctl launch` prints `<bundle id>: <pid>`
    pid = int(output.strip().rsplit(':', 1)[-1])
    container = Path(simctl('get_app_container', udid, BUNDLE_ID, 'data').strip())
    phase_dir = container / 'Documents' / f'probe-{phase}'
    done_file = phase_dir / 'done.json'

    status = 'timeout'
    deadline = started + PHASE_TIMEOUT_SECONDS[phase]
    while time.time() < deadline:
        if done_file.exists():
            status = 'done'
            break
        if not is_running(pid):
            status = 'done' if done_file.exists() else 'exited'
            break
        time.sleep(POLL_SECONDS)

    simctl('io', udid, 'screenshot', str(out_dir / f'screen-{phase}.png'), check=False, timeout=60)
    simctl('terminate', udid, BUNDLE_ID, check=False)
    time.sleep(AFTER_TERMINATE_SECONDS)
    if phase_dir.exists():
        shutil.copytree(phase_dir, out_dir / f'probe-{phase}', dirs_exist_ok=True)
    return {'status': status, 'seconds': round(time.time() - started), 'pid': pid}


def save_logs(udid, out_dir):
    queries = {
        'app-log.txt': 'subsystem == "org.liquidgram.messenger"',
        'webkit-errors.txt': (
            f'(process == "{PROCESS_NAME}" OR process BEGINSWITH "com.apple.WebKit")'
            ' AND (messageType == error OR messageType == fault)'
        ),
    }
    for file_name, predicate in queries.items():
        try:
            text = simctl(
                'spawn', udid, 'log', 'show', '--style', 'compact', '--info', '--debug', '--last', '60m',
                '--predicate', predicate, timeout=LOG_TIMEOUT_SECONDS, check=False,
            )
        except subprocess.TimeoutExpired:
            text = 'log show timed out'
        (out_dir / file_name).write_text(text[-MAX_LOG_BYTES:])


def save_crash_reports(started, out_dir):
    reports_dir = Path.home() / 'Library' / 'Logs' / 'DiagnosticReports'
    if not reports_dir.is_dir():
        return []
    copied = []
    for report in reports_dir.iterdir():
        if report.name.startswith(PROCESS_NAME) and report.stat().st_mtime >= started:
            shutil.copy2(report, out_dir / report.name)
            copied.append(report.name)
    return copied


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    app_path, prefix, out_arg, run_id = sys.argv[1:]
    out_dir = Path(out_arg)
    out_dir.mkdir(parents=True, exist_ok=True)
    started = time.time()
    summary = {'runtimePrefix': prefix, 'runId': run_id, 'phases': {}}
    udid = None
    try:
        runtime = find_runtime(prefix)
        device_type = pick_device_type(runtime)
        summary.update({
            'runtime': runtime['name'],
            'runtimeVersion': runtime['version'],
            'runtimeBuild': runtime.get('buildversion'),
            'deviceType': device_type['name'],
        })
        udid = simctl('create', f'Probe {runtime["version"]}', device_type['identifier'], runtime['identifier']).strip()
        summary['udid'] = udid
        simctl('boot', udid)
        simctl('bootstatus', udid, '-b', timeout=BOOT_TIMEOUT_SECONDS)
        simctl('install', udid, app_path, timeout=INSTALL_TIMEOUT_SECONDS)
        for phase in PHASES:
            summary['phases'][phase] = run_phase(udid, phase, f'{run_id}-{prefix}', out_dir)
    except Exception as err:  # Each runtime reports its own failure, the next one still runs
        summary['error'] = f'{type(err).__name__}: {err}'
    finally:
        if udid:
            try:
                save_logs(udid, out_dir)
            except Exception as err:
                summary['logError'] = str(err)
            simctl('shutdown', udid, check=False, timeout=120)
            simctl('delete', udid, check=False, timeout=120)
        summary['crashReports'] = save_crash_reports(started, out_dir)
        summary['seconds'] = round(time.time() - started)
        (out_dir / 'runner.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
