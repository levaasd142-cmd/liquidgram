// Helpers of `ios/run-ui-tests.sh` and the iOS workflow. Plain Node.js without dependencies.
//
//   node report.mjs pick-simulator [preferred-name] < simctl.json
//       Reads `xcrun simctl list -j devices available` and prints `<udid>\t<name>\t<runtime>` of an iPhone on the
//       newest iOS runtime: the preferred name, else an iPhone 17 Pro or 16 Pro, else the newest Pro, else any iPhone.
//   node report.mjs summarize --work <dir> --out <dir> [--device <name>] [--runtime <name>] [--build-failed]
//       Turns the result bundles' exports in the work folder into README.md, summary.md, summary.json, screenshots/,
//       ax/ and logs/ in the output folder.
//   node report.mjs annotate <summary.json>
//       Prints GitHub Actions annotations: a notice with the counts and an error per failed test.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TOOLS_DIR = path.dirname(fileURLToPath(import.meta.url));
const KNOWN_ISSUES_FILE = path.join(TOOLS_DIR, '..', 'known-issues.json');
const PASSES = ['migration', 'light', 'dark'];
const LOG_TAIL_LINES = 300;
const SCREENSHOT_MAX_SIZE = 1200;
const SCREENSHOT_DISPLAY_WIDTH = 260;
const MAX_MESSAGE_LENGTH = 1000;
const MAX_BUILD_ERRORS = 40;
// GitHub shows at most 10 error annotations per step
const MAX_ERROR_ANNOTATIONS = 10;
// Accessibility trees the tests attach; XCTest adds its own query descriptions, which only repeat the failures
const ACCESSIBILITY_TREE_PREFIX = 'ax-';
const PREFERRED_SIMULATORS = ['iPhone 17 Pro', 'iPhone 16 Pro'];
const IOS_RUNTIME_PATTERN = /SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$/;
const PRO_IPHONE_PATTERN = /^iPhone (\d+) Pro$/;
// `Test Case '-[LiquidgramUITests.CoreTests testDemoAccount]' passed (12.345 seconds).`
const LOG_RESULT_PATTERN = new RegExp(
  "^Test Case '-\\[(?:[\\w.]+\\.)?(\\w+) (\\w+)\\]' (passed|failed|skipped) \\((\\d+(?:\\.\\d+)?) seconds\\)",
);
// `/path/CoreTests.swift:42: error: -[LiquidgramUITests.CoreTests testDemoAccount] : message`
const LOG_FAILURE_PATTERN = /: error: -\[(?:[\w.]+\.)?(\w+) (\w+)\] : (.*)$/;
const BUILD_ERROR_PATTERN = /(^|[^a-z])(error|fatal error):|BUILD FAILED|TEST BUILD FAILED/;
const DURATION_PART_PATTERN = /(\d+(?:\.\d+)?)\s*(ms|h|m|s)\b/g;
const SECONDS_IN_UNIT = {
  ms: 0.001, s: 1, m: 60, h: 3600,
};

const [command, ...args] = process.argv.slice(2);

switch (command) {
  case 'pick-simulator':
    pickSimulator(args[0]);
    break;
  case 'summarize':
    summarize(parseOptions(args));
    break;
  case 'annotate':
    annotate(args[0]);
    break;
  default:
    process.stderr.write('Usage: report.mjs pick-simulator|summarize|annotate ...\n');
    process.exit(64);
}

function pickSimulator(preferredName) {
  const { devices } = JSON.parse(fs.readFileSync(0, 'utf8'));
  const runtimes = Object.entries(devices)
    .map(([runtime, list]) => ({ runtime, version: parseRuntimeVersion(runtime), list }))
    .filter(({ version, list }) => version && list.some(isUsableIPhone))
    .sort((a, b) => compareVersions(b.version, a.version));
  if (!runtimes.length) {
    process.stderr.write('No available iPhone simulator\n');
    process.exit(1);
  }

  const { version, list } = runtimes[0];
  const iPhones = list.filter(isUsableIPhone);
  const names = [preferredName, ...PREFERRED_SIMULATORS].filter(Boolean);
  const device = names.map((name) => iPhones.find((item) => item.name === name)).find(Boolean)
    || iPhones
      .filter((item) => PRO_IPHONE_PATTERN.test(item.name))
      .sort((a, b) => Number(b.name.match(PRO_IPHONE_PATTERN)[1]) - Number(a.name.match(PRO_IPHONE_PATTERN)[1]))[0]
    || iPhones[0];
  process.stdout.write(`${device.udid}\t${device.name}\tiOS ${version.join('.')}\n`);
}

