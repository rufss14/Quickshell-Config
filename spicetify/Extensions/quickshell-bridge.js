// ── quickshell-bridge ─────────────────────────────────────────────────────────
// Pushes Spotify's OWN playhead out to the Quickshell shell, so the lyrics card can
// run off the app's clock instead of MPRIS's coarse approximation of it.
//
// Companion to  scripts/spotify-bridge.py  in the Quickshell config, which listens on
// loopback and turns each POST into a JSON line for the shell to read.
//
// ── Why this exists at all ────────────────────────────────────────────────────
// This extension runs INSIDE Spotify's renderer — the same privileged position Spicy
// Lyrics occupies. That means no cookie scraping and no token minting: the numbers
// below are the ones the player itself is using to draw its own progress bar.
//
// ── It sends ANCHORS, not a position stream ───────────────────────────────────
// An anchor goes out on songchange, play/pause, and a detected seek — about five per
// song. The shell interpolates between them off a monotonic clock, so streaming
// `onprogress` (which fires many times a second) would be pure noise for a value the
// other end can derive exactly.
//
// ── API shape is read defensively ─────────────────────────────────────────────
// Spicetify's `Player.data` has changed shape across versions (`item` vs `track`,
// `metadata` vs flat fields). Every read below falls back rather than assuming, because
// a wrong guess here fails silently — an anchor with an empty title still posts fine and
// the shell just never matches a track.
//
// ── WHEN THIS STOPS WORKING, IT IS ONE OF THESE ───────────────────────────────
// Every one of them has actually happened, and every one failed SILENTLY: no lyrics, a
// red cross on the card, and nothing in any log. Check them in this order — it is roughly
// cheapest first, and `qs ipc -c ~/.config/quicktest call spotify lyrics` answers most of
// them outright.
//
//  1. THE INJECTED COPY IS STALE.  Editing this file changes nothing until
//     `spicetify apply` copies it into /opt/spotify/Apps/xpui/extensions/ and restarts
//     Spotify. Compare the two with `cmp` before believing any other diagnosis; a stale
//     copy has impersonated three different bugs so far.
//
//  2. THE EXTENSION THREW AT LOAD.  It is `defer`ed, so it runs before Spicetify has
//     defined its global. Anything that touches an undeclared identifier at the top —
//     `!Spicetify` rather than `typeof Spicetify === "undefined"` — throws ReferenceError
//     and takes the whole IIFE with it, retry timer included. Symptom: no anchors at all,
//     not even a playhead. There is no console unless `spicetify enable-devtools` has
//     been run, which is why this one cost the most.
//
//  3. THE TOKEN ACCESSOR MOVED.  `Platform.AuthorizationAPI.getState().token.accessToken`
//     is verified against THIS Spicetify's helper/spicetifyWrapper.js. Spicy Lyrics' own
//     source calls `Platform.GetSpotifyAccessToken()`, which does not exist here at all.
//     Check the wrapper, never their repo and never memory. Symptom: "no access token".
//
//  4. THE VERSION HEADER WAS RETIRED.  `SpicyLyrics-Version` is validated server-side and
//     an unrecognised value comes back as a bare HTTP 400. Bump CLIENT_VERSION to their
//     current release. Symptom: "http 400" with a server message attached.
//
//  5. THE WIRE FORMAT CHANGED.  The API answers with a packed [values, opcodes] pair, not
//     JSON — see services/objpack.js. Symptom: "payload did not map", with the payload's
//     structure printed beside it.
//
//  6. TIMERS ARE THROTTLED.  Chromium clamps setInterval to roughly once a MINUTE while
//     Spotify's window is hidden, which is its normal state behind the shell. Anything
//     that must stay live rides `onprogress`, which is playback-driven. Symptom: the
//     playhead is a minute stale after a shell reload, or lyrics take minutes to arrive.
//
//  7. THE PORT IS HELD BY A DEAD SHELL'S LISTENER.  See spotify-bridge.py. Symptom: the
//     shell reports state "error" and nothing arrives at all.
//
//  8. NOT A FAULT: PAUSED, HIDDEN, AND THE SHELL RESTARTED.  This one looks exactly like
//     a dead extension and is not one, so check it before doing any real work.
//
//     The anchor heartbeat rides `onprogress` because that is the only signal Chromium
//     does not throttle (failure 6). `onprogress` requires PLAYBACK. So with Spotify
//     paused AND its window hidden — its normal state behind the shell — there is no
//     unthrottled event left: the interval below is clamped to roughly once a minute and
//     may be deferred well past that under intensive throttling. Measured: still silent
//     after 75 seconds.
//
//     Symptom: `status` says "listening (no track)" and stays there, with everything else
//     verifiably healthy — injected copy in sync, Spotify restarted with it, listener
//     bound and parented to the live shell. It clears the moment playback resumes or the
//     window is shown, and only ever appears after a shell restart.
//
//     There is no fix from inside the renderer; the throttle is the browser's and it is
//     not negotiable. Play something before concluding the bridge is broken.
//
// The rule underneath all of it: this bridge spans three processes that cannot see each
// other's failures, so anything that can fail must SAY so. That is what
// `postLyrics(uri, null, reason)` is for, and why the shell keeps `lastLyricsError`
// rather than only logging it.
// ─────────────────────────────────────────────────────────────────────────────

