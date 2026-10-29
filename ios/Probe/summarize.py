#!/usr/bin/env python3
"""Summarizes the probe results of every runtime in <results-dir> as summary.json and summary.md, and prints one
GitHub annotation per runtime, so the outcome is readable without downloading anything.

Usage: summarize.py <results-dir>
"""
import json
import sys
from pathlib import Path

ORIGINS = ('custom', 'http')
PHASES = ('main', 'verify')
INFO_PREFIX = 'info-'
MAX_DETAIL_LENGTH = 300


def load_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def collect_checks(runtime_dir):
    """Maps `scenario/check` to the result of each origin"""
    checks = {}
    for phase in PHASES:
        report = load_json(runtime_dir / f'probe-{phase}' / 'report.json')
        if not report:
            continue
        for scenario in report['scenarios']:
            prefix = scenario['name']
            if scenario['status'] != 'done':
                key = f'{prefix}/scenario-status'
                checks.setdefault(key, {})[scenario['origin']] = {'ok': False, 'detail': scenario['status']}
            for check in scenario['checks']:
                key = f'{prefix}/{check["name"]}'
                checks.setdefault(key, {})[scenario['origin']] = {
                    'ok': check['ok'], 'detail': check['detail'][:MAX_DETAIL_LENGTH],
                }
    return checks


def mark(result):
    if result is None:
        return '-'
    return 'pass' if result['ok'] else 'FAIL'


def escape_annotation(text):
    return text.replace('%', '%25').replace('\r', '').replace('\n', '%0A')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    results_dir = Path(sys.argv[1])
    summary = {}
    lines = ['# Transport probe', '']
    for runtime_dir in sorted(path for path in results_dir.iterdir() if path.is_dir()):
        runner = load_json(runtime_dir / 'runner.json') or {}
        checks = collect_checks(runtime_dir)
        title = f'{runner.get("runtime", runtime_dir.name)} ({runner.get("deviceType", "?")})'
        summary[runtime_dir.name] = {'runner': runner, 'checks': checks}

        regressions = []
        both_failing = []
        http_only_failures = []
        counts = {origin: [0, 0] for origin in ORIGINS}
        for key, results in sorted(checks.items()):
            for origin in ORIGINS:
                if origin in results:
                    counts[origin][1] += 1
                    counts[origin][0] += results[origin]['ok']
            custom = results.get('custom')
            http = results.get('http')
            if key.split('/', 1)[1].startswith(INFO_PREFIX):
                continue
            if custom and not custom['ok'] and http and http['ok']:
                regressions.append(f'{key}: {custom["detail"]}')
            elif custom and not custom['ok']:
                both_failing.append(f'{key}: {custom["detail"]}')
            elif http and not http['ok']:
                http_only_failures.append(f'{key}: {http["detail"]}')

        phases = ', '.join(f'{phase} {info.get("status")}' for phase, info in runner.get('phases', {}).items())
        header = (
            f'{title}: {phases or "not run"}{" error " + runner["error"] if runner.get("error") else ""}. '
            f'custom scheme {counts["custom"][0]}/{counts["custom"][1]} pass, '
            f'loopback {counts["http"][0]}/{counts["http"][1]} pass'
        )
        lines += [f'## {title}', '', header, '', '| Check | Custom scheme | Loopback | Detail (custom) |', '| --- | --- | --- | --- |']
        for key, results in sorted(checks.items()):
            detail = (results.get('custom') or results.get('http') or {}).get('detail', '').replace('|', '/')
            lines.append(f'| {key} | {mark(results.get("custom"))} | {mark(results.get("http"))} | {detail[:120]} |')
        lines.append('')

        message = [header]
        message += ['Fails only over the custom scheme:'] + (regressions or ['none'])
        message += ['Fails over the custom scheme and the loopback server:'] + (both_failing or ['none'])
        message += ['Fails only over the loopback server:'] + (http_only_failures or ['none'])
        compact = ' '.join(
            f'{key}={mark(results.get("custom"))[0]}{mark(results.get("http"))[0]}'
            for key, results in sorted(checks.items())
        )
        message += ['All (custom, loopback; p = pass, F = fail):', compact]
        level = 'warning' if regressions or runner.get('error') or not checks else 'notice'
        print(f'::{level} title=Transport probe {title}::{escape_annotation(chr(10).join(message))}')

    (results_dir / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (results_dir / 'summary.md').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