function isUsableIPhone(device) {
  return device.isAvailable !== false && /^iPhone\b/.test(device.name);
}

function parseRuntimeVersion(runtime) {
  const match = runtime.match(IOS_RUNTIME_PATTERN);
  return match ? match.slice(1).filter((part) => part !== undefined).map(Number) : undefined;
}

function compareVersions(a, b) {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const difference = (a[i] || 0) - (b[i] || 0);
    if (difference) return difference;
  }
  return 0;
}

function parseOptions(list) {
  const options = {};
  for (let i = 0; i < list.length; i++) {
    const name = list[i].replace(/^--/, '');
    if (list[i + 1] === undefined || list[i + 1].startsWith('--')) {
      options[name] = true;
    } else {
      options[name] = list[++i];
    }
  }
  return options;
}

function summarize(options) {
  const workDir = path.resolve(options.work);
  const outDir = path.resolve(options.out);
  const knownIssues = readJson(KNOWN_ISSUES_FILE) || {};
  for (const folder of ['screenshots', 'ax', 'logs']) {
    fs.mkdirSync(path.join(outDir, folder), { recursive: true });
  }

  const tests = [];
  const screenshots = [];
  const selfTests = [];
  for (const pass of PASSES) {
    const passDir = path.join(workDir, pass);
    const logFile = path.join(workDir, `${pass}.log`);
    if (!fs.existsSync(passDir) && !fs.existsSync(logFile)) continue;

    const passTests = readTests(passDir, logFile).map((test) => ({ ...test, pass }));
    const attachments = exportAttachments(passDir, pass, outDir);
    screenshots.push(...attachments.screenshots);
    selfTests.push(...attachments.selfTests);
    tests.push(...passTests);
    copyTail(logFile, path.join(outDir, 'logs', `xcodebuild-${pass}.log`));
  }
  copyTail(path.join(workDir, 'build-for-testing.log'), path.join(outDir, 'logs', 'build-for-testing.log'));
  copyFile(path.join(workDir, 'app.log'), path.join(outDir, 'logs', 'app.log'));
  copyFile(path.join(workDir, 'simulator.txt'), path.join(outDir, 'logs', 'simulator.txt'));

  markKnownIssues(tests, selfTests, knownIssues);
  const buildErrors = options['build-failed'] ? readBuildErrors(path.join(workDir, 'build-for-testing.log')) : [];
  const counts = countResults(tests);
  const status = getStatus(options, tests, counts);
  const summary = {
    status,
    generatedAt: new Date().toISOString(),
    source: {
      branch: process.env.GITHUB_REF_NAME,
      commit: process.env.GITHUB_SHA,
      run: process.env.GITHUB_RUN_ID && process.env.GITHUB_SERVER_URL
        ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
        : undefined,
    },
    device: { name: options.device, runtime: options.runtime },
    counts,
    tests,
    selfTests,
    buildErrors,
    screenshots,
  };

  fs.writeFileSync(path.join(outDir, 'summary.json'), `${JSON.stringify(summary, undefined, 2)}\n`);
  const markdown = renderSummary(summary);
  fs.writeFileSync(path.join(outDir, 'summary.md'), markdown);
  fs.writeFileSync(path.join(outDir, 'README.md'), markdown + renderScreenshots(summary));
  process.stdout.write(`UI tests: ${describeCounts(counts)}; report in ${outDir}\n`);
}

function getStatus(options, tests, counts) {
  if (options['build-failed']) return 'build-failed';
  if (!tests.length) return 'no-results';
  return counts.failed ? 'failed' : 'passed';
}

// Test results of one pass, from `xcresulttool get test-results tests` or else from the xcodebuild output
function readTests(passDir, logFile) {
  const fromBundle = readBundleTests(path.join(passDir, 'tests.json'));
  const fromLog = readLogTests(logFile);
  const tests = fromBundle.length ? fromBundle : fromLog;
  const summaryFailures = readSummaryFailures(path.join(passDir, 'summary.json'));
  return tests.map((test) => {
    const logTest = fromLog.find((item) => item.name === test.name);
    const message = test.message || summaryFailures.get(test.name) || (logTest && logTest.message);
    return { ...test, message: message ? truncate(message) : undefined };
  });
}

function readBundleTests(file) {
  const json = readJson(file);
  if (!json || !Array.isArray(json.testNodes)) return [];

  const tests = [];
  const visit = (node, suite) => {
    if (node.nodeType === 'Test Case') {
      const failures = collectFailureMessages(node);
      tests.push({
        name: normalizeTestName(node.nodeIdentifier || `${suite}/${node.name}`),
        status: normalizeStatus(node.result),
        duration: node.durationInSeconds ?? parseDuration(node.duration),
        message: failures.length ? failures.join(' | ') : undefined,
      });
      return;
    }
    const nextSuite = node.nodeType === 'Test Suite' ? node.name : suite;
    (node.children || []).forEach((child) => visit(child, nextSuite));
  };
  json.testNodes.forEach((node) => visit(node, ''));
  return tests;
}