(function quickshellBridge() {
    const PORT = 47821;                 // must match spotify-bridge.py's DEFAULT_PORT
    const URL  = "http://127.0.0.1:" + PORT + "/";

    const SEEK_EPS_MS = 400;            // progress this far off expectation is a seek
    const MIN_GAP_MS  = 200;            // never post more often than this
    const HEARTBEAT_MS = 5000;          // re-state the anchor at least this often
    const LYRICS_REPOST_MS = 20000;     // re-state the cached lyrics at least this often

    // ── typeof, NOT a truthiness test ─────────────────────────────────────────
    // This was `if (!Spicetify || !Spicetify.Player || …)`, and it was fatal.
    //
    // Referencing an UNDECLARED identifier throws ReferenceError in JavaScript — it does
    // not evaluate to undefined the way a missing property does. This script is `defer`ed,
    // so it runs before Spicetify's wrapper has defined the global, which means `!Spicetify`
    // threw and took the whole IIFE with it — including the setTimeout retry on the very
    // next line, which never got the chance to register.
    //
    // So the guard written to survive "Spicetify isn't ready yet" was the one thing that
    // could not survive it. The extension was dead from load, permanently, with no anchors,
    // no lyrics and nothing anywhere saying so: a renderer with no visible console throws
    // into the void.
    //
    // `typeof x === "undefined"` is the only safe way to test a possibly-undeclared global.
    if (typeof Spicetify === "undefined"
        || !Spicetify.Player
        || !Spicetify.Player.addEventListener) {

        // Fast at first: 150ms × 200 tries (30s) covers a Spicetify that is merely slow
        // to boot, and halves the typical wait of the old 300ms × 100.
        //
        // ── …but never GIVE UP ────────────────────────────────────────────────
        // It used to stop after those 200 tries, so that a Spicetify that never loads
        // couldn't leave a timer running forever. A Spotify launched in the background
        // (`spicetify apply` relaunches it onto a workspace nobody is looking at) can take
        // longer than that to bring Spicetify up — and then this extension was dead for
        // the whole session: no anchors, no lyrics, no repaint for the wave, and nothing
        // saying so. Measured: zero connections to the bridge in 75s from a live
        // renderer. After the fast tries, one cheap check every 2s until it's there.
        quickshellBridge.tries = (quickshellBridge.tries || 0) + 1;
        setTimeout(quickshellBridge, quickshellBridge.tries <= 200 ? 150 : 2000);
        return;
    }

    let lastSentAt   = 0;               // performance.now() of the last post
    let expectedMs   = 0;               // where we think the playhead should be
    let expectedAt   = 0;               // when that expectation was formed
    let lastUri      = null;

    // ── Metadata ──────────────────────────────────────────────────────────────
    // Total, like post(): `Spicetify.Player.data` can throw while the player is still
    // coming up, and waitForTrack() calls this at load.
    function trackInfo() {
        try { return readTrack(); } catch (e) {
            return { trackUri: "", title: "", artist: "", album: "", durationMs: 0 };
        }
    }
    function readTrack() {
        const d    = Spicetify.Player.data || {};
        const item = d.item || d.track || {};
        const meta = item.metadata || {};

        const artists = item.artists;
        const artist  = Array.isArray(artists) && artists.length
            ? artists.map(a => a.name || a.title || "").filter(Boolean).join(", ")
            : (meta.artist_name || "");

        return {
            trackUri:   item.uri || meta.uri || "",
            title:      item.name || meta.title || "",
            artist:     artist,
            album:      (item.album && item.album.name) || meta.album_title || "",
            durationMs: (item.duration && item.duration.milliseconds)
                        || Number(meta.duration) || 0
        };
    }

    // ── Post ──────────────────────────────────────────────────────────────────
    // `mode: "no-cors"` on purpose: this is fire-and-forget, we never read the reply,
    // and a simple request with a text/plain body skips the CORS preflight entirely.
    // `keepalive` so an anchor sent as Spotify is closing still leaves the process.
    // ── post() must never THROW ───────────────────────────────────────────────
    // At load, Spicetify.Player exists before the player behind it does, and
    // getProgress() threw. post("init") is called at the top level of this IIFE, so
    // that one throw ended the extension's startup right there: the listeners above
    // it lived on (which is why anchors still arrived once something played), but the
    // 5s heartbeat and everything after it — the wave's restyle poll included — never
    // ran in any Spotify. Measured: no page ever delivered an "init", and every page's
    // first message was a playback event. A reading that isn't there yet is 0.
    function readPlayer(fn, fallback) {
        try { return fn(); } catch (e) { return fallback; }
    }
    function post(reason) {
        const now = performance.now();
        const info = trackInfo();

        const positionMs = readPlayer(() => Spicetify.Player.getProgress(), 0) || 0;
        const playing    = !!readPlayer(() => Spicetify.Player.isPlaying(), false);

        expectedMs = positionMs;
        expectedAt = now;
        lastSentAt = now;

        const body = JSON.stringify({
            type:   "anchor",
            reason: reason,
            trackUri:   info.trackUri,
            title:      info.title,
            artist:     info.artist,
            album:      info.album,
            durationMs: info.durationMs,
            positionMs: positionMs,
            playing:    playing,
            sentAt:     Math.round(now)
        });

        try {
            fetch(URL, {
                method: "POST",
                mode: "no-cors",
                headers: { "Content-Type": "text/plain" },
                body: body,
                keepalive: true
            }).catch(() => {});     // shell not running is the normal case, not an error
        } catch (e) { /* never let the bridge break playback */ }
    }

    // ── Lyrics ────────────────────────────────────────────────────────────────
    // Fetched HERE rather than in the shell, and that is the whole reason this works.
    //
    // The API authenticates with a live Spotify access token — the same one the client is
    // already holding. Inside the renderer that is one call away; outside it, it would
    // mean scraping an sp_dc cookie and minting tokens, which is the fragile path this
    // bridge exists to avoid. The shell receives lyrics it could not have fetched itself.
    //
    // Failure here is NEVER fatal: the shell keeps its own NetEase/LRCLIB lookup and falls
    // back to it whenever nothing arrives. That matters because this endpoint gates on a
    // client version header, so it can start refusing us without warning.
    const LYRICS_API = "https://api.spicylyrics.org/query";

    // Sent as SpicyLyrics-Version, and their server VALIDATES it. A made-up value like
    // "3.0.0" comes back as a bare HTTP 400; a version that's merely STALE (e.g. 6.3.1
    // once 6.3.12 was out) comes back 200 with a fake "Static" lyric reading
    // "Please update Spicy Lyrics" — which decodes fine but maps to nothing, so the
    // symptom is `qs ipc … call spotify lyrics` -> "payload did not map".
    //
    // This is the single most likely thing to rot: when they cut a release and retire
    // this one, lyrics stop arriving. Bump it to whatever
    //   https://github.com/Spikerko/spicy-lyrics/releases/latest
    // reports. Failure is never fatal — the shell falls back to its own lookup.
    const CLIENT_VERSION = "6.3.15";

    let lastLyricsPayload = null;         // kept so a restarted shell can be re-told
    let lastLyricsPostAt  = 0;            // performance.now() of the last lyrics post

    // ── Getting the token ─────────────────────────────────────────────────────
    // VERIFIED against the installed helper/spicetifyWrapper.js, which builds its own
    // auth header exactly this way. The obvious-looking `Platform.GetSpotifyAccessToken()`
    // — which is what Spicy Lyrics' own source calls — does NOT exist on Spicetify 2.44:
    // zero occurrences in the wrapper. Calling it threw a TypeError on every single track,
    // the catch below turned that into a quiet failure, and the shell fell back to NetEase
    // every time while looking like it had merely found no lyrics.
    //
    // The older name is still tried second, because other Spicetify builds do expose it
    // and there is no reason to break on those.
    function accessToken() {
        try {
            const st = Spicetify.Platform
                    && Spicetify.Platform.AuthorizationAPI
                    && Spicetify.Platform.AuthorizationAPI.getState
                    && Spicetify.Platform.AuthorizationAPI.getState();
            if (st && st.token && st.token.accessToken) return st.token.accessToken;
        } catch (e) { /* fall through to the alternate spelling */ }

        try {
            if (typeof Spicetify.Platform.GetSpotifyAccessToken === "function")
                return Spicetify.Platform.GetSpotifyAccessToken();
        } catch (e) { /* no token available */ }

        return null;
    }

    // ── Attempted is not the same as succeeded ────────────────────────────────
    // These used to be one variable, set BEFORE the request went out. That made a single
    // failure permanent for the track: the guard saw the uri already recorded and refused
    // to try again, forever, with nothing anywhere saying why.
    let lyricsHaveFor  = null;   // uri we actually hold a payload for
    let lyricsTriedFor = null;   // uri of the attempt in flight or last finished
    let lyricsAttempts = 0;      // attempts against lyricsTriedFor

    const MAX_ATTEMPTS = 3;

    async function fetchLyrics(uri) {
        if (!uri || !uri.startsWith("spotify:track:")) return;
        if (uri === lyricsHaveFor) return;                 // already have them

        if (uri === lyricsTriedFor) {
            // Retrying the same track: bounded, so a track their database genuinely does
            // not have cannot turn into an endless poll against someone else's server.
            if (lyricsAttempts >= MAX_ATTEMPTS) return;
        } else {
            lyricsTriedFor = uri;
            lyricsAttempts = 0;
        }
        lyricsAttempts++;

        const trackId = uri.split(":")[2];
        if (!trackId) return;

        try {
            const token = await accessToken();
            if (!token) { postLyrics(uri, null, "no access token"); return; }

            const res = await fetch(LYRICS_API, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "SpicyLyrics-Version": CLIENT_VERSION,
                    "X-mode": "2",
                    "SpicyLyrics-WebAuth": "Bearer " + token
                },
                body: JSON.stringify({
                    queries: [{
                        operation: "lyrics",
                        variables: { id: trackId, auth: "SpicyLyrics-WebAuth" }
                    }],
                    client: { version: CLIENT_VERSION }
                })
            });

            if (!res.ok) {
                // Include whatever the server said. A bare status told us a 400 was
                // happening but nothing about which field it objected to, which is most of
                // why the version mismatch took a full debug cycle to find. Truncated
                // because this ends up in a log line, not a document.
                let detail = "";
                try { detail = (await res.text() || "").slice(0, 200).replace(/\s+/g, " "); }
                catch (e) { /* body already consumed or not text */ }

                postLyrics(uri, null, "http " + res.status + (detail ? " — " + detail : ""));
                return;
            }

            // The envelope is { queries: [ { operationId, result: { data, … } } ] }. We
            // send exactly one query, so its id is "0" — but match by id rather than
            // taking [0], because the contract is a keyed list, not an ordered one.
            const body = await res.json();
            const jobs = (body && body.queries) || [];
            let payload = null;
            for (const job of jobs) {
                if (job && job.operationId === "0") { payload = job.result && job.result.data; break; }
            }
            if (!payload && jobs.length > 0) payload = jobs[0].result && jobs[0].result.data;

            postLyrics(uri, payload, payload ? "" : "no payload");
        } catch (e) {
            postLyrics(uri, null, String(e && e.message ? e.message : e));
        }
    }

    function postLyrics(uri, payload, error) {
        if (payload) {
            lastLyricsPayload = payload;
            lyricsHaveFor = uri;
        }
        lastLyricsPostAt = performance.now();

        const body = JSON.stringify({
            type: "lyrics",
            trackUri: uri,
            payload: payload || null,
            error: error || ""
        });
        try {
            fetch(URL, {
                method: "POST",
                mode: "no-cors",
                headers: { "Content-Type": "text/plain" },
                body: body,
                keepalive: true
            }).catch(() => {});
        } catch (e) { /* never let this break playback */ }
    }

    // ── Events ────────────────────────────────────────────────────────────────
    // ── songchange fires BEFORE Player.data catches up ────────────────────────
    // Reading trackInfo() synchronously here returns the PREVIOUS track often enough to
    // matter: the anchor went out with the old uri and the lyrics fetch asked for the old
    // song, so the card showed the wrong words — confidently, and in sync with nothing,
    // which is the exact failure scripts/lyrics.py's own header calls the one that counts.
    //
    // Deferring a frame lets the client settle, and the uri is re-read AFTER the wait
    // rather than captured before it. `onprogress` below is the backstop if this is ever
    // still early: it compares the live uri against lastUri on every tick.
    Spicetify.Player.addEventListener("songchange", () => {
        setTimeout(() => {
            const uri = trackInfo().trackUri;
            if (!uri) return;
            lastUri = uri;
            post("songchange");
            fetchLyrics(uri);
        }, 80);
    });

    Spicetify.Player.addEventListener("onplaypause", () => post("playpause"));

    // Seek detection. `onprogress` fires continuously; we only care when the reported
    // position disagrees with where simple elapsed time says it should be — that is a
    // scrub, a skip, or a stall. Everything else the shell already knows how to compute.
    Spicetify.Player.addEventListener("onprogress", (e) => {
        const now = performance.now();
        const posMs = (e && typeof e.data === "number") ? e.data
                                                        : (Spicetify.Player.getProgress() || 0);

        // A track change can land here before songchange does; treat it as an anchor.
        const uri = trackInfo().trackUri;
        if (uri && uri !== lastUri) {
            lastUri = uri;
            post("track");
            // This branch used to post the anchor and return WITHOUT fetching, so it was
            // possible to have a perfectly live playhead and never once ask for lyrics —
            // which is exactly what happened after `spicetify apply` restarted Spotify
            // mid-song: init ran before Player.data was populated, no songchange ever
            // fired because the song never changed, and this was the only path left.
            fetchLyrics(uri);
            return;
        }

        // ── The real heartbeat lives HERE, not on setInterval ─────────────────
        // Measured on this machine: with Spotify's window hidden — its normal state behind
        // a shell overlay — Chromium throttles setInterval to roughly once a MINUTE. The
        // 5s heartbeat became a 60s one, so after a shell reload the card sat blank for up
        // to a minute, and the lyrics retry hanging off the same timer took three minutes
        // to exhaust its attempts. An anchor was observed arriving between t=60s and t=90s
        // when it should have come at t=5s.
        //
        // `onprogress` is driven by playback rather than a wall clock, so it survives the
        // throttling that flattens timers. It only fires while something is playing, which
        // is exactly when a stale playhead matters; the interval below stays as the
        // fallback for the paused case, where being a minute late costs nothing.
        if (now - lastSentAt >= HEARTBEAT_MS) {
            post("heartbeat");

            // No payload for this track yet — ask for one.
            if (lastUri && lastUri !== lyricsHaveFor) {
                fetchLyrics(lastUri);
            }
            // We DO have one: re-state it periodically so a restarted shell gets it back.
            // This used to live on the setInterval below with the rest of the heartbeat,
            // which is exactly the throttled path — so after a shell reload the playhead
            // came back within seconds (this handler) while the words took minutes (that
            // one). Anything the shell needs after a restart has to be on this side of
            // the throttle.
            else if (lastLyricsPayload && now - lastLyricsPostAt >= LYRICS_REPOST_MS) {
                postLyrics(lyricsHaveFor, lastLyricsPayload, "");
            }
            return;
        }

        if (now - lastSentAt < MIN_GAP_MS) return;

        const elapsed  = Spicetify.Player.isPlaying() ? (now - expectedAt) : 0;
        const expected = expectedMs + elapsed;

        if (Math.abs(posMs - expected) > SEEK_EPS_MS) post("seek");
    });

    // One anchor at startup so a shell that starts mid-song is not blind until the next
    // track boundary — and the lyrics for whatever is already playing.
    // Deferred for the same reason songchange is: at extension load `Player.data` is
    // usually not populated yet, so reading the uri here returns "" and the fetch guard
    // drops the request on the floor without a trace.
    //
    // ── Polled, not a flat wait ────────────────────────────────────────────────
    // This used to be a single setTimeout(…, 1500) — a fixed 1.5s of dead air on every
    // Spotify launch before the first real anchor or lyrics fetch went out, regardless of
    // how soon Player.data actually populated. It usually does well under that. Checking
    // every 150ms instead fires the moment the data is real, while 1500ms stays as the
    // worst case for a slow load — so this can only ever connect sooner, never later.
    post("init");
    (function waitForTrack(tries) {
        const uri = trackInfo().trackUri;
        if (uri || tries >= 10) {
            post("init");
            if (uri) fetchLyrics(uri);
            return;
        }
        setTimeout(function () { waitForTrack(tries + 1); }, 150);
    })(0);

    // ── Heartbeat ─────────────────────────────────────────────────────────────
    // Yes, this is polling, and the rest of this bridge is deliberately not. It earns the
    // exception: the anchors above are pushed on EVENTS, and the shell is the thing that
    // restarts. Reload Quickshell mid-song and the listener comes up to silence — Spotify
    // has nothing to say until the next track change, so the card sat blank for the rest
    // of the song. That was the "doesn't detect the song if it's already playing" bug.
    //
    // The extension cannot be told the shell came back (nothing can reach into the
    // renderer), so the only way for a restarted listener to learn the current state is
    // for this side to repeat itself occasionally.
    //
    // 5s is the whole cost: one small POST to loopback, twelve times a minute, and it is
    // also the worst-case blank period after a reload. Anchors stay event-driven — this
    // only re-states what the shell should already know.
    let beats = 0;
    setInterval(function () {
        post("heartbeat");

        // The restyle poll rides the heartbeat too (see pollEvents): requests made as
        // the page loads were measured to vanish in Spotify — not even the "init"
        // anchors arrived — so the poll started there could hang forever, and this is
        // the one path proven to deliver. A poll in flight longer than the bridge ever
        // holds one is dead; start another.
        if (beats === 0) say({ event: "start" });
        if (!pollLive || performance.now() - pollAt > EVENT_HOLD_MS + 10000) pollEvents();

        // The anchor heartbeat alone is not enough after a shell restart: this side still
        // has the track recorded, so nothing would re-fetch, and the card would sit with a
        // live playhead and no words for the rest of the song. Re-stating the CACHED
        // payload costs no network — but it is far bigger than an anchor, so it goes out
        // every sixth beat (~30s) rather than every one.
        beats++;

        // Re-state the cached payload so a RESTARTED SHELL gets it back. Costs no network.
        if (beats % 6 === 0 && lastLyricsPayload && lyricsHaveFor)
            postLyrics(lyricsHaveFor, lastLyricsPayload, "");

        // ── The retry that was missing entirely ───────────────────────────────
        // Every path to fetchLyrics was an event: songchange, or init. Miss both — which
        // is the normal case when Spotify restarts mid-song — and nothing ever asked for
        // lyrics again for that track. There was no route back.
        //
        // The heartbeat is already running, so it costs nothing to let it notice that the
        // current track has no payload and try again. Bounded by MAX_ATTEMPTS inside
        // fetchLyrics, so a track with genuinely no lyrics settles after three tries
        // rather than polling someone else's server forever.
        if (lastUri && lastUri !== lyricsHaveFor) fetchLyrics(lastUri);
    }, 5000);

    // ── Restyle: the shell asks, this side repaints, then says when it HAS ─────
    // The wave (services/Contagion.qml) rewrites the theme on disk (spicetify refresh)
    // and holds its front until Spotify shows it. Nothing outside the renderer can see
    // when that is, so this does the swap and reports it: reload-theme.sh POSTs
    // /restyle to the bridge, which answers the GET /events held open here.
    //
    // Each theme sheet is CLONED with a fresh ?v= and the old one removed only once the
    // new one has loaded — swapping href in place drops the sheet for the frames the
    // fetch takes, which is an unstyled flash. Then two frames (the recalc, and the
    // paint it causes) before reporting; a hidden renderer runs no frames, so a timer
    // races them.
    //
    // The poll is EXACTLY the shape the anchors use — a no-cors POST with
    // `keepalive` — because that is the only shape this renderer was measured to
    // deliver to loopback. Traced at the bridge over a minute: 16 anchor POSTs, and
    // not one byte of the poll, whether it was a cors GET or a no-cors POST WITHOUT
    // keepalive. Chromium holds an ordinary fetch from this origin to 127.0.0.1
    // before it leaves (its local-network rules); a keepalive fetch is loaded by the
    // browser process and goes. So `listening` stayed false and the wave never waited.
    // A no-cors reply is opaque, so an event is told from a timeout by TIME: the
    // bridge holds an idle poll EVENT_HOLD_S (25s — short, since a keepalive load may
    // be capped) and answers an event at once. Polls chain off promises, not timers,
    // so a hidden window doesn't throttle them (failure 6); one that never settles is
    // aborted.
    const EVENT_HOLD_MS = 25000;
    const SHEET_RE      = /(^|\/)(colors|user)\.css/;

    function restyle() {
        const started = performance.now();
        const v = Date.now();
        const old = Array.from(document.querySelectorAll("link[rel=stylesheet]"))
            .filter(l => SHEET_RE.test(l.getAttribute("href") || ""));
        const loads = old.map(link => new Promise(done => {
            const fresh = link.cloneNode();
            let settled = false;
            const finish = ok => {
                if (settled) return;
                settled = true;
                if (ok) link.remove(); else fresh.remove();
                done(ok);
            };
            fresh.onload  = () => finish(true);
            fresh.onerror = () => finish(false);
            setTimeout(() => finish(false), 4000);
            fresh.setAttribute("href", (link.getAttribute("href") || "").split("?")[0] + "?v=" + v);
            link.after(fresh);
        }));
        // Resolves once the report has gone out — the bridge treats it as the
        // acknowledgement, and polls again before it would only repaint twice.
        return Promise.all(loads).then(results => new Promise(done => {
            let sent = false;
            const report = () => {
                if (sent) return;
                sent = true;
                try {
                    fetch(URL, {
                        method: "POST", mode: "no-cors", keepalive: true,
                        headers: { "Content-Type": "text/plain" },
                        body: JSON.stringify({
                            type: "restyled", sheets: old.length,
                            loaded: results.filter(Boolean).length,
                            ms: Math.round(performance.now() - started)
                        })
                    }).catch(() => {}).then(done);
                } catch (e) { done(); }
                setTimeout(done, 1000);     // a report that never settles mustn't stop polling
            };
            requestAnimationFrame(() => requestAnimationFrame(report));
            setTimeout(report, 250);
        }));
    }

    // ── Saying what happened, since nothing else can ───────────────────────────
    // Spotify's console is off, and a fetch Chromium refuses never reaches the bridge
    // to be seen. So the extension reports on itself through the one path measured to
    // work (an anchor-shaped POST): which build is running, and every way the poll
    // fails. The bridge logs it; SpotifyBridge prints it. States and error names only.
    const EXT_BUILD = "mailbox-10";     // restyle-8 + the mailbox and "play X" via searchSuggestions (2026-10-24)
    let pollFailures = 0;
    function say(what) {
        try {
            fetch(URL, {
                method: "POST", mode: "no-cors", keepalive: true,
                headers: { "Content-Type": "text/plain" },
                body: JSON.stringify(Object.assign({ type: "ext", build: EXT_BUILD }, what))
            }).catch(() => {});
        } catch (e) { /* never let the bridge break playback */ }
    }

    let quick = 0;                      // polls in a row answered at once
    let polls = 0;
    let pollLive = false;               // a poll is in flight (the heartbeat checks)
    let pollAt = 0;
    // ── The mailbox: what the bridge wants, read through a stylesheet ─────────
    // A woken poll says only THAT something is waiting — its reply is opaque (no-cors). /mailbox.css sets
    // `#qs-mailbox::after { content: "<base64 JSON>" }`, and computed style is readable whatever origin the
    // sheet came from, so this loads it and reads it back: { restyle: seq?, play: { seq, query, kind }? }.
    // An older bridge has no mailbox (the sheet fails to load) → null, and the caller restyles as before.
    let lastPlaySeq = 0;
    function checkMail() {
        return new Promise(done => {
            let box = document.getElementById("qs-mailbox");
            if (!box) {
                box = document.createElement("div");
                box.id = "qs-mailbox";
                box.style.cssText = "position:fixed;width:0;height:0;overflow:hidden;opacity:0;pointer-events:none";
                document.body.appendChild(box);
            }
            const link = document.createElement("link");
            link.rel = "stylesheet";
            link.href = URL + "mailbox.css?v=" + Date.now();
            let settled = false;
            const finish = mail => { if (settled) return; settled = true; link.remove(); done(mail); };
            link.onload = () => {
                let mail = {};
                try {
                    const raw = getComputedStyle(box, "::after").content || "";
                    const b64 = raw.replace(/^["']|["']$/g, "");
                    if (b64 && b64 !== "none") mail = JSON.parse(decodeURIComponent(escape(atob(b64))));
                } catch (e) { mail = {}; }
                finish(mail);
            };
            link.onerror = () => finish(null);
            setTimeout(() => finish(null), 4000);
            document.head.appendChild(link);
        });
    }

    // ── "Play X": Spotify's own search, then play it ──────────────────────────
    // Through the app's own GraphQL, so nothing outside the app is asked (the public Web API with this
    // client's token answers 429; CosmosAsync to api.spotify.com answers "Resolver not found!" on
    // Spicetify 2.45 — both measured 2026-10-24).
    //
    // WHICH query matters: `searchDesktop` (the search page's) is registered by xpui-routes-search.js, a
    // chunk Spotify loads only once its search page has been opened — until then the definition doesn't
    // exist. `searchSuggestions` (the top bar's type-ahead) is registered by xpui-modules.js at start, so
    // it's always there; its variables are copied from Spotify 1.3.4's own call. searchDesktop is the
    // second try, for when that chunk happens to be loaded. The hit is found by its URI's kind anywhere in
    // the answer (topResultsV2.itemsV2[].item.data.uri today), so a reshuffled response still works.
    const SECTION = { track: "tracksV2", album: "albumsV2", artist: "artists", playlist: "playlists" };
    function findUri(node, kind, depth) {
        if (!node || typeof node !== "object" || depth > 10) return null;
        if (typeof node.uri === "string" && node.uri.indexOf("spotify:" + kind + ":") === 0) {
            const artists = node.artists && node.artists.items
                ? node.artists.items.map(a => a && a.profile && a.profile.name).filter(Boolean) : [];
            const name = node.name || (node.profile && node.profile.name) || "";
            return { uri: node.uri, title: name + (artists.length ? " — " + artists.join(", ") : "") };
        }
        for (const k of Object.keys(node)) {
            const r = findUri(node[k], kind, depth + 1);
            if (r) return r;
        }
        return null;
    }
    async function searchUri(query, kind, notes) {
        const G = Spicetify.GraphQL;
        if (!G || !G.Request || !G.Definitions) { notes.push("no Spicetify.GraphQL"); return null; }
        const tries = [];
        if (G.Definitions.searchSuggestions)
            tries.push(["searchSuggestions", { query: query, limit: 30, numberOfTopResults: 30, offset: 0,
                                               includeAuthors: false, includeAlbumPreReleases: false,
                                               includeEpisodeContentRatingsV2: false }]);
        if (G.Definitions.searchDesktop)
            tries.push(["searchDesktop", { searchTerm: query, offset: 0, limit: 10, numberOfTopResults: 5,
                                           includeAudiobooks: false, includePreReleases: false,
                                           includeLocalConcertsField: false, includeArtistHasConcertsField: false,
                                           includeAuthors: false }]);
        if (tries.length === 0) notes.push("no search definition loaded");
        for (const [name, vars] of tries) {
            try {
                const res = await G.Request(G.Definitions[name], vars);
                if (res && res.errors && res.errors.length) { notes.push(name + ": " + String(res.errors[0].message || "error").slice(0, 80)); continue; }
                const sv = res && res.data && res.data.searchV2;
                const hit = findUri(sv && sv[SECTION[kind]], kind, 0) || findUri(sv, kind, 0);
                if (hit) return hit;
                notes.push(name + ": no " + kind);
            } catch (e) {
                notes.push(name + ": " + String((e && e.message) || e).slice(0, 80));
            }
        }
        return null;
    }
    async function playByName(cmd) {
        let hit = null, error = "";
        const notes = [];
        try {
            const kind = SECTION[cmd.kind] ? cmd.kind : "track";
            hit = await searchUri(String(cmd.query || ""), kind, notes);
            if (hit) await Spicetify.Player.playUri(hit.uri);
            // "nothing found" exactly when every search ran and none had a hit; anything else says why.
            else error = notes.every(n => / no [a-z]+$/.test(n)) && notes.length ? "nothing found" : notes.join("; ");
        } catch (e) {
            error = String((e && e.message) || e).slice(0, 160);
        }
        try {
            fetch(URL, {
                method: "POST", mode: "no-cors", keepalive: true,
                headers: { "Content-Type": "text/plain" },
                body: JSON.stringify({ type: hit && !error ? "played" : "play-failed", seq: cmd.seq,
                                       uri: hit ? hit.uri : "", title: hit ? hit.title : "", error: error })
            }).catch(() => {});
        } catch (e) { /* the bridge times the request out */ }
    }

    // What a woken poll was for: the mailbox says; no mailbox (an older bridge) means a restyle.
    function handleWake() {
        return checkMail().then(mail => {
            const jobs = [];
            if (!mail || mail.restyle) jobs.push(restyle());
            if (mail && mail.play && mail.play.seq !== lastPlaySeq) {
                lastPlaySeq = mail.play.seq;
                jobs.push(playByName(mail.play));
            }
            return Promise.all(jobs);
        });
    }

    function pollEvents() {
        polls++;
        const t0 = performance.now();
        const mine = polls;
        pollLive = true;
        pollAt = t0;
        const ctl = new AbortController();
        const deadline = setTimeout(() => ctl.abort(), EVENT_HOLD_MS + 15000);
        fetch(URL + "events", {
            method: "POST", mode: "no-cors", keepalive: true,
            headers: { "Content-Type": "text/plain" }, body: "poll", signal: ctl.signal
        }).then(() => {
            clearTimeout(deadline);
            if (mine !== polls) return;     // superseded by the heartbeat's restart
            pollLive = false;
            const took = performance.now() - t0;
            if (polls <= 2) say({ event: "poll-settled", ms: Math.round(took) });
            quick = took < 250 ? quick + 1 : 0;
            // An instant answer is an event — unless they come in a run, which is an
            // older bridge with no /events refusing the body. Never spin on that.
            if (quick >= 3) setTimeout(pollEvents, 3000);
            else if (took < EVENT_HOLD_MS - 5000) handleWake().then(pollEvents, pollEvents);
            else pollEvents();
        }).catch(e => {
            clearTimeout(deadline);
            if (mine !== polls) return;
            pollLive = false;
            pollFailures++;
            if (pollFailures <= 3 || pollFailures % 20 === 0)
                say({ event: "poll-failed", n: pollFailures,
                      ms: Math.round(performance.now() - t0),
                      error: String((e && e.name) || "") + ": " + String((e && e.message) || e).slice(0, 160) });
            setTimeout(pollEvents, 3000);   // the bridge is down (a shell restarting)
        });
    }
    pollEvents();                       // may vanish at load; the heartbeat restarts it

    // ── A way to actually TEST this ───────────────────────────────────────────
    // Every failure so far has been diagnosed by inference from a missing line in the
    // shell's IPC output, which is how a wrong token API and a wrong version header each
    // cost a full cycle. This runs the real request and hands back the raw status and
    // response, so the next question is answered by measurement.
    //
    //   spicetify enable-devtools     (once)
    //   then in Spotify's console:    await __qsBridge.test()
    window.__qsBridge = {
        test: async function () {
            const uri = trackInfo().trackUri;
            const token = await accessToken();
            if (!uri)   return { ok: false, why: "no track uri — Player.data not ready" };
            if (!token) return { ok: false, why: "no access token" };

            const res = await fetch(LYRICS_API, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "SpicyLyrics-Version": CLIENT_VERSION,
                    "X-mode": "2",
                    "SpicyLyrics-WebAuth": "Bearer " + token
                },
                body: JSON.stringify({
                    queries: [{
                        operation: "lyrics",
                        variables: { id: uri.split(":")[2], auth: "SpicyLyrics-WebAuth" }
                    }],
                    client: { version: CLIENT_VERSION }
                })
            });

            const text = await res.text();

            // On FAILURE the body is a server message and is what we need to read. On
            // SUCCESS it is the lyrics themselves — so report their shape instead, which
            // is all a diagnostic needs and keeps the words out of logs and pasted output.
            if (res.ok) {
                let shape = "unparseable";
                try {
                    const body = JSON.parse(text);
                    const jobs = (body && body.queries) || [];
                    const data = jobs.length ? (jobs[0].result && jobs[0].result.data) : null;
                    shape = data
                        ? { type: data.Type, source: data.source,
                            lines: (data.Content || []).length }
                        : "no payload in envelope";
                } catch (e) { /* leave as unparseable */ }

                return { ok: true, status: res.status, uri: uri,
                         version: CLIENT_VERSION, payload: shape };
            }

            return { ok: false, status: res.status, uri: uri,
                     version: CLIENT_VERSION, body: text.slice(0, 500) };
        },
        state: function () {
            return { lastUri: lastUri, lyricsHaveFor: lyricsHaveFor,
                     lyricsTriedFor: lyricsTriedFor, attempts: lyricsAttempts,
                     version: CLIENT_VERSION };
        }
    };

    console.log("[quickshell-bridge] active on port " + PORT);
})();
