// ── test-medialinks.js ────────────────────────────────────────────────────────
// Tests for services/medialinks.js: where a song's title, artists, album and cover link to.
//
//     bun scripts/test-medialinks.js      (or: node scripts/test-medialinks.js)
//
// Pure functions, no I/O.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "medialinks.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const L = new Function(src + "\nreturn { spotifyUri, cleanUri, searchUri, isWeb, appOf, destinationOf, linksFor, openCommand };")();

let pass = 0, fail = 0;
function check(name, ok, detail) {
    if (ok) pass++; else { fail++; console.log("FAIL", name, detail === undefined ? "" : JSON.stringify(detail)); }
}

const ID = "4uLU6hMCjMI75M1A2tKUQC";
const ID2 = "6kLU6hMCjMI75M1A2tKUQD";
const S = q => "spotify:search:" + encodeURIComponent(q);

// ── web → uri ──
check("web track", L.spotifyUri("https://open.spotify.com/track/" + ID) === "spotify:track:" + ID);
check("query string dropped", L.spotifyUri("https://open.spotify.com/track/" + ID + "?si=abc") === "spotify:track:" + ID);
check("not spotify", L.spotifyUri("https://youtube.com/watch?v=" + ID) === "");
check("empty", L.spotifyUri("") === "" && L.spotifyUri(null) === "");

// ── only app targets; a track is never a link (the client would play it) ──
check("album opens in the app", L.appOf("spotify:album:" + ID) === "spotify:album:" + ID);
check("artist opens in the app", L.appOf("spotify:artist:" + ID) === "spotify:artist:" + ID);
check("search opens in the app", L.appOf(S("a b")) === S("a b"));
check("a track is not a link", L.appOf("spotify:track:" + ID) === "");
check("junk is not a link", L.appOf("spotify:album:x; rm") === "" && L.appOf("javascript:x") === "");

// ── spotify, with the bridge ──
const withBridge = L.linksFor(
    { isSpotify: true, url: "https://open.spotify.com/track/" + ID, artist: "A, B", album: "Rec" },
    { trackUri: "spotify:track:" + ID, albumUri: "spotify:album:" + ID2,
      artists: [{ name: "A", uri: "spotify:artist:" + ID }, { name: "B", uri: "spotify:artist:" + ID2 }] });
check("bridge: title is the album, not the song", withBridge.title === "spotify:album:" + ID2);
check("bridge: album", withBridge.album === "spotify:album:" + ID2);
check("bridge: cover is the album", withBridge.cover === "spotify:album:" + ID2);
check("bridge: one link per artist", withBridge.artists.length === 2
    && withBridge.artists[0].link === "spotify:artist:" + ID && withBridge.artists[1].name === "B");

// ── spotify, without it: names are searched in the app ──
const bare = L.linksFor({ isSpotify: true, url: "https://open.spotify.com/track/" + ID, artist: "Tyler, The Creator", album: "IGOR" }, null);
check("bare: the title searches its album", bare.title === S("Tyler, The Creator IGOR"));
check("bare: album searches the names", bare.album === S("Tyler, The Creator IGOR"));
check("bare: an artist string is one entry, never split", bare.artists.length === 1 && bare.artists[0].name === "Tyler, The Creator");
check("bare: artist searches", bare.artists[0].link === S("Tyler, The Creator"));

// ── a bad bridge uri falls back instead of reaching a command ──
const bad = L.linksFor({ isSpotify: true, url: "", artist: "X", album: "Y" },
    { trackUri: "spotify:track:no", albumUri: "$(reboot)", artists: [{ name: "X", uri: "bad" }] });
check("bad uris: no junk link", bad.title === S("X Y") && bad.album === bad.title && bad.title.indexOf("$") < 0);
check("bad uris: album falls to a search", bad.album === S("X Y"));
check("bad uris: artist falls to a search", bad.artists[0].link === S("X"));
check("nothing known, nothing linked", L.linksFor({ isSpotify: true }, null).cover === "" && L.linksFor({ isSpotify: true }, null).artists.length === 0);

// ── other players: the page, in the browser ──
const yt = L.linksFor({ isSpotify: false, url: "https://www.youtube.com/watch?v=abc", artist: "Some Channel", album: "" }, null);
check("web: the title is the page", yt.title === "https://www.youtube.com/watch?v=abc" && yt.cover === yt.title);
check("web: a channel is named, not linked", yt.artists.length === 1 && yt.artists[0].link === "" && yt.album === "");
check("a local file links nowhere", L.linksFor({ isSpotify: false, url: "file:///home/me/a.flac", artist: "Me" }, null).title === "");

// ── what may be run ──
check("open: an album in the app", L.openCommand("spotify:album:" + ID).join(" ") === "xdg-open spotify:album:" + ID);
check("open: a search in the app", L.openCommand(S("a b")).length === 2);
check("open: a video in the browser", L.openCommand("https://example.com/x").length === 2);
check("open: a track runs nothing", L.openCommand("spotify:track:" + ID).length === 0);
check("open: junk runs nothing", L.openCommand("").length === 0 && L.openCommand("-o /etc/passwd").length === 0
    && L.openCommand("file:///etc/passwd").length === 0 && L.openCommand("https://open.spotify.com/track/x;rm").length === 0);
check("destination: app or browser", L.destinationOf("spotify:album:" + ID) === "app" && L.destinationOf("https://example.com") === "browser" && L.destinationOf("") === "");

console.log(fail === 0 ? "ok  " + pass + " checks" : fail + " FAILED of " + (pass + fail));
process.exit(fail === 0 ? 0 : 1);
