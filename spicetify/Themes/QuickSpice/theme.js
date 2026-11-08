// QuickSpice — the two things CSS can't see.
//
//   data-qs-playing  on <html> while a track plays, so the seek bar's wave only travels
//                    when there is something to travel with (CSS has no idea what the
//                    player is doing).
//   data-qs-light    on <html> when the palette's base is light, for the roles the shell
//                    weakens on a light palette (PaletteRoles._lightMode).
//
// Nothing here touches Spotify's own DOM: no node is added, moved or re-texted. React owns
// those nodes, and a script that rewrites one makes the next render throw or go stale.
// An attribute on <html> is the one thing it never reads.
//
// ── Runs before Spicetify exists ──────────────────────────────────────────────
// theme.js is injected as a plain script, ahead of the `Spicetify` global, so anything
// that names it outright (`!Spicetify`) throws a ReferenceError and the rest never runs.
// `typeof` is safe on an undeclared name; the player appears later still, so retry.
(function () {
  "use strict";

  const root = document.documentElement;

  function setLight() {
    // The same test the shell's contrast code uses, on --spice-main (the base).
    const raw = getComputedStyle(root).getPropertyValue("--spice-main").trim().replace("#", "");
    if (raw.length !== 6) return;
    const lin = (i) => {
      const s = parseInt(raw.substr(i, 2), 16) / 255;
      return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
    };
    const lum = 0.2126 * lin(0) + 0.7152 * lin(2) + 0.0722 * lin(4);
    root.toggleAttribute("data-qs-light", lum > 0.4);
  }

  // A palette change re-fetches colors.css (the bridge's /restyle), which swaps the
  // stylesheet under us — re-read the base whenever a stylesheet <link> is added.
  new MutationObserver(setLight).observe(document.head, { childList: true });
  setLight();

  // The play cookie turns while a track plays. CookieButton settles it onto the nearest
  // petal when it stops, so it comes to rest upright and symmetric rather than at a random
  // tilt. CSS can't read the angle a running animation has reached; this can, and hands the
  // two angles to a settle animation (the shape repeats every 360/8 degrees, so snapping to
  // a multiple of that is invisible). The turn is the body's `rotate` ("123.4deg", or "none").
  const PETAL = 360 / 8;
  function settlePlayButton() {
    const btn = document.querySelector('[data-testid="control-button-playpause"]');
    if (!btn) return;
    const raw = getComputedStyle(btn.firstElementChild || btn, "::before").rotate;
    const from = parseFloat(raw) || 0;
    btn.style.setProperty("--qs-settle-from", from + "deg");
    btn.style.setProperty("--qs-settle-to", Math.round(from / PETAL) * PETAL + "deg");
    btn.classList.add("qs-settle");
  }
  function releasePlayButton() {
    const btn = document.querySelector('[data-testid="control-button-playpause"]');
    if (btn) btn.classList.remove("qs-settle");
  }

  function setPlaying() {
    let playing = false;
    try { playing = !!Spicetify.Player.isPlaying(); } catch (e) { /* player not up yet */ }
    const was = root.hasAttribute("data-qs-playing");
    if (playing === was) return;
    if (playing) releasePlayButton();
    else settlePlayButton();
    root.toggleAttribute("data-qs-playing", playing);
  }


  // ═══ The cover's ring of level bars (components/CookieCover.qml) ═══════════════════
  // The media panel stands a ring of bars off its cookie, driven by cava. Spotify's page can
  // neither run cava nor hear anything, so the shell's bridge (scripts/spotify-bridge.py) runs
  // the same cava and streams its frames at GET /spectrum. This draws them on a canvas of its own
  // — appended to <body>, outside React's tree, and laid over the cover — while a track plays.
  //
  // The geometry is cookie.js's: each bar starts a gap OUTSIDE the cookie's edge at its own
  // angle, and the cookie turns underneath it, so the inner ends breathe as petals pass while
  // the bars themselves stand still. Silence is a ring of dots, never a gap.
  const BARS = 32;
  const RING = { petals: 8, depth: 0.13, gap: 3, reach: 7, thick: 2 };
  const levels = new Array(BARS).fill(0);
  let target = new Array(BARS).fill(0);
  let ctl = null, retry = 0, raf = 0, ringTimer = 0, canvas = null, ringColor = null, ringGeo = null;
  const ringClock = { t0: 0, ms: 0, running: false, playing: false };

  function bridgePort() {
    // 47821 is the bridge's own default; the override exists to test against a private one.
    try { return Number(localStorage.getItem("qs-bridge-port")) || 47821; } catch (e) { return 47821; }
  }
  const wantRing = () => root.hasAttribute("data-qs-playing") && document.visibilityState === "visible";

  async function connectSpectrum() {
    if (ctl) return;
    ctl = new AbortController();
    try {
      const res = await fetch("http://127.0.0.1:" + bridgePort() + "/spectrum", { signal: ctl.signal });
      if (!res.ok || !res.body) throw new Error("no spectrum");
      const reader = res.body.getReader();
      const dec = new TextDecoder();
      let buf = "";
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf("\n\n")) >= 0) {
          const ev = buf.slice(0, i);
          buf = buf.slice(i + 2);
          if (ev.startsWith("data: ")) {
            const v = ev.slice(6).split(",").map(Number);
            if (v.length >= BARS) target = v;
          }
        }
      }
    } catch (e) { /* bridge not running, or we hung up on purpose */ }
    ctl = null;
    target = new Array(BARS).fill(0);
    // Back off: a bridge that is not there should not be asked every frame.
    if (wantRing()) { clearTimeout(retry); retry = setTimeout(syncRing, 8000); }
  }
  function disconnectSpectrum() {
    clearTimeout(retry);
    if (ctl) ctl.abort();
    ctl = null;
  }

  // Scallop's radius at a shape-local angle (services/cookie.js radiusAt).
  const radiusAt = (a, rMax) => {
    const amp = rMax * RING.depth;
    return (rMax - amp) + amp * (0.5 + 0.5 * Math.cos(RING.petals * a));
  };

  // ── A frame when one is wanted, never one per vsync ─────────────────────────────
  // A loop that asks for EVERY frame and skips most of them still makes the page render at the
  // display's rate — 165 times a second on a 165Hz screen, each one a full lifecycle pass — for a
  // canvas that draws at 30 (or 20) fps. Measured: this loop and the drift's each asked ~97 times a
  // second. So a timer waits out the interval and only then asks for the next frame.
  function nextRing(ms) {
    ringTimer = setTimeout(() => { ringTimer = 0; raf = requestAnimationFrame(drawRing); }, ms);
  }

  function drawRing(now) {
    raf = 0;
    // ── Everything layout-shaped is read on a slow clock ─────────────────────────────
    // Finding the elements, their size and centre, and whether they are showing all change only with
    // layout. Done per frame, each of those reads forces a style recalculation (the cover is animating,
    // so styles are always dirty) — measured as the bulk of this page's main-thread cost. So: every
    // 400ms. The button holds the cookie and turns, so its bounding box swells with the angle — about
    // its own centre, which is all that is read from it; the size is the unturned one.
    if (!ringGeo || now - ringGeo.t > 400) {
      const slot = document.querySelector(".main-nowPlayingWidget-coverArtContainer");
      const widget = document.querySelector(".main-nowPlayingWidget-nowPlaying");
      if (!slot || !widget || slot.offsetParent === null) {
        ringGeo = { t: now, hidden: true };
      } else {
        const r = slot.getBoundingClientRect();
        const rMax = slot.offsetWidth / 2;                  // the clip-path's own 50%
        const side = Math.ceil((rMax + RING.gap + RING.reach + RING.thick) * 2);
        ringGeo = { t: now, slot, rMax, side, left: r.x + r.width / 2 - side / 2, top: r.y + r.height / 2 - side / 2 };
      }
      if (canvas) {
        const show = !ringGeo.hidden;
        if (show) { canvas.style.left = ringGeo.left + "px"; canvas.style.top = ringGeo.top + "px"; }
        if (canvas.style.display !== (show ? "block" : "none")) canvas.style.display = show ? "block" : "none";
      }
    }
    if (ringGeo.hidden) {
      // Not there yet (the player mounts late) — look again in a second rather than every frame.
      if (wantRing() && !ringTimer) nextRing(1000);
      return;
    }
    if (!canvas) {
      canvas = document.createElement("canvas");
      canvas.id = "qs-cava";
      canvas.style.cssText = "position:fixed;pointer-events:none;z-index:4";
      root.appendChild(canvas);
      ringGeo.t = 0;                                         // place it on the next frame
    }
    const { rMax, side, slot } = ringGeo;
    const dpr = window.devicePixelRatio || 1;
    if (canvas.width !== Math.round(side * dpr)) {
      canvas.width = canvas.height = Math.round(side * dpr);
      canvas.style.width = canvas.style.height = side + "px";
    }

    // The cookie's angle (the scallop's own box turns: user.css, qs-spin). getAnimations() flushes
    // style, so it is read ONCE, then advanced by the clock: the animation is linear, 60s a turn, so
    // its time is a sum. Re-read every 4s to stay true (and on play/pause, when it stops or resumes).
    const playing = wantRing();
    if (!ringClock.t0 || now - ringClock.t0 > 4000 || ringClock.playing !== playing) {
      const turn = slot.getAnimations().find((a) => a.animationName === "qs-spin");
      ringClock.ms = turn ? Number(turn.currentTime) % 60000 : ringClock.ms;
      ringClock.running = !!turn && turn.playState === "running";
      ringClock.t0 = now;
      ringClock.playing = playing;
    }
    const phaseMs = ringClock.running ? ringClock.ms + (now - ringClock.t0) : ringClock.ms;
    const phase = ((phaseMs % 60000) / 60000) * 2 * Math.PI;
    if (!ringColor) ringColor = getComputedStyle(root).getPropertyValue("--qs-focus").trim() || "#fff";
    const accent = ringColor;

    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, side, side);
    ctx.strokeStyle = accent;
    ctx.lineWidth = RING.thick;
    ctx.lineCap = "round";

    let alive = false;
    for (let i = 0; i < BARS; i++) {
      // The shell shapes the spectrum with an exponent before drawing it.
      const want = Math.pow(Math.max(0, Math.min(1, target[i] || 0)), 1.25);
      levels[i] += (want - levels[i]) * 0.35;
      if (levels[i] > 0.004) alive = true;
      const th = i * 2 * Math.PI / BARS - Math.PI / 2;
      const r0 = radiusAt(th - phase, rMax) + RING.gap;
      const len = Math.max(RING.thick, levels[i] * RING.reach);
      const c = Math.cos(th), s = Math.sin(th);
      ctx.beginPath();
      ctx.moveTo(side / 2 + c * r0, side / 2 + s * r0);
      ctx.lineTo(side / 2 + c * (r0 + len), side / 2 + s * (r0 + len));
      ctx.stroke();
    }
    // Keep going while the track plays (the cookie turns) or the bars are still settling: 30fps is
    // plenty for a bar that follows a 30fps spectrum.
    if (wantRing() || alive) nextRing(30);
  }

  function syncRing() {
    if (wantRing()) { connectSpectrum(); } else { disconnectSpectrum(); }
    if (!raf && !ringTimer) raf = requestAnimationFrame(drawRing);
  }
  document.addEventListener("visibilitychange", syncRing);
  new MutationObserver(syncRing).observe(root, { attributes: true, attributeFilter: ["data-qs-playing"] });


  // ═══ Search — borrowed from the shell's launcher field ═════════════════════════════
  // LauncherField / TypedPlaceholder: an empty field that TYPES its own hints (a key in the
  // accent, then what it does). Spotify's field takes `artist:` `album:` `track:` `genre:`
  // `year:`, so those are the prefixes it teaches. The typed line is an element of our own
  // appended to <html> and laid over the field; nothing of Spotify's is touched.
  const HINTS = [["artist:", "only artists"], ["album:", "by album"], ["track:", "one song"],
                 ["genre:", "a style"], ["year:", "1990-2000"]];
  const sInput = () => document.querySelector(".main-globalNav-searchInputSection input");
  const sSection = () => document.querySelector(".main-globalNav-searchInputSection");
  let typed = null, bound = null;

  // The typed hint: one timer whose interval is the current phase's delay, exactly
  // TypedPlaceholder's — hold long enough to read, erase faster than it was typed.
  // It types only while the field is in use (pointed at, or focused) — the launcher's hints type while
  // the launcher is OPEN, and Spotify's field is always on screen: typing there forever was ~40 text
  // writes a second, each one a frame, for as long as Spotify ran. At rest the whole hint stands still.
  const typer = { idx: 0, n: 0, phase: "gap", timer: 0, live: false };
  const DELAY = { type: 42, hold: 2200, erase: 18, gap: 380 };
  const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ── Geometry is read twice a second, never per tick ──────────────────────────────
  // The ticker below fires up to 55 times a second (a character every 18-42ms). Reading layout in
  // each tick (getBoundingClientRect, offsetParent) forced a style recalculation every time —
  // measured at ~250ms of every second, a quarter of the page's main thread. Where the field is
  // changes only when the window does, so it is read on a slow clock, on resize, and on input.
  const geo = { ok: false };
  function refreshGeo() {
    const sec = sSection();
    const inp = bound;
    if (!sec || !inp || !inp.isConnected) { geo.ok = false; return; }
    const r = sec.getBoundingClientRect();
    geo.ok = r.width > 220 && sec.offsetParent !== null;
    if (!geo.ok || !typed) return;
    // Where Spotify's own placeholder sits: after the magnifier, centred on the pill.
    const icon = sec.querySelector("button");
    typed.style.left = ((icon ? icon.getBoundingClientRect().right : r.left + 44) + 6) + "px";
    typed.style.top = r.top + "px";
    typed.style.height = r.height + "px";
  }
  let typedShown = false;
  function renderTyped() {
    if (!typed) {
      typed = document.createElement("div");
      typed.id = "qs-typed";
      typed.innerHTML = '<span class="lead">Search Spotify</span><span class="sep">  ·  </span><span class="key"></span><span class="txt"></span>';
      root.appendChild(typed);
      refreshGeo();
    }
    const open = !!(geo.ok && bound && bound.isConnected && !bound.value);
    if (open !== typedShown) { typedShown = open; typed.style.display = open ? "flex" : "none"; }
    if (!open) return false;
    const h = HINTS[typer.idx % HINTS.length];
    const full = h[0] + " " + h[1];
    const shown = reduced() || !typer.live ? full : full.slice(0, typer.n);
    const key = shown.slice(0, h[0].length), txt = shown.length > h[0].length ? shown.slice(h[0].length) : "";
    const k = typed.querySelector(".key"), t = typed.querySelector(".txt");
    if (k.textContent !== key) k.textContent = key;
    if (t.textContent !== txt) t.textContent = txt;
    return full;
  }
  function tickTyped() {
    const full = renderTyped();
    if (full === false) { typer.timer = setTimeout(tickTyped, 400); return; }   // not visible: poll slowly
    if (reduced() || !typer.live) { typer.timer = setTimeout(tickTyped, 2000); return; }
    if (typer.phase === "type") { typer.n++; if (typer.n >= full.length) typer.phase = "hold"; }
    else if (typer.phase === "hold") typer.phase = "erase";
    else if (typer.phase === "erase") { typer.n--; if (typer.n <= 0) { typer.n = 0; typer.phase = "gap"; } }
    else { typer.idx = (typer.idx + 1) % HINTS.length; typer.phase = "type"; }
    typer.timer = setTimeout(tickTyped, DELAY[typer.phase]);
  }

  function setLive() {
    const sec = bound && bound.closest(".main-globalNav-searchInputSection");
    const live = !!sec && (document.activeElement === bound || sec.matches(":hover"));
    if (live === typer.live) return;
    typer.live = live;
    clearTimeout(typer.timer);
    if (live) { typer.n = 0; typer.phase = "type"; }
    tickTyped();
  }
  function bindSearch() {
    const i = sInput();
    if (!i || i === bound) return;
    bound = i;
    i.addEventListener("input", () => { refreshGeo(); renderTyped(); });
    i.addEventListener("focus", setLive);
    i.addEventListener("blur", setLive);
    const sec = i.closest(".main-globalNav-searchInputSection");
    if (sec) { sec.addEventListener("pointerenter", setLive); sec.addEventListener("pointerleave", setLive); }
    refreshGeo();
    typer.live = false;
    setLive();
    if (!typer.timer) tickTyped();
  }
  // The field is remounted when Spotify changes page, so look for it again — but only when the one
  // we hold has gone: this observer sees every DOM change in the app.
  let bindQueued = false;
  new MutationObserver(() => {
    if (bindQueued || (bound && bound.isConnected)) return;
    bindQueued = true;
    requestAnimationFrame(() => { bindQueued = false; bindSearch(); });
  }).observe(root, { childList: true, subtree: true });
  window.addEventListener("resize", () => { refreshGeo(); renderTyped(); });
  setInterval(refreshGeo, 800);
  bindSearch();


  // ═══ The cookie field (services/Drift, drift.js, DriftShapes) ═══════════════════════
  // The shell lets soft Scallops drift in each panel — over the panel's fill, under its content —
  // and the same field shows in the bar and the gaps, so a shape leaving one panel is the one
  // entering the next. The model here is drift.js's, constant for constant: 28 shapes on a 1000×800
  // plane that repeats, so a window of any size sees the same density; ONE drift velocity for the
  // whole field (shapes at different speeds catch each other and pile up — measured in the shell);
  // depth, spread evenly, sets a shape's size, opacity and wander (a bounded sinusoid, so it can
  // never accumulate); every third has a faint outline. No separation pass: with a shared velocity
  // and a jittered-grid start the arrangement cannot reshuffle, which is all that pass guarded.
  // (The per-shape turn, breath and wander are generated still, so the seeded layout stays the same,
  // but only the positions, sizes, tones and a fixed turn are drawn — see below.)
  const DRIFT = {
    W: 1000, H: 800, N: 28, SPEED: 6,
    FORMS: [[8, 0], [4, .20], [6, .14], [7, .12], [9, .10], [12, .07], [5, .22], [8, .24], [9, .12], [6, .20]],
    SIZE: [28, 112], ALPHA: [.07, .16], WANDER: [10, 26], TURN: 10,
    BOOST: 1,
  };
  const field = (() => {
    // mulberry32, as drift.js — the same field twice, so a screenshot is repeatable.
    let a = 20261010;
    const rand = () => {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    const lerp = (x, y, k) => x + (y - x) * k;
    const { W, H, N } = DRIFT;
    const cols = Math.max(1, Math.ceil(Math.sqrt(N * W / H)));
    const rows = Math.max(1, Math.ceil(N / cols));
    const cells = Array.from({ length: cols * rows }, (_, i) => i);
    for (let k = cells.length - 1; k > 0; k--) {          // dealt out at random (Fisher–Yates)
      const r = Math.floor(rand() * (k + 1));
      [cells[k], cells[r]] = [cells[r], cells[k]];
    }
    const cw = W / cols, ch = H / rows;
    const current = rand() * Math.PI * 2;                 // the way the whole field drifts
    const out = [];
    for (let i = 0; i < N; i++) {
      const depth = N > 1 ? i / (N - 1) : .5;
      const dir = rand() < .5 ? -1 : 1;
      const form = DRIFT.FORMS[Math.floor(rand() * DRIFT.FORMS.length)];
      const cell = cells[i % cells.length];
      out.push({
        x: ((cell % cols) + .5 + (rand() - .5) * .4) * cw,
        y: (Math.floor(cell / cols) + .5 + (rand() - .5) * .4) * ch,
        r: rand() * 360,
        vx: Math.cos(current) * DRIFT.SPEED, vy: Math.sin(current) * DRIFT.SPEED,
        vr: dir * lerp(2, DRIFT.TURN, rand()),
        size: lerp(DRIFT.SIZE[0], DRIFT.SIZE[1], depth),
        alpha: lerp(DRIFT.ALPHA[0], DRIFT.ALPHA[1], depth),
        points: form[0], petal: form[1],
        tone: Math.floor(rand() * 4),
        phase: rand() * Math.PI * 2,
        wp: rand() * Math.PI * 2, ww: lerp(.12, .35, rand()), wa: lerp(DRIFT.WANDER[0], DRIFT.WANDER[1], depth),
        outlined: i % 3 === 0,
      });
    }
    return out;
  })();

  // ── Drawn once, moved by the compositor ──────────────────────────────────────────
  // The first two versions were a full-window canvas redrawn 20 times a second on Spotify's main
  // thread. Spotify keeps that thread busy (measured: ~980ms of every second while a track plays,
  // the theme or not), so the field got whatever frames were left — it stuttered — and its own jank
  // guard switched it off, three strikes and gone for the session: "the cookies disappear".
  // Now nothing is drawn per frame. The field is ONE tile (W×H, the shapes at their seeded places,
  // turned, sized and tinted, every third outlined), rendered once as an SVG and repeated as the
  // background of a layer one tile larger than the window each way. That layer slides by exactly
  // one tile and starts over — a `translate`, so the compositor runs it and a busy page cannot stall
  // or stop it. The one thing a single tile cannot keep is each shape turning on its own; the shared
  // drift, plus a slow wander of the whole field, is the motion.
  //
  // The shell's order is fill, shapes, content. So the field's layer (under the app) carries the
  // panels' fills too — a rounded rect per panel, kept on the panel by a ResizeObserver, not a timer —
  // and the shapes over them; the panels give up their own background while it runs
  // (html[data-qs-field], user.css) and keep their border, shadow and content above it.
  const PANELS = [".Root__nav-bar", ".Root__main-view", ".Root__right-sidebar", ".Root__now-playing-bar",
                  ".Root__globalNav.searchInputCollapsed"];
  let fieldEl = null, tileKey = "";
  const fills = new Map();                                // panel element → its fill rect
  const ro = new ResizeObserver(() => placeFills());

  // The drift as a whole number of tiles, so the loop is seamless: of the eight ways one tile can
  // go (across, down, or corner to corner), the one nearest the field's seeded current.
  const LOOP = (() => {
    const want = Math.atan2(field[0].vy, field[0].vx);
    let best = null;
    for (const kx of [-1, 0, 1]) for (const ky of [-1, 0, 1]) {
      if (!kx && !ky) continue;
      const d = Math.abs(Math.atan2(Math.sin(Math.atan2(ky * DRIFT.H, kx * DRIFT.W) - want),
                                    Math.cos(Math.atan2(ky * DRIFT.H, kx * DRIFT.W) - want)));
      if (!best || d < best.d) best = { d, kx, ky };
    }
    const dist = Math.hypot(best.kx * DRIFT.W, best.ky * DRIFT.H);
    return { x: best.kx * DRIFT.W, y: best.ky * DRIFT.H, s: dist / DRIFT.SPEED };
  })();

  // A scallop's outline (Scallop.qml), turned and sized, as SVG path data about its centre.
  function scallop(s) {
    const R = s.size / 2, rot = s.r * Math.PI / 180, steps = Math.max(48, s.points * 8);
    let d = "";
    for (let i = 0; i < steps; i++) {
      const th = i / steps * Math.PI * 2;
      const r = R * ((1 - s.petal) + s.petal * (.5 + .5 * Math.cos(s.points * th)));
      d += (i ? "L" : "M") + (r * Math.cos(th + rot)).toFixed(1) + " " + (r * Math.sin(th + rot)).toFixed(1);
    }
    return d + "Z";
  }

  // The tile, in the palette's colours (an image can't read CSS, so they are baked in — and the tile
  // is rebuilt when the palette changes). The shell's four tones: primary, focus, outline, fg.
  function buildTile() {
    const cs = getComputedStyle(root);
    const hex = (name, fb) => {
      const m = /^#?([0-9a-f]{6})/i.exec(cs.getPropertyValue(name).trim());
      const n = parseInt(m ? m[1] : fb, 16);
      return (n >> 16 & 255) + "," + (n >> 8 & 255) + "," + (n & 255);
    };
    const text = hex("--spice-text", "ffffff");
    const tones = [[hex("--spice-button", "888888"), 1], [hex("--spice-button-active", "888888"), 1], [text, .22], [text, 1]];
    const key = JSON.stringify(tones);
    if (key === tileKey) return null;
    tileKey = key;
    const { W, H } = DRIFT;
    let body = "";
    for (const s of field) {
      const [rgb, ta] = tones[s.tone];
      const a = s.alpha * DRIFT.BOOST * ta, R = s.size / 2, d = scallop(s);
      const stroke = s.outlined
        ? ' stroke="rgb(' + rgb + ')" stroke-opacity="' + Math.min(1, a * 3.4).toFixed(3) + '" stroke-width="1"' : "";
      // A shape across an edge is drawn on both sides of it, so the repeated tile has no seams.
      for (const dx of [-W, 0, W]) for (const dy of [-H, 0, H]) {
        const cx = s.x + dx, cy = s.y + dy;
        if (cx + R < 0 || cy + R < 0 || cx - R > W || cy - R > H) continue;
        body += '<path transform="translate(' + cx.toFixed(1) + " " + cy.toFixed(1) + ')" d="' + d +
                '" fill="rgb(' + rgb + ')" fill-opacity="' + a.toFixed(3) + '"' + stroke + "/>";
      }
    }
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + W + '" height="' + H + '" viewBox="0 0 ' + W + " " + H + '">' + body + "</svg>";
    return 'url("data:image/svg+xml,' + encodeURIComponent(svg) + '")';
  }
  function refreshTile() {
    if (!fieldEl) return;
    const url = buildTile();
    if (url) fieldEl.style.setProperty("--qs-field-tile", url);
  }

  // Each panel's fill, where the panel is. Called by the ResizeObserver (a panel changed size — and
  // when one moves, a neighbour has changed size) and by the window's resize; the set of panels is
  // re-read on a slow clock, since the side panel comes and goes.
  function placeFills() {
    for (const [el, rect] of fills) {
      const r = el.getBoundingClientRect();
      const show = el.isConnected && r.width > 8 && r.height > 8;
      rect.style.display = show ? "" : "none";
      if (!show) continue;
      const t = "translate(" + r.x + "px, " + r.y + "px)";
      if (rect.style.transform !== t) rect.style.transform = t;
      if (rect.style.width !== r.width + "px") rect.style.width = r.width + "px";
      if (rect.style.height !== r.height + "px") rect.style.height = r.height + "px";
    }
  }
  function syncPanels() {
    if (!fieldEl) return;
    const now = new Set(PANELS.map((sel) => document.querySelector(sel)).filter(Boolean));
    let changed = false;
    for (const [el, rect] of fills) {
      if (now.has(el)) continue;
      ro.unobserve(el); rect.remove(); fills.delete(el); changed = true;
    }
    for (const el of now) {
      if (fills.has(el)) continue;
      const rect = document.createElement("div");
      rect.className = "qs-fill";
      fieldEl.insertBefore(rect, fieldEl.querySelector(".qs-wander"));
      fills.set(el, rect); ro.observe(el); changed = true;
    }
    if (changed) placeFills();
  }

  function buildField() {
    if (fieldEl) return;
    fieldEl = document.createElement("div");
    fieldEl.id = "qs-field";
    fieldEl.innerHTML = '<div class="qs-wander"><div><div class="qs-grid"></div></div></div>';
    fieldEl.style.setProperty("--qs-drift-x", -LOOP.x + "px");
    fieldEl.style.setProperty("--qs-drift-y", -LOOP.y + "px");
    fieldEl.style.setProperty("--qs-drift-t", LOOP.s.toFixed(1) + "s");
    root.insertBefore(fieldEl, root.firstChild);
    refreshTile();
    syncPanels();
    root.setAttribute("data-qs-field", "");
    setInterval(syncPanels, 1000);
    window.addEventListener("resize", placeFills);
  }
  new MutationObserver(() => { ringColor = null; refreshTile(); }).observe(document.head, { childList: true });

  // Not at script start: Spotify is busy building its UI then. Wait for the page to have loaded and
  // its main view to exist (the panels the fills follow).
  (function whenReady() {
    if (document.readyState !== "complete" || !document.querySelector(".Root__main-view .main-view-container")) {
      setTimeout(whenReady, 500);
      return;
    }
    buildField();
  })();

  // The cover, as a CSS variable. Spotify hides the cover whenever a track has a Canvas clip,
  // and on a Spotify that cannot decode the clip (Canvas is H.264) the panel is left empty;
  // user.css draws this in that case. A variable on <html> because nothing else here may
  // touch Spotify's own DOM.
  function setArt() {
    let url = "";
    try {
      const m = Spicetify.Player.data.item.metadata || {};
      const uri = m.image_xlarge_url || m.image_large_url || m.image_url || "";
      const id = String(uri).split(":").pop();
      if (id && /^[0-9a-f]+$/i.test(id)) url = "https://i.scdn.co/image/" + id;
    } catch (e) { /* player not up yet */ }
    if (url) root.style.setProperty("--qs-art", 'url("' + url + '")');
    else root.style.removeProperty("--qs-art");
  }

  // ═══ Canvas — the looping clip, relayed through the shell's bridge ══════════════════
  // Spotify's Linux build cannot decode H.264 (its Chromium's ffmpeg has no proprietary codecs,
  // linked into libcef.so), and every Canvas clip is H.264 — so Spotify never shows one. Where that
  // is so (and only there: a Spotify that CAN decode keeps its own), this looks the track's clip up
  // and hands the bridge's re-encoded copy (scripts/spotify-bridge.py, GET /canvas: an animated
  // AVIF) to user.css as `--qs-canvas`. An image, not a <video>: a CSS background lives in the
  // panel — it scrolls and clips with it — and touches nothing of Spotify's. It is preloaded first,
  // and only then flagged (`data-qs-canvas`), so the clip fades in over the cover rather than
  // popping in late; the cover stays meanwhile, and stays for a track with no clip.
  const RELAY = !(window.MediaSource && MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E"'));
  root.toggleAttribute("data-qs-canvas-relay", RELAY);
  const CLIP = /^https:\/\/canvaz\.scdn\.co\/[^\s"'\\?#]+\.mp4$/;
  let canvasFor = "", canvasTries = 0, canvasDrop = 0;

  // A track change does NOT drop the clip on screen. It used to, at once, and the next track's clip
  // comes only after its lookup (and, uncached, its re-encode) — so two tracks with clips in a row went
  // clip, cover, clip. Now the clip holds until the next one is ready, or until it is known there is
  // none, or for HOLD at most; ready in time, it goes clip to clip. --qs-canvas is never cleared, so a
  // clip that does fade out fades out showing itself.
  const HOLD = 600;
  function dropCanvas() {
    clearTimeout(canvasDrop);
    canvasDrop = 0;
    root.removeAttribute("data-qs-canvas");
  }
  async function setCanvas() {
    if (!RELAY) return;
    let uri = "";
    try { uri = String(Spicetify.Player.data.item.uri || ""); } catch (e) { /* player not up yet */ }
    // At start-up the player exists before the restored track does, and restoring a session fires no
    // songchange — so an empty answer is "not yet", not "nothing": ask again shortly.
    if (!uri) {
      if (canvasTries++ < 30) setTimeout(setCanvas, 1000);
      return;
    }
    if (uri === canvasFor) return;
    canvasFor = uri;
    clearTimeout(canvasDrop);
    canvasDrop = root.hasAttribute("data-qs-canvas") ? setTimeout(dropCanvas, HOLD) : 0;
    const def = typeof Spicetify !== "undefined" && Spicetify.GraphQL && Spicetify.GraphQL.Definitions
      && Spicetify.GraphQL.Definitions.canvas;
    if (!uri.startsWith("spotify:track:")) { dropCanvas(); return; }   // an episode, an ad, nothing
    if (!def) {                                              // GraphQL arrives after the player
      canvasFor = "";
      if (canvasTries++ < 20) setTimeout(setCanvas, 1000);
      return;
    }
    let url = "";
    try {
      const r = await Spicetify.GraphQL.Request(def, { trackUri: uri });
      url = String((r && r.data && r.data.trackUnion && r.data.trackUnion.canvas && r.data.trackUnion.canvas.url) || "");
    } catch (e) { /* no clip, or the API said no: the cover, below */ }
    if (uri !== canvasFor) return;                           // a newer track came meanwhile
    if (!CLIP.test(url)) { dropCanvas(); return; }           // no clip: the cover comes back now
    const src = "http://127.0.0.1:" + bridgePort() + "/canvas?src=" + encodeURIComponent(url);
    const img = new Image();
    img.onload = () => {
      if (uri !== canvasFor) return;
      clearTimeout(canvasDrop);
      canvasDrop = 0;
      root.style.setProperty("--qs-canvas", 'url("' + src + '")');
      root.setAttribute("data-qs-canvas", "");
    };
    img.onerror = () => { if (uri === canvasFor) dropCanvas(); };   // a bridge that's down: the cover
    img.src = src;
  }

  let tries = 0;
  (function wire() {
    if (typeof Spicetify === "undefined" || !Spicetify.Player || !Spicetify.Player.addEventListener) {
      // Capped, so a Spotify that never defines it doesn't keep a timer alive forever.
      if (tries++ < 120) setTimeout(wire, 500);
      return;
    }
    // The events can fire before isPlaying() reflects the change, so the read is deferred a
    // beat; and onprogress (playback-driven, so it can't be throttled away like a timer) is a
    // cheap net for the case where a transition was missed.
    const later = () => setTimeout(setPlaying, 120);
    Spicetify.Player.addEventListener("onplaypause", later);
    Spicetify.Player.addEventListener("songchange", () => { later(); setArt(); setCanvas(); });
    Spicetify.Player.addEventListener("onprogress", () => {
      if (!root.hasAttribute("data-qs-playing")) setPlaying();
    });
    setPlaying();
    setArt();
    setCanvas();
    syncRing();
  })();
})();