function collectFailureMessages(node) {
  const messages = [];
  const visit = (child) => {
    if (child.nodeType === 'Failure Message' && child.name) messages.push(child.name);
    (child.children || []).forEach(visit);
  };
  (node.children || []).forEach(visit);
  return messages;
}

function readSummaryFailures(file) {
  const failures = new Map();
  const json = readJson(file);
  (json && Array.isArray(json.testFailures) ? json.testFailures : []).forEach((failure) => {
    const name = normalizeTestName(failure.testIdentifierString || failure.testName || '');
    if (name && failure.failureText) {
      failures.set(name, failures.has(name) ? `${failures.get(name)} | ${failure.failureText}` : failure.failureText);
    }
  });
  return failures;
}

function readLogTests(file) {
  if (!fs.existsSync(file)) return [];

  const tests = [];
  const messages = new Map();
  fs.readFileSync(file, 'utf8').split('\n').forEach((line) => {
    const failure = line.match(LOG_FAILURE_PATTERN);
    if (failure) {
      const name = `${failure[1]}/${failure[2]}`;
      messages.set(name, messages.has(name) ? `${messages.get(name)} | ${failure[3]}` : failure[3]);
      return;
    }
    const result = line.match(LOG_RESULT_PATTERN);
    if (result) {
      tests.push({ name: `${result[1]}/${result[2]}`, status: result[3], duration: Number(result[4]) });
    }
  });
  return tests.map((test) => ({ ...test, message: messages.get(test.name) }));
}

// `CoreTests/testDemoAccount()` and `LiquidgramUITests/CoreTests/testDemoAccount` become `CoreTests/testDemoAccount`
function normalizeTestName(identifier) {
  const parts = identifier.replace(/\(\)$/, '').split('/').filter(Boolean);
  return parts.slice(-2).join('/');
}

function normalizeStatus(result) {
  switch (result) {
    case 'Passed':
      return 'passed';
    case 'Failed':
      return 'failed';
    case 'Skipped':
      return 'skipped';
    case 'Expected Failure':
      return 'expected failure';
    default:
      return String(result || 'unknown').toLowerCase();
  }
}

function parseDuration(text) {
  if (typeof text !== 'string') return undefined;

  let seconds = 0;
  let hasPart = false;
  for (const [, value, unit] of text.matchAll(DURATION_PART_PATTERN)) {
    seconds += Number(value) * SECONDS_IN_UNIT[unit];
    hasPart = true;
  }
  return hasPart ? seconds : undefined;
}

// Copies the screenshots, accessibility trees and self-test reports of `xcresulttool export attachments`
function exportAttachments(passDir, pass, outDir) {
  const result = { screenshots: [], selfTests: [] };
  const attachmentsDir = path.join(passDir, 'attachments');
  const manifest = readJson(path.join(attachmentsDir, 'manifest.json'));
  if (!Array.isArray(manifest)) return result;

  const usedNames = new Set();
  manifest.forEach((entry) => {
    const test = normalizeTestName(entry.testIdentifier || entry.testIdentifierURL || 'unknown');
    const attachments = [...(entry.attachments || [])].sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
    attachments.forEach((attachment) => {
      const source = path.join(attachmentsDir, attachment.exportedFileName || '');
      if (!attachment.exportedFileName || !fs.existsSync(source)) return;

      const extension = path.extname(attachment.exportedFileName).toLowerCase();
      const name = getAttachmentName(attachment);
      const baseName = makeUniqueName(`${test.replace('/', '-')}-${name}`, usedNames);
      if (['.png', '.jpg', '.jpeg', '.heic'].includes(extension)) {
        const file = `screenshots/${baseName}.png`;
        saveScreenshot(source, path.join(outDir, file));
        result.screenshots.push({
          test, pass, name, file, isFailure: Boolean(attachment.isAssociatedWithFailure),
        });
      } else if (name.startsWith('selftest-report')) {
        const file = `logs/${baseName}.json`;
        fs.copyFileSync(source, path.join(outDir, file));
        const report = readJson(source);
        if (report) result.selfTests.push({ test, pass, file, ...report });
      } else if (name.startsWith(ACCESSIBILITY_TREE_PREFIX)) {
        fs.copyFileSync(source, path.join(outDir, 'ax', `${baseName}.txt`));
      }
    });
  });
  return result;
}

