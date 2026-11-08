// Inserted by scripts/darkreader-live.py into Dark Reader's background/index.js, right after
// `Messenger.init(...)`, so `_a` (the Extension class) and `UserStorage` are in scope.
//
// Dark Reader accepts settings only from its own popup, so this is the one place a theme can
// be set from outside: it asks the native host for the desktop palette and hands it to
// `_a.setTheme` — the same call the popup makes, so every open tab repaints without a restart.
(() => {
    const HOST = "quicktest_darkreader";
    const HEX = /^#[0-9a-f]{6}$/i;
    const KEYS = new Set([
        "darkSchemeBackgroundColor", "darkSchemeTextColor",
        "lightSchemeBackgroundColor", "lightSchemeTextColor", "selectionColor"
    ]);
    let delay = 1000;
    const connect = () => {
        const port = chrome.runtime.connectNative(HOST);
        port.onMessage.addListener(async (msg) => {
            delay = 1000;
            const next = {};
            for (const [key, value] of Object.entries((msg && msg.theme) || {})) {
                if (KEYS.has(key) && HEX.test(value)) next[key] = value;
            }
            if (!Object.keys(next).length) return;
            await _a.waitUntilReady();
            const now = UserStorage.settings.theme;
            if (Object.keys(next).every((key) => now[key] === next[key])) return;
            _a.setTheme(next);
        });
        // The host exits when the browser closes and may not exist yet: retry, backing off to
        // five minutes so a missing host costs almost nothing.
        port.onDisconnect.addListener(() => {
            void chrome.runtime.lastError;
            setTimeout(connect, delay);
            delay = Math.min(delay * 2, 300000);
        });
    };
    connect();
})();
