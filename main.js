const { app, BrowserWindow } = require('electron');

let mainWindow;

function createWindow(service, title) {
    mainWindow = new BrowserWindow({
        width: 1200,
        height: 800,
        minWidth: 800,
        minHeight: 600,
        title: `iCloud ${title}`,
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            sandbox: true
        }
    });

    // Chrome User Agent för maximal kompatibilitet
    mainWindow.webContents.setUserAgent(
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
    );

    // Ladda iCloud-tjänsten
    mainWindow.loadURL(`https://www.icloud.com/${service}`);

    // Hantera nya fönster (popups)
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        return {
            action: 'allow',
            overrideBrowserWindowOptions: {
                width: 1200,
                height: 800,
                minWidth: 800,
                minHeight: 600,
                webPreferences: {
                    nodeIntegration: false,
                    contextIsolation: true,
                    sandbox: true
                }
            }
        };
    });

    mainWindow.on('closed', () => {
        mainWindow = null;
    });
}

// Läs kommandoradsargument
const args = process.argv.slice(2);
if (args.length < 2) {
    console.error('Usage: electron . <service> <title>');
    console.error('Example: electron . photos Photos');
    app.quit();
} else {
    const service = args[0];
    const title = args[1];

    app.whenReady().then(() => {
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
}
