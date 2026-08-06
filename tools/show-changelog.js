#!/usr/bin/env node
// Renders CHANGELOG.md to a page the launcher opens once after an update.
//
// Prints the path of the page to stdout when there is something to show, and
// nothing otherwise, so the launcher can decide with a simple test.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = process.env.ICLOUD_APP_ROOT || path.join(__dirname, '..');
const PROFILE = process.env.ICLOUD_APP_PROFILE
    || path.join(os.homedir(), '.config', 'icloud-app', 'profile');
const STATE_PATH = path.join(PROFILE, 'app-state.json');
const MAX_SECTIONS_SHOWN = 5;

const readJson = (file, fallback) => {
    try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
        return fallback;
    }
};

const currentVersion = readJson(path.join(ROOT, 'package.json'), {}).version;
if (!currentVersion) {
    process.exit(0);
}

const state = readJson(STATE_PATH, {});
const previousVersion = state.lastSeenVersion;

if (previousVersion === currentVersion) {
    process.exit(0);
}

fs.mkdirSync(path.dirname(STATE_PATH), { recursive: true });
fs.writeFileSync(STATE_PATH, JSON.stringify({ ...state, lastSeenVersion: currentVersion }, null, 2));

// A fresh install has nothing to catch up on.
if (!previousVersion) {
    process.exit(0);
}

const parseVersion = (value) => {
    const match = /^(\d+)\.(\d+)\.(\d+)/.exec(String(value || ''));
    return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null;
};

const isNewer = (a, b) => {
    const left = parseVersion(a);
    const right = parseVersion(b);
    if (!left || !right) {
        return false;
    }
    for (let i = 0; i < 3; i += 1) {
        if (left[i] !== right[i]) {
            return left[i] > right[i];
        }
    }
    return false;
};

// Keep a Changelog format: "## [1.2.0] - 2026-08-06", "### Added", "- item".
function parseChangelog(markdown) {
    const sections = [];
    let section = null;
    let group = null;

    for (const rawLine of markdown.split('\n')) {
        const line = rawLine.trimEnd();

        const versionHeading = /^##\s+\[?([0-9]+\.[0-9]+\.[0-9]+)\]?(?:\s+-\s+(.+))?\s*$/.exec(line);
        if (versionHeading) {
            section = { version: versionHeading[1], date: versionHeading[2] || '', groups: [] };
            sections.push(section);
            group = null;
            continue;
        }
        if (!section) {
            continue;
        }

        const groupHeading = /^###\s+(.+?)\s*$/.exec(line);
        if (groupHeading) {
            group = { title: groupHeading[1], items: [] };
            section.groups.push(group);
            continue;
        }

        const bullet = /^[-*]\s+(.+?)\s*$/.exec(line);
        if (bullet) {
            if (!group) {
                group = { title: '', items: [] };
                section.groups.push(group);
            }
            group.items.push(bullet[1]);
            continue;
        }

        if (line.startsWith('  ') && group && group.items.length > 0) {
            group.items[group.items.length - 1] += ` ${line.trim()}`;
        }
    }

    return sections;
}

let markdown;
try {
    markdown = fs.readFileSync(path.join(ROOT, 'CHANGELOG.md'), 'utf8');
} catch (_) {
    process.exit(0);
}

const sections = parseChangelog(markdown)
    .filter((section) => isNewer(section.version, previousVersion))
    .slice(0, MAX_SECTIONS_SHOWN);

if (sections.length === 0) {
    process.exit(0);
}

// Changelog text is escaped rather than inserted as markup: the file is local,
// but a page that renders arbitrary text as HTML is a habit worth not forming.
const escape = (value) => String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

// A deliberately small subset of inline markdown, applied *after* escaping so
// no markup can survive from the source file. Links keep their text and drop
// the URL: this window has nowhere sensible to navigate to.
const inline = (text) => escape(text)
    .replace(/\[([^\]]+)\]\([^)\s]+\)/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`]+)`/g, '<code>$1</code>');

const SECURITY_GROUPS = new Set(['security', 'säkerhet']);
const isSecurity = (title) => SECURITY_GROUPS.has(String(title).trim().toLowerCase());

const body = sections.map((release) => `
    <article class="release">
      <div class="release-head">
        <span class="version">Version ${escape(release.version)}</span>
        ${release.date ? `<span class="date">${escape(release.date)}</span>` : ''}
      </div>
      ${release.groups.map((group) => {
        const secure = isSecurity(group.title);
        const items = group.items.map((item) => `<li>${inline(item)}</li>`).join('');
        if (secure) {
            return `<section class="security">
                <span class="group-title security-title">${escape(group.title)}</span>
                <ul>${items}</ul>
            </section>`;
        }
        return `
        ${group.title ? `<span class="group-title">${escape(group.title)}</span>` : ''}
        <ul>${items}</ul>`;
    }).join('')}
    </article>`).join('');

const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>What's New</title>
<style>
:root { color-scheme: light dark; --bg:#fff; --text:#1d1d1f; --muted:#6e6e73; --border:#d2d2d7; --chip:#f5f5f7;
  --sec-bg:#f0f7ff; --sec-border:#cfe3fb; --sec-text:#0b63c5; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#1c1c1e; --text:#f5f5f7; --muted:#98989d; --border:#3a3a3c; --chip:#2c2c2e;
    --sec-bg:#16233a; --sec-border:#2b4569; --sec-text:#6cb3ff; }
}
* { box-sizing: border-box; }
body { margin:0; padding:26px 28px 32px; background:var(--bg); color:var(--text);
  font-family:-apple-system,"SF Pro Text","Inter","Segoe UI",system-ui,sans-serif; }
h1 { margin:0; font-size:22px; font-weight:600; letter-spacing:-0.015em; }
.subtitle { margin:4px 0 18px; font-size:13px; color:var(--muted); }
.release { padding:16px 0; border-top:1px solid var(--border); }
.release:first-of-type { border-top:none; padding-top:2px; }
.release-head { display:flex; align-items:baseline; gap:10px; margin-bottom:8px; }
.version { font-size:15px; font-weight:600; }
.date { font-size:12px; color:var(--muted); }
.group-title { display:inline-block; margin:12px 0 6px; padding:2px 9px; background:var(--chip);
  border-radius:6px; font-size:11px; font-weight:600; text-transform:uppercase;
  letter-spacing:0.04em; color:var(--muted); }
ul { margin:0; padding-left:20px; }
li { margin:5px 0; font-size:14px; line-height:1.5; }
strong { font-weight:600; }
code { font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace; font-size:12.5px;
  background:var(--chip); padding:1px 5px; border-radius:4px; }
.security { margin:14px 0 4px; padding:12px 14px 14px; border-radius:10px;
  background:var(--sec-bg); border:1px solid var(--sec-border); }
.security ul { padding-left:18px; }
.security-title { margin:0 0 6px; background:transparent; padding:0;
  color:var(--sec-text); }
.security-title::before { content:"🔒 "; }
</style>
</head>
<body>
<h1>What's new in version ${escape(currentVersion)}</h1>
<p class="subtitle">You updated from version ${escape(previousVersion)}.</p>
${body}
</body>
</html>
`;

const outPath = path.join(PROFILE, 'changelog.html');
fs.writeFileSync(outPath, html);
process.stdout.write(outPath);
