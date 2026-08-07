# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project uses [semantic versioning](https://semver.org/).

The app shows the newest entries in a window the first time you start it after
an update.

## [2.3.0] - 2026-08-07

### Changed

- **The icons now ship with the app.** `install-icons.sh` used to download
  icons from the Papirus theme at install time; three of those downloads have
  started failing (the icons were removed upstream) and the Photos icon that
  did arrive looked like a broken-image placeholder. The repository now
  bundles macOS-style icons from the WhiteSur icon theme (GPL-3.0, see
  `icons/README.md`) — Photos gets its pinwheel back — and installing them is
  a local copy that needs no network.

### Fixed

- The Reminders icon was installed under a misspelled name
  (`remainders.svg`). The shortcut generator now uses the correct spelling
  and `install-icons.sh` cleans up the stray file.

## [2.2.0] - 2026-08-06

### Changed

- **Downloads now ask where to save.** An app-mode window has no toolbar and
  no download bubble, so a download used to finish silently in your Downloads
  folder with nothing visible on screen. A save dialog gives both feedback
  that something happened and the choice of destination — the desktop, a
  folder, anywhere. New profiles get this from the start; existing profiles
  are migrated once, on the first launch where no window is already open
  (needs `python3`; if you later turn the prompt off again, that choice
  sticks).

## [2.1.0] - 2026-08-06

### Added

- **The browser now keeps itself current.** At most once a day, launching the
  app checks for a newer stable release in the background, downloads and
  verifies it beside the current install, and swaps it in on the next launch.
  The check never delays or interrupts a window, never prompts, and can be
  tuned or disabled with `ICLOUD_APP_UPDATE_INTERVAL` (seconds; `0` disables).
- **The browser source is a choice**, made with `ICLOUD_APP_BROWSER_SOURCE`:
  `chrome` (default) is Google Chrome stable from Google's GPG-signed apt
  repository; `cft` is Chrome for Testing stable, integrity-checked against
  Google Cloud Storage metadata; `chromium-snapshot` is pure open-source
  Chromium for anyone who wants no proprietary code — still supported, still
  tested, with its trade-offs stated plainly in the README. The choice is
  sticky: updates follow the source you installed from.
- `tools/get-chromium.sh --check` reports the installed versus available
  version from the terminal.

### Changed

- **The default browser is now Google Chrome stable** instead of a Chromium
  trunk snapshot. Installs made by 2.0.0 (which recorded no source choice)
  migrate to the default on their next update; set
  `ICLOUD_APP_BROWSER_SOURCE=chromium-snapshot` before then to stay on pure
  Chromium.

### Security

This release closes the browser-supply weaknesses found by the 2.0.0 security
review:

- **Stable channel instead of trunk.** The default build is an official stable
  release, with the exploit mitigations trunk snapshots lack (Control Flow
  Integrity, profile-guided optimisation).
- **The download is verified before anything is executed.** The default source
  follows the same chain of trust `apt` uses: `Release.gpg` signs `Release`,
  which carries the hash of `Packages`, which carries the SHA-256 of the
  package — verified against Google's signing key **pinned in this repo**
  (fingerprint `EB4C 1BFD 4F04 2F6D DDCC EC91 7721 F63B D38B 4796`), so trust
  no longer rests on TLS alone. The `cft` source verifies size and MD5 from
  storage metadata (integrity only); the snapshot source remains unverifiable,
  which is documented rather than hidden.
- **Safe Browsing is active** in the default build, and in Chrome for Testing
  (verified: both carry Google API keys; the snapshot build carries none).
  This matters here because the window has no address bar and no domain
  allowlist. The 2.0.0 test for this — `strings chrome | grep -x dummytoken` —
  turned out not to discriminate: that string is a compiled-in constant present
  even in builds with keys. Key presence itself was checked instead.
- **A frozen browser can no longer happen silently.** 2.0.0 pinned a revision
  and updated only by hand; the browser handling the Apple ID password now
  tracks the stable channel on its own.

## [2.0.0] - 2026-08-06

### Added

- **"Sign in with iPhone" works.** Scan the QR code on Apple's login page with
  your iPhone camera and sign in without typing a password. Passkeys, PRF and
  every other WebAuthn feature work too, because the app now runs on a complete
  browser rather than an embedded engine.
- The app ships its own Chromium build, downloaded once by
  `tools/get-chromium.sh`. Behaviour no longer depends on what happens to be
  installed on the machine.
- A window showing what changed, the first time the app starts after an update.

### Changed

- **The app is built on Chromium in app mode instead of Electron.** Electron
  packages Chromium's rendering engine but not its browser layer, and the
  WebAuthn implementation - transport selection, the QR dialog, the credential
  picker, PRF, largeBlob - lives in the browser layer. That is why the
  "Sign in with iPhone" button used to spin forever
  ([electron/electron#24573](https://github.com/electron/electron/issues/24573)).
- Windows are grouped per service by the desktop environment, so each iCloud
  service gets its own icon in the dock or task bar.

### Removed

- The Electron dependency, and with it the `chrome-sandbox` permission fix that
  installation used to require.
- An experimental Rust helper that reimplemented WebAuthn hybrid transport.
  It could not work: the library it used cannot send WebAuthn extensions at
  all, and Apple's flow requires the PRF extension.

### Security

- Sessions run inside a real browser sandbox with site isolation, instead of an
  embedded engine configured by this project.
- Passkey sign-in is handled by Chromium's own WebAuthn implementation rather
  than a hand-written one.
- The dedicated profile keeps iCloud cookies out of your everyday browser, and
  the browser's password manager is switched off in it.
- **Known weaknesses, stated plainly.** The bundled browser does not update
  itself — run `tools/get-chromium.sh --force` periodically. It has no Safe
  Browsing, because builds without Google API keys cannot have it. And unlike
  version 1.x there is no allowlist stopping the window from navigating away
  from Apple's domains. Setting `ICLOUD_APP_BROWSER` to a browser your
  distribution keeps patched removes all three. See the README for detail.

## [1.0.0] - 2026-06-02

### Added

- First release: an Electron shell around the iCloud services, with shortcuts
  in the application menu.
- Navigation and popups are restricted to Apple and iCloud domains.
- Permissions the app does not need (camera, microphone, location) are denied.
