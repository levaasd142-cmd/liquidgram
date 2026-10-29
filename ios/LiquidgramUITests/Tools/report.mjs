// Helpers of `ios/run-ui-tests.sh` and the iOS workflow. Plain Node.js without dependencies.
//
//   node report.mjs pick-simulator [preferred-name] < simctl.json
//       Reads `xcrun simctl list -j devices available` and prints `<udid>\t<name>\t<runtime>` of an iPhone on the
//       newest iOS runtime: the preferred name, else an iPhone 17 Pro or 16 Pro, else the newest Pro, else any iPhone.
//   node report.mjs summarize --work <dir> --out <dir> [--device <name>] [--runtime <name>] [--build-failed]
//       Turns the result bundles' exports in the work folder into README.md, summary.md, summary.json,
//       contact-sheet.png, screenshots/, ax/ and logs/ in the output folder.
//   node report.mjs annotate <summary.json>
//       Prints GitHub Actions annotations: a notice with the counts and an error per failed test.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';

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
// All screenshots on one image, in the order of the report, with the test and the step under each one
const CONTACT_SHEET_FILE = 'contact-sheet.png';
const SHEET_COLUMNS = 7;
// The screen of an iPhone 17 Pro, 402x874 pt, scaled down
const THUMB_WIDTH = 180;
const THUMB_HEIGHT = 392;
const SHEET_MARGIN = 12;
const TILE_GAP = 10;
// A band above each screenshot: green for a passed test, red for a failed one, orange for the failure's screenshot
const BAND_HEIGHT = 5;
const CAPTION_LINES = 2;
const CAPTION_LINE_HEIGHT = 10;
const CAPTION_PADDING = 4;
const TITLE_SCALE = 2;
const SHEET_COLORS = {
  background: [255, 255, 255],
  text: [34, 34, 34],
  passed: [46, 160, 67],
  failed: [218, 54, 51],
  failureScreenshot: [255, 153, 0],
  frame: [208, 215, 222],
  missing: [235, 235, 235],
};
// A 5x7 pixel font: each glyph of FONT_CHARS is 7 rows in FONT_CODES, each row a base-32 digit whose 5 bits are its
// pixels from left to right. Other characters are drawn as a box.
const FONT_CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz -_.,:/()[]#\'+=?!%><*';
const FONT_CODES = 'ehjlphe4c4444eeh1248vv2421he26aiv22vgu11he68guhhev124888ehhehheehhf12cehhvhhhuhhuhhuehggghesihhhisvgguggvvggugggehgnhhfhhhvhhhe44444e72222ichikokihggggggvhrllhhhhhpljhhehhhhheuhhugggehhhliduhhukihfgge11uv444444hhhhhhehhhhha4hhhlllahha4ahhhha4444v1248gv00e1fhfggmphhu00egghe11djhhf00ehvge698s8880fhhf1eggmphhh40c444e20622icggikokic44444e00qllhh00mphhh00ehhhe00uhugg00djf1100mpggg00ege1u88s889600hhhjd00hhha400hhlla00ha4ah00hhf1e00v248v0000000000v000000000v00000cc0000c480cc0cc001248g024888428422248e88888ee22222eaavavaac480000044v44000v0v00eh124044444404op248j38421248248g84204lel40';
const GLYPH_WIDTH = 5;
const GLYPH_HEIGHT = 7;
const GLYPH_ADVANCE = 6;
const MISSING_GLYPH = 'vhhhhhv';
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
// Channels of the PNG color types: gray, RGB, palette, gray with alpha, RGBA
const PNG_CHANNELS = {
  0: 1, 2: 3, 3: 1, 4: 2, 6: 4,
};
const PNG_COLOR_TYPE_RGB = 2;
const PNG_FILTER_SUB = 1;
const CRC_TABLE = makeCrcTable();

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

  summary.contactSheet = writeContactSheet(summary, outDir);
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
    'Folders: [`screenshots/`](screenshots), [`ax/`](ax) (accessibility trees of failed tests), [`logs/`](logs) '
      + '(app log, xcodebuild output, self-test reports).',
    '',
  );
  return lines.join('\n');
}