// `suggestedHumanReadableName` is `<attachment name>_<index>_<UUID>.<extension>`
function getAttachmentName(attachment) {
  const readable = attachment.suggestedHumanReadableName || attachment.name || attachment.exportedFileName;
  return readable
    .replace(/\.[a-z0-9]+$/i, '')
    .replace(/_\d+_[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i, '')
    .replace(/[^\w.-]+/g, '-');
}

function makeUniqueName(name, usedNames) {
  let candidate = name;
  for (let index = 2; usedNames.has(candidate); index++) {
    candidate = `${name}-${index}`;
  }
  usedNames.add(candidate);
  return candidate;
}

// Downscales screenshots with `sips` on macOS, so the report stays small and readable; elsewhere they are copied
function saveScreenshot(source, destination) {
  if (process.platform !== 'darwin') {
    fs.copyFileSync(source, destination);
    return;
  }
  try {
    execFileSync('sips', ['-s', 'format', 'png', '-Z', String(SCREENSHOT_MAX_SIZE), source, '--out', destination], {
      stdio: 'ignore',
    });
  } catch (err) {
    fs.copyFileSync(source, destination);
  }
}

function markKnownIssues(tests, selfTests, knownIssues) {
  const knownChecks = knownIssues.selfTestChecks || {};
  const knownTests = knownIssues.tests || {};
  selfTests.forEach((report) => {
    (report.checks || []).forEach((check) => {
      if (!check.ok && knownChecks[check.name]) check.knownIssue = knownChecks[check.name];
    });
  });
  tests.forEach((test) => {
    if (test.status !== 'failed') return;

    if (knownTests[test.name]) {
      test.knownIssue = knownTests[test.name];
      return;
    }
    const report = selfTests.find((item) => item.test === test.name && item.pass === test.pass);
    const failedChecks = report ? (report.checks || []).filter((check) => !check.ok) : [];
    if (failedChecks.length && failedChecks.every((check) => check.knownIssue)) {
      test.knownIssue = failedChecks.map((check) => `${check.name}: ${check.knownIssue}`).join('; ');
    }
  });
}

function countResults(tests) {
  const counts = {
    total: tests.length, passed: 0, failed: 0, skipped: 0, knownIssues: 0,
  };
  tests.forEach((test) => {
    if (test.status === 'passed' || test.status === 'expected failure') counts.passed++;
    else if (test.status === 'skipped') counts.skipped++;
    else counts.failed++;
    if (test.knownIssue) counts.knownIssues++;
  });
  return counts;
}

function describeCounts(counts) {
  const known = counts.knownIssues ? ` (${counts.knownIssues} known)` : '';
  return `${counts.passed} passed, ${counts.failed} failed${known}, ${counts.skipped} skipped`;
}

function readBuildErrors(file) {
  if (!fs.existsSync(file)) return [];

  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const errors = lines.filter((line) => BUILD_ERROR_PATTERN.test(line));
  return (errors.length ? errors : lines.slice(-MAX_BUILD_ERRORS)).slice(0, MAX_BUILD_ERRORS).map(truncate);
}

function renderSummary(summary) {
  const { counts, device, source } = summary;
  const lines = [
    '# Liquidgram UI tests',
    '',
    `**${formatStatus(summary.status)}**: ${describeCounts(counts)}.`,
    '',
    `- Device: ${device.name || 'unknown'}${device.runtime ? `, ${device.runtime}` : ''}`,
  ];
  if (source.branch) {
    const commit = source.commit ? ` at \`${source.commit.slice(0, 7)}\`` : '';
    lines.push(`- Branch: \`${source.branch}\`${commit}`);
  }
  if (source.run) lines.push(`- Run: ${source.run}`);
  lines.push(`- Generated: ${summary.generatedAt}`, '');

  if (summary.buildErrors.length) {
    lines.push('## Build errors', '', '```', ...summary.buildErrors, '```', '');
  }

  if (summary.tests.length) {
    lines.push('## Tests', '', '| Test | Pass | Status | Duration | Failure |', '| --- | --- | --- | --- | --- |');
    summary.tests.forEach((test) => {
      const status = test.knownIssue ? `${test.status}, known issue` : test.status;
      const failure = [test.message, test.knownIssue && `Known issue: ${test.knownIssue}`].filter(Boolean).join('<br>');
      const cells = [
        `\`${test.name}\``, test.pass, formatStatus(status), formatDuration(test.duration), escapeCell(failure),
      ];
      lines.push(`| ${cells.join(' | ')} |`);
    });
    lines.push('');
  }

  summary.selfTests.forEach((report) => {
    lines.push(`## Self-test (${report.pass})`, '', '| Check | Result | Detail |', '| --- | --- | --- |');
    (report.checks || []).forEach((check) => {
      const result = check.ok ? 'ok' : (check.knownIssue ? 'failed, known issue' : '**failed**');
      const detail = [check.detail, check.knownIssue && `Known issue: ${check.knownIssue}`]
        .filter(Boolean)
        .join('<br>');
      lines.push(`| \`${check.name}\` | ${result} | ${escapeCell(detail)} |`);
    });
    if (report.info) {
      lines.push('', '<details><summary>Page details</summary>', '');
      lines.push('```json', JSON.stringify(report.info, undefined, 2), '```', '', '</details>');
    }
    if (report.error) lines.push('', `The self-test script failed: ${escapeCell(report.error)}`);
    lines.push('');
  });

  lines.push(
    'Folders: [`screenshots/`](screenshots), [`ax/`](ax) (accessibility trees the tests attached), [`logs/`](logs) '
      + '(app log, xcodebuild output, self-test reports).',
    '',
  );
  return lines.join('\n');
}

function renderScreenshots(summary) {
  if (!summary.screenshots.length) return '';

  const lines = ['', '## Screenshots', ''];
  const groups = new Map();
  summary.screenshots.forEach((screenshot) => {
    const key = `${screenshot.test} (${screenshot.pass})`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(screenshot);
  });
  groups.forEach((list, key) => {
    lines.push(`### \`${key}\``, '');
    lines.push(list.map((item) => (
      `<img src="${item.file}" width="${SCREENSHOT_DISPLAY_WIDTH}" alt="${item.name}" title="${item.name}">`
    )).join('\n'));
    lines.push('', list.map((item) => `[${item.name}](${item.file})`).join(' · '), '');
  });
  return `${lines.join('\n')}\n`;
}

function annotate(summaryFile) {
  const summary = readJson(summaryFile);
  if (!summary) {
    process.stdout.write('::warning title=UI tests::No summary.json, so the tests did not run or crashed\n');
    return;
  }

  const { name: deviceName, runtime } = summary.device || {};
  const device = [deviceName, runtime].filter(Boolean).join(', ');
  process.stdout.write(`::notice title=UI tests ${escapeProperty(formatStatus(summary.status))}::`
    + `${escapeData(`${describeCounts(summary.counts)} on ${device || 'the simulator'}`)}\n`);
  if (summary.buildErrors && summary.buildErrors.length) {
    process.stdout.write(`::error title=UI tests did not build::${escapeData(summary.buildErrors.join('\n'))}\n`);
  }
  const failedTests = (summary.tests || []).filter((test) => test.status === 'failed');
  const annotatedTests = failedTests.length > MAX_ERROR_ANNOTATIONS
    ? failedTests.slice(0, MAX_ERROR_ANNOTATIONS - 1)
    : failedTests;
  annotatedTests.forEach((test) => {
    const known = test.knownIssue ? ` (known issue: ${test.knownIssue})` : '';
    const title = `${test.name} (${test.pass})`;
    const message = `${test.message || 'Failed'}${known}`;
    process.stdout.write(`::error title=${escapeProperty(title)}::${escapeData(message)}\n`);
  });
  const hiddenTests = failedTests.slice(annotatedTests.length);
  if (hiddenTests.length) {
    const names = hiddenTests.map((test) => `${test.name} (${test.pass})`).join(', ');
    const title = `${hiddenTests.length} more failed tests`;
    process.stdout.write(`::error title=${escapeProperty(title)}::${escapeData(`${names}; see the report`)}\n`);
  }
}

function formatStatus(status) {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function formatDuration(seconds) {
  return typeof seconds === 'number' ? `${seconds.toFixed(1)} s` : '';
}

function escapeCell(text) {
  return String(text || '').replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
}

function escapeData(text) {
  return String(text).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
}

function escapeProperty(text) {
  return escapeData(text).replace(/:/g, '%3A').replace(/,/g, '%2C');
}

function truncate(text) {
  const value = String(text);
  return value.length > MAX_MESSAGE_LENGTH ? `${value.slice(0, MAX_MESSAGE_LENGTH)}…` : value;
}

function copyTail(source, destination) {
  if (!fs.existsSync(source)) return;

  const lines = fs.readFileSync(source, 'utf8').split('\n');
  fs.writeFileSync(destination, lines.slice(-LOG_TAIL_LINES).join('\n'));
}

function copyFile(source, destination) {
  if (fs.existsSync(source)) fs.copyFileSync(source, destination);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    return undefined;
  }
}
