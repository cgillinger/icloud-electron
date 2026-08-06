# Task: keep the bundled browser current and verified

**Status:** implemented in 2.1.0 (2026-08-06) — see outcome notes below;
"Sign in with iPhone" end-to-end verification on the new browser still pending
**Created:** 2026-08-06
**Applies to:** version 2.0.0
**Estimated size:** one focused session

## Outcome notes (2026-08-06)

- Implemented as planned: `ICLOUD_APP_BROWSER_SOURCE` with `chrome` (default),
  `cft`, `chromium-snapshot`; GPG-verified apt chain with the key pinned at
  `tools/google-linux-signing-key.gpg`; background staged updates applied on
  the next launch; `--check`. All three sources install-tested on
  Chrome 151.0.7922.75-1 / CfT 151.0.7922.76 / snapshot r1675012.
- **The open question resolved with a correction.** The proposed test
  (`strings chrome | grep -x dummytoken`) does not discriminate: `dummytoken`
  is a compiled-in comparison constant, present even in Google Chrome, which
  certainly has Safe Browsing. Counting baked-in API keys
  (`strings chrome | grep -cE '^AIzaSy[0-9A-Za-z_-]{33}$'`) does: Chrome 4,
  CfT 4, snapshot 0. So **CfT does have keys**, but Chrome stayed the default
  because only the apt repository gives a TLS-independent signature.
- The source choice is sticky (recorded in `chromium-build.txt`); 2.0.0
  installs, which recorded no source, migrate to the default on next update.
- On userns-restricting systems, a staged build whose sandbox helper is not
  yet setuid is *not* swapped in; the launcher prints the needed commands
  instead of applying an update that would refuse to start.

---

## Why this exists

Version 2.0.0 replaced Electron with a bundled Chromium, which is what made
"Sign in with iPhone" work. That was the right architecture, but the *source*
of that browser was chosen to prove the architecture quickly, not to run in
production. It has three defects, all found by a security review of 2.0.0:

1. **The build never updates.** `tools/get-chromium.sh` pins a revision. Until
   this task is done, the browser handling the Apple ID password is frozen at
   whatever build was current on 2026-08-06 unless the user runs
   `--force` by hand.
2. **No Safe Browsing.** Chromium builds without Google API keys cannot have
   it, so phishing and malicious-download warnings are inactive. This matters
   more than usual here, because the app-mode window has no address bar and no
   domain allowlist — a phishing link opened from iCloud Mail gets no warning
   from anywhere.
3. **The download is unverified.** 230 MB is fetched over HTTPS and executed.
   The snapshot archive publishes no signatures, so trust rests entirely on TLS
   to `storage.googleapis.com`.

There is a fourth, quieter problem: snapshot builds are **trunk builds, not
stable releases**. They are not `is_official_build`, which means Control Flow
Integrity and profile-guided optimisation are absent — exploit mitigations that
a stable Chromium or Chrome has.

Fixing the source of the browser fixes all four at once.

---

## What was already verified (2026-08-06)

Do not re-derive these; they were checked against live endpoints.

**Chrome for Testing publishes a stable channel with a discovery API.**

```
$ curl -s https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions.json
  Stable   151.0.7922.76  (rev 1654411)
  Beta     152.0.7977.30
  Dev      153.0.7979.3
  Canary   153.0.7993.0
```

Download URLs come from `last-known-good-versions-with-downloads.json`, e.g.
`https://storage.googleapis.com/chrome-for-testing-public/151.0.7922.76/linux64/chrome-linux64.zip`.
**That JSON contains no checksums** — only URLs.

**Google Cloud Storage exposes object metadata**, which gives an integrity
check the download can be compared against:

```
$ curl -s "https://storage.googleapis.com/storage/v1/b/chrome-for-testing-public/o/151.0.7922.76%2Flinux64%2Fchrome-linux64.zip"
  size:    193284800
  md5Hash: hC/AkWNMyAanurxaV9FTfA==   (base64)
  crc32c:  SOPVlA==
```

Note the limitation: this metadata comes from the same server as the file, so
it proves the transfer was not corrupted — **not** that the file is authentic
if Google's storage or your TLS path is compromised.

**Google's Linux apt repository is GPG-signed, and the key is already present
on this machine.**

```
$ curl -sI https://dl.google.com/linux/chrome/deb/dists/stable/Release.gpg
  HTTP/2 200
$ ls /usr/share/keyrings/google-chrome.gpg
  /usr/share/keyrings/google-chrome.gpg
```

