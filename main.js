const { app, BrowserWindow, session } = require('electron');

// Valid iCloud services that can be launched
const VALID_SERVICES = [
    'photos',
    'iclouddrive',
    'contacts',
    'notes',
    'mail',
    'calendar',
    'reminders',
    'pages',
    'numbers',
    'keynote',
    'fmf',
    'find'
];

const ICLOUD_ORIGIN = 'https://www.icloud.com';

const WEB_PREFERENCES = {
    nodeIntegration: false,
    contextIsolation: true,
    sandbox: true
};

const WINDOW_DEFAULTS = {
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600
};

function isAllowedURL(url) {
    try {
        const parsed = new URL(url);
        if (parsed.protocol !== 'https:') return false;
        const h = parsed.hostname;
        return h === 'icloud.com' || h.endsWith('.icloud.com')
            || h === 'apple.com' || h.endsWith('.apple.com');
    } catch (_) {
        return false;
    }
}

let mainWindow;

function createWindow(service, title) {
    mainWindow = new BrowserWindow({
        ...WINDOW_DEFAULTS,
        title: `iCloud ${title}`,
        webPreferences: WEB_PREFERENCES
    });

    // Chrome User Agent för maximal kompatibilitet
    mainWindow.webContents.setUserAgent(
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
    );

    mainWindow.loadURL(`${ICLOUD_ORIGIN}/${service}`);

    // Begränsa navigering i huvudfönstret till iCloud/Apple-domäner
    mainWindow.webContents.on('will-navigate', (event, url) => {
        if (!isAllowedURL(url)) {
            event.preventDefault();
        }
    });

    // Hantera nya fönster (popups) - tillåt bara iCloud-domäner
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        if (isAllowedURL(url)) {
            return {
                action: 'allow',
                overrideBrowserWindowOptions: {
                    ...WINDOW_DEFAULTS,
                    webPreferences: WEB_PREFERENCES
                }
            };
        }
        return { action: 'deny' };
    });

    mainWindow.on('closed', () => {
        mainWindow = null;
    });
}

// Läs och validera kommandoradsargument
const args = process.argv.slice(2);
if (args.length < 2) {
    console.error('Usage: electron . <service> <title>');
    console.error('Example: electron . photos Photos');
    console.error(`Valid services: ${VALID_SERVICES.join(', ')}`);
    process.exit(1);
}

const service = args[0];
const title = args[1];

if (!VALID_SERVICES.includes(service)) {
    console.error(`Unknown service: "${service}"`);
    console.error(`Valid services: ${VALID_SERVICES.join(', ')}`);
    process.exit(1);
}

app.whenReady().then(() => {
    // Neka behörigheter som appen inte behöver (kamera, mikrofon, etc.)
    session.defaultSession.setPermissionRequestHandler((_webContents, permission, callback) => {
        const allowed = ['clipboard-read', 'clipboard-sanitized-write', 'notifications'];
        callback(allowed.includes(permission));
    });

    createWindow(service, title);
});

app.on('window-all-closed', () => {
    app.quit();
});

app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
        createWindow(service, title);
    }
});
