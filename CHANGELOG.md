# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project uses [semantic versioning](https://semver.org/).

The app shows the newest entries in a window the first time you start it after
an update.

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