This gives a real chain of trust, independent of TLS: `Release.gpg` signs
`Release`, `Release` carries the hash of `Packages`, `Packages` carries the
SHA-256 of the `.deb`. It is exactly what `apt` verifies.

**On licensing.** An earlier concern that only Chromium may be redistributed
does not constrain this task. The script *downloads* the browser onto the
user's machine; the repository never ships a binary. That is the same thing
`npm install electron` did in 1.x. The repo stays clean whichever source is
chosen.

---

## The decision to make first

Three sources, in increasing order of protection:

| Source | Stable channel | Signature | Safe Browsing | Official build | Branding |
|---|---|---|---|---|---|
| Chromium snapshots *(today)* | no | no | no | no | pure open source |
| Chrome for Testing | yes | integrity only | **unverified — check** | likely | Chrome for Testing |
| Google Chrome via apt repo | yes | **GPG** | yes | yes | proprietary Chrome |

**Recommendation:** Google Chrome via the signed apt repository as the default,
because it is the only option that closes all four defects, and Safe Browsing
is the specific protection this app most needs given it has no address bar and
no domain allowlist.

**All three sources stay selectable, and the pure-Chromium path is a
first-class option, not a leftover.** Someone who wants nothing proprietary on
their machine should be able to have that, and the honest trade-off — trunk
builds, manual updates, no Safe Browsing — is theirs to accept knowingly. Do
not let `chromium-snapshot` rot: it must keep working, keep being tested, and
be documented as the FOSS-only choice rather than as a fallback. Concretely:

```bash
ICLOUD_APP_BROWSER_SOURCE=chromium-snapshot ./tools/get-chromium.sh
```

If a source of *stable*, redistributable, pure-Chromium builds for Linux turns
up, prefer it over the snapshot archive for this path — it would remove the
trunk-build drawback while keeping the FOSS property. Worth a look:
distribution tarballs, or a reproducible build service. Not investigated in the
originating session.

**Open question to resolve before implementing:** does a Chrome for Testing
build have working Safe Browsing (i.e. are Google API keys baked in)? Check
with `strings chrome | grep -x dummytoken` on an extracted CfT build — the
presence of `dummytoken` means no API keys, the way it does for the snapshot
build we ship today. If CfT does have keys, it becomes a strong default and
avoids the proprietary-Chrome question entirely.

---

## Implementation plan

### 1. Rework `tools/get-chromium.sh` into a source-aware installer

Add `ICLOUD_APP_BROWSER_SOURCE` with values `chrome` (default), `cft`,
`chromium-snapshot`, and keep the current behaviour available under the last
one. Each source implements: resolve current version, download, verify,
unpack, atomically swap.

For `chrome`:

- Fetch `https://dl.google.com/linux/chrome/deb/dists/stable/Release` and
  `Release.gpg`.
- Verify with `gpgv --keyring /usr/share/keyrings/google-chrome.gpg`, falling
  back to a key shipped in the repo so the app does not depend on Chrome being
  installed. **Pin the key in the repo and document its fingerprint** — a key
  read from the system can be replaced by whoever can write there.
- Parse `main/binary-amd64/Packages` for `google-chrome-stable`, take its
  `SHA256` and `Filename`.
- Download the `.deb`, verify the SHA-256, `dpkg-deb -x` into a staging
  directory, and move `opt/google/chrome` into place.
- `dpkg-deb` is part of `dpkg`, present on Debian-family systems. On others,
  fall back to `ar x` + `tar xf`, both from binutils/tar. Detect and report
  clearly rather than failing obscurely.

For `cft`:

- Read the stable version from `last-known-good-versions-with-downloads.json`.
- Fetch the GCS object metadata for the download URL, keep `size` and
  `md5Hash`, verify both after downloading.

Record what was installed in `chromium-build.txt` — source, version, digest,
date — so the update check can compare and the user can see what they run.

### 2. Add an update check to `icloud-app.sh`

- At launch, if `chromium-build.txt` is older than `ICLOUD_APP_UPDATE_INTERVAL`
  (default 24 h), run the version check **in the background** so it never
  delays the window.
- If a newer stable version exists, download and stage it beside the current
  install, then swap on the *next* launch. A running browser cannot have its
  files replaced underneath it.
- Never block, never prompt, never auto-restart. Log to stderr only.
- Add `--check` to `get-chromium.sh` that reports current versus available and
  exits, for use from the terminal.

### 3. Documentation

