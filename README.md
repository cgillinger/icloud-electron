# iCloud for Linux (Electron)

Access your iCloud services (Photos, Drive, Contacts) on Linux through dedicated application windows.

![iCloud on Linux](https://img.shields.io/badge/Platform-Linux-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Electron](https://img.shields.io/badge/Electron-33.x-brightgreen)

## 🎯 What This Is

This is a **lightweight Electron wrapper** that gives you dedicated application windows for iCloud services on Linux. Think of it as having separate browser windows specifically for iCloud, launched from your application menu.

### ✅ What It Does
- Opens iCloud services in dedicated Electron windows
- Creates desktop shortcuts for Photos, Drive, and Contacts
- Maintains login sessions (you stay logged in)
- Uses modern Chromium engine for full compatibility

### ❌ What It Doesn't Do
- Does NOT provide system integration (no file sync, no notifications)
- Does NOT sync files to your local filesystem
- Does NOT integrate with Linux file managers
- It's essentially a dedicated browser for iCloud, not a native client

## 🔧 Requirements

- **Linux distribution** (tested on Ubuntu 24.04 LTS / Kubuntu 24.04 LTS)
- **Node.js and npm** (version 18 or higher recommended)
- **Apple ID account**
- Internet connection

## 📦 Installation

### Step 1: Install Node.js and npm

**Ubuntu/Debian/Kubuntu:**
```bash
sudo apt update
sudo apt install nodejs npm
```

**Fedora:**
```bash
sudo dnf install nodejs npm
```

**Arch Linux:**
```bash
sudo pacman -S nodejs npm
```

Verify installation:
```bash
node --version
npm --version
```

### Step 2: Clone or Download This Repository

```bash
cd ~
git clone https://github.com/YOUR_USERNAME/icloud-electron.git
cd icloud-electron
```

Or download as ZIP and extract to `~/icloud-electron/`

### Step 3: Install Electron

```bash
cd ~/icloud-electron
npm install
```

### Step 4: Fix Electron Sandbox Permissions

This is **required** for Electron to run properly:

```bash
sudo chown root:root node_modules/electron/dist/chrome-sandbox
sudo chmod 4755 node_modules/electron/dist/chrome-sandbox
```

### Step 5: Test the Application

```bash
cd ~/icloud-electron
npx electron . photos Photos
```

A window should open showing iCloud Photos. If it works, proceed to the next step!

### Step 6: Install Launcher Script

```bash
cat > ~/icloud-electron/icloud-electron.sh << 'EOF'
#!/bin/bash
cd ~/icloud-electron
npx electron . "$@"
EOF

chmod +x ~/icloud-electron/icloud-electron.sh
sudo ln -s ~/icloud-electron/icloud-electron.sh /usr/local/bin/icloud-electron
```

### Step 7: Create Desktop Shortcuts

```bash
mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/icloud-photos-electron.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=iCloud Photos
Comment=Access iCloud Photos
Exec=/usr/local/bin/icloud-electron photos Photos
Icon=emblem-photos
Terminal=false
Categories=Network;Graphics;Photography;
EOF

cat > ~/.local/share/applications/icloud-drive-electron.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=iCloud Drive
Comment=Access iCloud Drive
Exec=/usr/local/bin/icloud-electron iclouddrive Drive
Icon=folder-cloud
Terminal=false
Categories=Network;FileTransfer;
EOF

cat > ~/.local/share/applications/icloud-contacts-electron.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=iCloud Contacts
Comment=Access iCloud Contacts
Exec=/usr/local/bin/icloud-electron contacts Contacts
Icon=x-office-address-book
Terminal=false
Categories=Network;Office;ContactManagement;
EOF

update-desktop-database ~/.local/share/applications/
```

## 🚀 Usage

### Launch from Application Menu

After installation, you'll find these applications in your menu:
- **iCloud Photos** - Access your photo library
- **iCloud Drive** - Access your cloud storage
- **iCloud Contacts** - Manage your contacts

### Launch from Terminal

```bash
# Photos
icloud-electron photos Photos

# Drive
icloud-electron iclouddrive Drive

# Contacts
icloud-electron contacts Contacts

# Notes (if you want)
icloud-electron notes Notes

# Mail (if you want)
icloud-electron mail Mail
```

## 🔐 Login Information

### ⚠️ Important: Passkey Login Does Not Work

When you first open an iCloud service, you'll see a login screen. **DO NOT use "Sign in with passkey"** - it will hang and not receive the verification popup on your other Apple devices.

**Instead:**
1. Click **"Continue with password"**
2. Enter your Apple ID email
3. Enter your Apple ID password
4. Complete two-factor authentication (you'll get a code on your iPhone/iPad/Mac)
5. Check **"Keep me signed in"** to stay logged in

After logging in once, all iCloud services will share the same session.

## 🐛 Troubleshooting

### "FATAL: The SUID sandbox helper binary was found, but is not configured correctly"

Run this command:
```bash
sudo chown root:root ~/icloud-electron/node_modules/electron/dist/chrome-sandbox
sudo chmod 4755 ~/icloud-electron/node_modules/electron/dist/chrome-sandbox
```

### Login screen is cut off or button not visible

The window is resizable. Just drag the corner to make it larger, or maximize it.

### "Your browser is not supported" error

This shouldn't happen with Electron. If it does:
1. Make sure you're using Electron 30 or higher: `npx electron --version`
2. Update Electron: `npm install electron@latest`
3. Repeat Step 4 (sandbox permissions) after updating

### Multiple Electron instances causing errors

If you get IndexedDB or quota database errors:
```bash
killall electron
```

Then try launching again.

### Can't find the application in the menu

Update your desktop database:
```bash
update-desktop-database ~/.local/share/applications/
```

Log out and log back in, or restart your desktop environment.

## 📝 Adding More iCloud Services

You can create shortcuts for any iCloud service using this pattern:

```bash
icloud-electron <service-name> <window-title>
```

**Available services:**
- `photos` - iCloud Photos
- `iclouddrive` - iCloud Drive
- `contacts` - Contacts
- `notes` - Notes
- `mail` - iCloud Mail
- `calendar` - Calendar
- `reminders` - Reminders
- `pages` - Pages
- `numbers` - Numbers
- `keynote` - Keynote

Example desktop file for Notes:
```bash
cat > ~/.local/share/applications/icloud-notes-electron.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=iCloud Notes
Comment=Access iCloud Notes
Exec=/usr/local/bin/icloud-electron notes Notes
Icon=accessories-text-editor
Terminal=false
Categories=Network;Office;
EOF

update-desktop-database ~/.local/share/applications/
```

## 🗑️ Uninstallation

```bash
# Remove desktop shortcuts
rm ~/.local/share/applications/icloud-*-electron.desktop
update-desktop-database ~/.local/share/applications/

# Remove global launcher
sudo rm /usr/local/bin/icloud-electron

# Remove application folder
rm -rf ~/icloud-electron

# Remove stored data (login sessions, cache)
rm -rf ~/.config/icloud-electron
```

## 🔒 Privacy & Security

- This application runs entirely on your local machine
- No data is sent to third parties (only to Apple's iCloud servers)
- Login sessions are stored locally in `~/.config/icloud-electron/`
- The application uses the same Chromium engine as Google Chrome
- Your Apple ID password is only sent to Apple's servers (via HTTPS)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

MIT License - see LICENSE file for details

## ⚠️ Disclaimer

This is an unofficial tool and is not affiliated with, endorsed by, or connected to Apple Inc. iCloud is a trademark of Apple Inc.

## 🙏 Credits

- Built with [Electron](https://www.electronjs.org/)
- Inspired by the need for iCloud access on Linux

## 📚 Keywords

icloud linux, icloud ubuntu, icloud electron, icloud photos linux, icloud drive linux, icloud contacts linux, apple icloud linux, icloud web linux, icloud client linux, icloud wrapper linux, access icloud on linux, icloud debian, icloud fedora, icloud arch linux, icloud kde, icloud gnome
