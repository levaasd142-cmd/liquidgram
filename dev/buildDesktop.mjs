// Builds the Liquidgram desktop app from the production web build in `dist`: the Windows launcher
// with its installer and portable zip, and the Linux launcher. Requires Go and NSIS (`makensis`).
import { zipSync } from 'fflate';
import { execFileSync } from 'node:child_process';
import {
  cpSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DESKTOP_DIR = join(ROOT, 'desktop');
const LAUNCHER_DIR = join(DESKTOP_DIR, 'launcher');
const EMBED_DIR = join(LAUNCHER_DIR, 'webapp');
const INSTALLER_SCRIPT = join(DESKTOP_DIR, 'installer', 'liquidgram.nsi');
const PORTABLE_README = join(DESKTOP_DIR, 'portable', 'README.txt');
// Source maps only add weight, and the PHP helper shipped with the emoji images is never requested
const EXCLUDED_SUFFIXES = ['.map', '.php'];
const GO = process.env.GO || 'go';
const MAKENSIS = process.env.MAKENSIS || 'makensis';
const WINDOWS_EXE = 'Liquidgram.exe';
const LINUX_BINARY = 'liquidgram-linux-x64';
const INSTALLER = 'Liquidgram-Setup.exe';
const PORTABLE_ZIP = 'Liquidgram-Portable.zip';
const ZIP_LEVEL = 9;
const MEGABYTE = 1024 * 1024;
const BYTE_ORDER_MARK = String.fromCodePoint(0xFEFF);
const GO_HINT = 'Go 1.24 or newer is required, see go.dev/dl';
const NSIS_HINT = 'NSIS is required for the installer: install it with `apt-get install nsis`, '
  + '`brew install makensis` or from nsis.sourceforge.io, or pass --no-installer';

const { values: options } = parseArgs({
  options: {
    dist: { type: 'string', default: 'dist' },
    out: { type: 'string', default: 'dist-desktop' },
    'no-installer': { type: 'boolean', default: false },
  },
});

buildDesktop();

function buildDesktop() {
  const distDir = resolve(ROOT, options.dist);
  const outDir = resolve(ROOT, options.out);
  const version = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8')).version;
  const shouldBuildInstaller = !options['no-installer'];

  if (!existsSync(join(distDir, 'index.html'))) {
    throw new Error(`No web build in ${distDir}: run \`npm run build:production\` first`);
  }
  checkTool(GO, ['version'], GO_HINT);
  if (shouldBuildInstaller) {
    checkTool(MAKENSIS, ['-VERSION'], NSIS_HINT);
  }

  copyWebBuild(distDir);
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });

  runGo(['vet', './...']);
  runGo(['vet', './...'], { GOOS: 'windows' });
  runGo(['test', './...']);

  const windowsVersion = toWindowsVersion(version);
  runGo(['tool', 'go-winres', 'make', '--in', join('winres', 'winres.json'), '--arch', 'amd64', '--out', 'rsrc',
    '--product-version', windowsVersion, '--file-version', windowsVersion]);

  const exePath = join(outDir, WINDOWS_EXE);
  buildLauncher({
    goos: 'windows', goarch: 'amd64', version, outPath: exePath, extraLdflags: ['-H=windowsgui'],
  });
  buildLauncher({
    goos: 'linux', goarch: 'amd64', version, outPath: join(outDir, LINUX_BINARY),
  });

  packPortableZip(exePath, join(outDir, PORTABLE_ZIP));
  if (shouldBuildInstaller) {
    buildInstaller({
      version, windowsVersion, exePath, outPath: join(outDir, INSTALLER),
    });
  }

  printSummary(outDir, version);
}

function checkTool(command, args, hint) {
  try {
    execFileSync(command, args, { stdio: 'ignore' });
  } catch {
    throw new Error(hint);
  }
}

function copyWebBuild(distDir) {
  rmSync(EMBED_DIR, { recursive: true, force: true });
  cpSync(distDir, EMBED_DIR, {
    recursive: true,
    filter: (path) => !EXCLUDED_SUFFIXES.some((suffix) => path.endsWith(suffix)),
  });
}

function runGo(args, env = {}) {
  execFileSync(GO, args, {
    cwd: LAUNCHER_DIR,
    stdio: 'inherit',
    env: { ...process.env, CGO_ENABLED: '0', ...env },
  });
}

function buildLauncher({
  goos, goarch, version, outPath, extraLdflags = [],
}) {
  const ldflags = [...extraLdflags, '-s', '-w', `-X main.version=${version}`].join(' ');
  runGo(['build', '-trimpath', '-buildvcs=false', '-ldflags', ldflags, '-o', outPath, '.'], {
    GOOS: goos,
    GOARCH: goarch,
  });
}

// Windows version resources take exactly four numbers, so pre-release and build suffixes are dropped
function toWindowsVersion(version) {
  const parts = version.split(/[-+]/)[0].split('.').map(Number);
  while (parts.length < 4) parts.push(0);
  return parts.slice(0, 4).join('.');
}

function packPortableZip(exePath, outPath) {
  // Notepad on older Windows needs a byte order mark and CRLF line breaks to show the text properly
  const readme = `${BYTE_ORDER_MARK}${readFileSync(PORTABLE_README, 'utf8').replace(/\r?\n/g, '\r\n')}`;
  const zip = zipSync({
    [WINDOWS_EXE]: readFileSync(exePath),
    'README.txt': new TextEncoder().encode(readme),
  }, { level: ZIP_LEVEL });
  writeFileSync(outPath, zip);
}

function buildInstaller({
  version, windowsVersion, exePath, outPath,
}) {
  execFileSync(MAKENSIS, [
    '-V2',
    '-INPUTCHARSET', 'UTF8',
    `-DVERSION=${version}`,
    `-DVERSION_WIN=${windowsVersion}`,
    `-DAPP_EXE_PATH=${exePath}`,
    `-DOUT_FILE=${outPath}`,
    INSTALLER_SCRIPT,
  ], { stdio: 'inherit' });
}

function printSummary(outDir, version) {
  const files = [WINDOWS_EXE, LINUX_BINARY, PORTABLE_ZIP, INSTALLER].filter((name) => existsSync(join(outDir, name)));
  const lines = files.map((name) => {
    const size = (statSync(join(outDir, name)).size / MEGABYTE).toFixed(1);
    return `  ${name} (${size} MB)`;
  });

  // eslint-disable-next-line no-console
  console.log(`Liquidgram desktop ${version} is ready in ${relative(ROOT, outDir) || '.'}:\n${lines.join('\n')}`);
}