- README: replace the "On update cadence" and "On the browser download"
  paragraphs, which currently describe the manual-only situation.
- README: remove the caveat about Safe Browsing being inactive **if** the
  chosen default has it. Do not remove it otherwise — that claim was wrong once
  already and was called out by the review.
- CHANGELOG: new version entry with a `### Security` section.
- Bump `package.json` to 2.1.0.

### 4. Verify before claiming anything

- `strings <browser> | grep -x dummytoken` — absent means API keys are present,
  which means Safe Browsing works.
- Confirm the installed build is `is_official_build` (a stripped binary, no
  `(Developer Build` in `--version`) and that CFI symbols are present.
- **Test "Sign in with iPhone" end to end on the new browser.** This is not
  optional. The whole point of 2.0.0 is that this flow works, and it was only
  ever verified on the snapshot build. Bluetooth must be on.
- Confirm the changelog window, shortcuts and per-service icons still behave.

---

## Acceptance criteria

- [ ] A fresh install pulls a **stable-channel** browser, not a trunk build.
- [ ] The download is verified against a **GPG signature** (Chrome) or a
      published digest (CfT) before anything is executed.
- [ ] Running the app after a new stable release is published results in that
      release being installed, with no manual step.
- [ ] The update never delays or interrupts a launch.
- [ ] `tools/get-chromium.sh --check` reports installed versus available.
- [ ] "Sign in with iPhone" verified working on the new browser, with a note in
      the commit of which version was tested.
- [ ] Every security claim in the README re-checked against what the chosen
      build actually does.
- [ ] The pure-Chromium path still installs and launches, and is documented as
      a supported choice for people who want no proprietary code — with its
      drawbacks stated plainly.

---

## Related findings still open

From the 2.0.0 security review, not covered by this task:

- **No domain allowlist.** An `https://` link clicked inside iCloud Mail opens
  in the same window and profile as the live Apple session, with no address
  bar. Re-adding an allowlist would mean re-introducing a runtime process,
  which is what made 1.x fragile. Safe Browsing (this task) mitigates part of
  it; the rest is currently documented rather than solved. Worth revisiting —
  a Chromium enterprise policy file seeded into the profile may be able to do
  it without a runtime.
- **`ICLOUD_APP_BROWSER` is a substitution point.** Anyone able to set an
  environment variable in the session chooses which binary receives the Apple
  ID password. The launcher now prints the path when the variable is set, which
  is mitigation, not a fix.
- **The sandbox helper is not setuid.** On distributions that restrict
  unprivileged user namespaces (Ubuntu 24.04 among them) the browser refuses to
  start, which is correct fail-closed behaviour. Documented in the README
  troubleshooting section. An installer step could set it, but that needs root.

---

## Background

This work follows a session on 2026-08-06 that rebuilt the project from
Electron to bundled Chromium. Reading it is not required — this document is
self-contained — but it records why several things are the way they are.

- Session transcript:
  `~/.claude/projects/-home-christian-Dokument-Github/ce4e065e-99fb-471f-92dd-26f7b907e5b4.jsonl`
- Session ID: `ce4e065e-99fb-471f-92dd-26f7b907e5b4`
- Resume with: `claude --resume ce4e065e-99fb-471f-92dd-26f7b907e5b4`

Claude Code sessions are stored locally, so there is no shareable URL.

What that session established, briefly:

- Electron packages Chromium's rendering engine but not its browser layer, and
  WebAuthn's working half lives in the browser layer. "Sign in with iPhone"
  therefore cannot work in Electron on Linux
  ([electron/electron#24573](https://github.com/electron/electron/issues/24573)).
- Reimplementing hybrid transport is not viable either: the Rust library
  attempted cannot send WebAuthn extensions at all, and Apple's flow requires
  the PRF extension. Captured traffic showed Apple's page requesting
  `{largeBlob: {read: true}, prf: {eval: {first: ...}}}` with the server
  replying `requirePrf: true`.
- The hybrid/caBLE implementation is entirely open source. Nothing is gated
  behind `is_chrome_branded` and no Google API keys are involved; the tunnel
  servers are hardcoded in `device/fido/cable/v2_handshake.cc` and contacted
  without authentication. Verified empirically: pure open-source Chromium 153
  completed Apple's QR sign-in.
- On Ubuntu, `apt install chromium` yields a **snap**, whose confinement
  commonly blocks the D-Bus access to `org.bluez` that hybrid transport needs.
  Prefer a deb or tarball. This is the most likely cause if the QR option ever
  goes missing.
