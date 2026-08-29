#!/usr/bin/env node
// Works out the next version, writes it to package.json and prepends a
// CHANGELOG section. Used by the release workflow, but runnable locally with
// --dry-run to see exactly what it would do.
//
//   node scripts/prepare-release.mjs --bump patch
//   node scripts/prepare-release.mjs --version 2.0.0 --notes "..." --dry-run

import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : undefined;
};
const has = (name) => args.includes(`--${name}`);

const bump = flag('bump') ?? 'patch';
const explicit = flag('version');
const notesArg = flag('notes');
const dryRun = has('dry-run');

function main() {
const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const current = pkg.version;

function nextVersion() {
  if (explicit) {
    if (!/^\d+\.\d+\.\d+$/.test(explicit)) {
      throw new Error(`--version must be x.y.z, got "${explicit}"`);
    }
    return explicit;
  }
  const [major, minor, patch] = current.split('.').map(Number);
  switch (bump) {
    case 'major': return `${major + 1}.0.0`;
    case 'minor': return `${major}.${minor + 1}.0`;
    case 'patch': return `${major}.${minor}.${patch + 1}`;
    default: throw new Error(`--bump must be major, minor or patch, got "${bump}"`);
  }
}

const version = nextVersion();
if (version === current) throw new Error(`version ${version} is already released`);

/** Falls back to the commit subjects since the last tag when no notes are given. */
function resolveNotes() {
  if (notesArg && notesArg.trim()) return notesArg.trim();
  let range = '';
  try {
    const previous = execSync('git describe --tags --abbrev=0', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString().trim();
    range = `${previous}..HEAD`;
  } catch {
    // No tag yet: fall through and list everything.
  }
  const log = execSync(`git log ${range} --no-merges --format=%s`, { encoding: 'utf8' })
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    // Release commits are noise in their own changelog entry.
    .filter((l) => !/^chore: release /.test(l));
  return log.length ? log.map((l) => `- ${l}`).join('\n') : '- No user-visible changes.';
}

const notes = resolveNotes();
const changelog = readFileSync('CHANGELOG.md', 'utf8');
if (changelog.includes(`\n## ${version}\n`)) {
  throw new Error(`CHANGELOG.md already has a section for ${version}`);
}
const entry = `## ${version}\n\n${notes}\n`;
const updated = changelog.replace(/^# Changelog\n+/, `# Changelog\n\n${entry}\n`);
if (updated === changelog) throw new Error('CHANGELOG.md must start with "# Changelog"');

console.log(`current : ${current}`);
console.log(`next    : ${version}`);
console.log('--- changelog entry ---');
console.log(entry.trimEnd());
console.log('-----------------------');

if (dryRun) {
  console.log('dry run: nothing written');
} else {
  pkg.version = version;
  writeFileSync('package.json', `${JSON.stringify(pkg, null, 2)}\n`);
  writeFileSync('CHANGELOG.md', updated);
  console.log('wrote package.json and CHANGELOG.md');
}

// Hand the values to the workflow.
if (process.env.GITHUB_OUTPUT) {
  appendFileSync(process.env.GITHUB_OUTPUT, `version=${version}\n`);
  const delimiter = `NOTES_${Date.now()}`;
  appendFileSync(process.env.GITHUB_OUTPUT, `notes<<${delimiter}\n${notes}\n${delimiter}\n`);
}
}

try {
  main();
} catch (error) {
  // A stack trace here is noise; the message is the whole story.
  console.error(`prepare-release: ${error.message}`);
  process.exit(1);
}