function renderScreenshots(summary) {
  if (!summary.screenshots.length) return '';

  const lines = ['', '## Screenshots', ''];
  if (summary.contactSheet) {
    lines.push(
      'All screenshots at a glance, with a band for the test\'s result: green passed, red failed, orange the moment of '
        + 'the failure.',
      '',
      `<img src="${summary.contactSheet}" alt="Contact sheet of all screenshots">`,
      '',
    );
  }
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

// Draws every screenshot of the report on one PNG and returns its file name, or undefined without screenshots
function writeContactSheet(summary, outDir) {
  const { screenshots } = summary;
  if (!screenshots.length) return undefined;

  const statuses = new Map(summary.tests.map((test) => [`${test.name} ${test.pass}`, test.status]));
  const tileWidth = THUMB_WIDTH + 2;
  const tileHeight = BAND_HEIGHT + THUMB_HEIGHT + 2 + CAPTION_PADDING + CAPTION_LINES * CAPTION_LINE_HEIGHT;
  const titleHeight = GLYPH_HEIGHT * TITLE_SCALE + SHEET_MARGIN;
  const columns = Math.min(SHEET_COLUMNS, screenshots.length);
  const rows = Math.ceil(screenshots.length / SHEET_COLUMNS);
  const width = SHEET_MARGIN * 2 + columns * tileWidth + (columns - 1) * TILE_GAP;
  const height = SHEET_MARGIN * 2 + titleHeight + rows * tileHeight + (rows - 1) * TILE_GAP;
  const canvas = createCanvas(width, height, SHEET_COLORS.background);
  drawText(canvas, SHEET_MARGIN, SHEET_MARGIN, `Liquidgram UI tests: ${describeCounts(summary.counts)}`,
    SHEET_COLORS.text, TITLE_SCALE);

  const captionChars = Math.floor(tileWidth / GLYPH_ADVANCE);
  screenshots.forEach((screenshot, index) => {
    const x = SHEET_MARGIN + (index % SHEET_COLUMNS) * (tileWidth + TILE_GAP);
    const y = SHEET_MARGIN + titleHeight + Math.floor(index / SHEET_COLUMNS) * (tileHeight + TILE_GAP);
    const status = statuses.get(`${screenshot.test} ${screenshot.pass}`);
    const bandColor = screenshot.isFailure || screenshot.name.startsWith('failure-')
      ? SHEET_COLORS.failureScreenshot
      : (status === 'failed' ? SHEET_COLORS.failed : SHEET_COLORS.passed);
    fillRect(canvas, x, y, tileWidth, BAND_HEIGHT, bandColor);
    const frameY = y + BAND_HEIGHT;
    fillRect(canvas, x, frameY, tileWidth, THUMB_HEIGHT + 2, SHEET_COLORS.frame);
    const image = readPng(path.join(outDir, screenshot.file));
    if (image) {
      drawImageFitted(canvas, image, x + 1, frameY + 1, THUMB_WIDTH, THUMB_HEIGHT);
    } else {
      fillRect(canvas, x + 1, frameY + 1, THUMB_WIDTH, THUMB_HEIGHT, SHEET_COLORS.missing);
    }
    const captionY = frameY + THUMB_HEIGHT + 2 + CAPTION_PADDING;
    const [testClass, testName] = screenshot.test.split('/');
    const testCaption = `${testClass}/${testName}`.length <= captionChars ? `${testClass}/${testName}` : testName;
    drawText(canvas, x, captionY, truncateText(testCaption || screenshot.test, captionChars), SHEET_COLORS.text);
    drawText(canvas, x, captionY + CAPTION_LINE_HEIGHT, truncateText(screenshot.name, captionChars),
      SHEET_COLORS.text);
  });

  writePng(path.join(outDir, CONTACT_SHEET_FILE), canvas);
  return CONTACT_SHEET_FILE;
}

function truncateText(text, maxLength) {
  return text.length > maxLength ? `${text.slice(0, maxLength - 2)}..` : text;
}

function createCanvas(width, height, color) {
  const pixels = Buffer.alloc(width * height * 3);
  for (let i = 0; i < pixels.length; i += 3) {
    [pixels[i], pixels[i + 1], pixels[i + 2]] = color;
  }
  return { width, height, pixels };
}

function fillRect(canvas, left, top, width, height, color) {
  for (let y = Math.max(0, top); y < Math.min(canvas.height, top + height); y++) {
    for (let x = Math.max(0, left); x < Math.min(canvas.width, left + width); x++) {
      const offset = (y * canvas.width + x) * 3;
      [canvas.pixels[offset], canvas.pixels[offset + 1], canvas.pixels[offset + 2]] = color;
    }
  }
}

function drawText(canvas, left, top, text, color, scale = 1) {
  Array.from(text).forEach((char, index) => {
    const glyphIndex = FONT_CHARS.indexOf(char);
    const rows = glyphIndex === -1
      ? MISSING_GLYPH
      : FONT_CODES.slice(glyphIndex * GLYPH_HEIGHT, (glyphIndex + 1) * GLYPH_HEIGHT);
    Array.from(rows).forEach((digit, row) => {
      const bits = parseInt(digit, 32);
      for (let column = 0; column < GLYPH_WIDTH; column++) {
        if (bits & (1 << (GLYPH_WIDTH - 1 - column))) {
          fillRect(canvas, left + (index * GLYPH_ADVANCE + column) * scale, top + row * scale, scale, scale, color);
        }
      }
    });
  });
}

// Scales the image down into the box with an area average, keeping its aspect ratio, centered on white
function drawImageFitted(canvas, image, left, top, boxWidth, boxHeight) {
  const scale = Math.min(boxWidth / image.width, boxHeight / image.height, 1);
  const width = Math.max(1, Math.round(image.width * scale));
  const height = Math.max(1, Math.round(image.height * scale));
  const offsetX = left + Math.floor((boxWidth - width) / 2);
  const offsetY = top + Math.floor((boxHeight - height) / 2);
  fillRect(canvas, left, top, boxWidth, boxHeight, SHEET_COLORS.background);
  for (let y = 0; y < height; y++) {
    const sourceTop = Math.floor((y * image.height) / height);
    const sourceBottom = Math.max(sourceTop + 1, Math.floor(((y + 1) * image.height) / height));
    for (let x = 0; x < width; x++) {
      const sourceLeft = Math.floor((x * image.width) / width);
      const sourceRight = Math.max(sourceLeft + 1, Math.floor(((x + 1) * image.width) / width));
      const sum = [0, 0, 0];
      let count = 0;
      for (let sourceY = sourceTop; sourceY < sourceBottom; sourceY++) {
        for (let sourceX = sourceLeft; sourceX < sourceRight; sourceX++) {
          const offset = (sourceY * image.width + sourceX) * 4;
          const alpha = image.pixels[offset + 3] / 255;
          for (let channel = 0; channel < 3; channel++) {
            sum[channel] += image.pixels[offset + channel] * alpha + 255 * (1 - alpha);
          }
          count++;
        }
      }
      const offset = ((offsetY + y) * canvas.width + offsetX + x) * 3;
      for (let channel = 0; channel < 3; channel++) {
        canvas.pixels[offset + channel] = Math.round(sum[channel] / count);
      }
    }
  }
}

// Decodes a non-interlaced PNG with 8 or 16 bits per channel into RGBA; undefined for anything else
function readPng(file) {
  let data;
  try {
    data = fs.readFileSync(file);
  } catch (err) {
    return undefined;
  }
  if (data.length < PNG_SIGNATURE.length || !data.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
    return undefined;
  }

  let header;
  let palette;
  let paletteAlpha;
  const parts = [];
  for (let offset = PNG_SIGNATURE.length; offset + 8 <= data.length;) {
    const length = data.readUInt32BE(offset);
    const type = data.toString('latin1', offset + 4, offset + 8);
    const body = data.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      header = {
        width: body.readUInt32BE(0),
        height: body.readUInt32BE(4),
        bitDepth: body[8],
        colorType: body[9],
        interlace: body[12],
      };
    } else if (type === 'PLTE') {
      palette = body;
    } else if (type === 'tRNS') {
      paletteAlpha = body;
    } else if (type === 'IDAT') {
      parts.push(body);
    } else if (type === 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  const channels = header && PNG_CHANNELS[header.colorType];
  if (!channels || header.interlace || ![8, 16].includes(header.bitDepth)
    || (header.colorType === 3 && (!palette || header.bitDepth !== 8))) {
    return undefined;
  }

  let raw;
  try {
    raw = zlib.inflateSync(Buffer.concat(parts));
  } catch (err) {
    return undefined;
  }
  const bytesPerSample = header.bitDepth / 8;
  const bytesPerPixel = channels * bytesPerSample;
  const stride = header.width * bytesPerPixel;
  if (raw.length < (stride + 1) * header.height) return undefined;

  const pixels = Buffer.alloc(header.width * header.height * 4);
  let previous = Buffer.alloc(stride);
  for (let y = 0; y < header.height; y++) {
    const start = y * (stride + 1);
    const line = Buffer.from(raw.subarray(start + 1, start + 1 + stride));
    unfilterLine(raw[start], line, previous, bytesPerPixel);
    for (let x = 0; x < header.width; x++) {
      const samples = [];
      for (let channel = 0; channel < channels; channel++) {
        samples.push(line[x * bytesPerPixel + channel * bytesPerSample]);
      }
      const rgba = toRgba(header.colorType, samples, palette, paletteAlpha);
      rgba.forEach((value, channel) => {
        pixels[(y * header.width + x) * 4 + channel] = value;
      });
    }
    previous = line;
  }
  return { width: header.width, height: header.height, pixels };
}

function unfilterLine(filter, line, previous, bytesPerPixel) {
  for (let i = 0; i < line.length; i++) {
    const left = i >= bytesPerPixel ? line[i - bytesPerPixel] : 0;
    const up = previous[i];
    const upLeft = i >= bytesPerPixel ? previous[i - bytesPerPixel] : 0;
    let predictor = 0;
    if (filter === 1) {
      predictor = left;
    } else if (filter === 2) {
      predictor = up;
    } else if (filter === 3) {
      predictor = Math.floor((left + up) / 2);
    } else if (filter === 4) {
      const estimate = left + up - upLeft;
      const distances = [Math.abs(estimate - left), Math.abs(estimate - up), Math.abs(estimate - upLeft)];
      predictor = distances[0] <= distances[1] && distances[0] <= distances[2]
        ? left
        : (distances[1] <= distances[2] ? up : upLeft);
    }
    line[i] = (line[i] + predictor) & 0xff;
  }
}

function toRgba(colorType, samples, palette, paletteAlpha) {
  switch (colorType) {
    case 0:
      return [samples[0], samples[0], samples[0], 255];
    case 2:
      return [samples[0], samples[1], samples[2], 255];
    case 3: {
      const index = samples[0];
      const alpha = paletteAlpha && index < paletteAlpha.length ? paletteAlpha[index] : 255;
      return [palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2], alpha];
    }
    case 4:
      return [samples[0], samples[0], samples[0], samples[1]];
    default:
      return [samples[0], samples[1], samples[2], samples[3]];
  }
}

// Encodes the canvas as an 8-bit RGB PNG, every line with the Sub filter
function writePng(file, canvas) {
  const stride = canvas.width * 3;
  const raw = Buffer.alloc((stride + 1) * canvas.height);
  for (let y = 0; y < canvas.height; y++) {
    const start = y * (stride + 1);
    raw[start] = PNG_FILTER_SUB;
    for (let i = 0; i < stride; i++) {
      const value = canvas.pixels[y * stride + i];
      const left = i >= 3 ? canvas.pixels[y * stride + i - 3] : 0;
      raw[start + 1 + i] = (value - left) & 0xff;
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(canvas.width, 0);
  header.writeUInt32BE(canvas.height, 4);
  header[8] = 8;
  header[9] = PNG_COLOR_TYPE_RGB;
  fs.writeFileSync(file, Buffer.concat([
    PNG_SIGNATURE,
    makePngChunk('IHDR', header),
    makePngChunk('IDAT', zlib.deflateSync(raw)),
    makePngChunk('IEND', Buffer.alloc(0)),
  ]));
}

function makePngChunk(type, body) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(body.length);
  const typeAndBody = Buffer.concat([Buffer.from(type, 'latin1'), body]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(computeCrc(typeAndBody));
  return Buffer.concat([length, typeAndBody, crc]);
}

function computeCrc(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function makeCrcTable() {
  return Array.from({ length: 256 }, (_, index) => {
    let value = index;
    for (let bit = 0; bit < 8; bit++) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    return value >>> 0;
  });
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
