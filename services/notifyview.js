.pragma library

// ── notifyview.js ─────────────────────────────────────────────────────────────
// What the notification centre SHOWS, apart from what it stores: search, the per-app
// filter, the two ways of laying the history out (by app, by day), the app counts behind
// the summary strip, and the clock arithmetic for timed Do Not Disturb and snooze. Kept
// out of the QML so `bun scripts/test-notifyview.js` can exercise it — a filter that
// quietly hides a notification is the kind of bug nobody would notice.
//
// A "group" everywhere here is { app, items, latest }: `app` is the group's label AND its
// key (the app's name in the by-app layout, "Yesterday" in the by-day one), `items` the
// records newest-first, `latest` the newest. NotificationGroups draws either layout from
// the same shape.

// The bucket a notification with no app name falls into (same as Notifications._appKey).
var NO_APP = "Notifications";

function appKey(r) {
    return (r && r.appName) ? r.appName : NO_APP;
}

// ── An app's tone ─────────────────────────────────────────────────────────────
// Which of `n` palette slots an app wears, from a hash of its NAME — so one app is the same
// colour on its tiles and on its chip in the summary strip, in every session. (The QML picks
// the colours; this only picks the slot.)
function toneIndex(name, n) {
    var h = 0, s = String(name || "");
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
    return Math.abs(h) % (n || 3);
}

// ── Search ────────────────────────────────────────────────────────────────────
// Every word typed must appear somewhere in the app's name, the summary or the body, in any
// order, ignoring case: "spotify now" finds Spotify's "Now playing". Empty matches all.
function words(q) {
    return String(q || "").toLowerCase().split(/\s+/).filter(function (w) { return w !== ""; });
}

function matches(rec, q) {
    var ws = words(q);
    if (ws.length === 0) return true;
    var hay = ((rec.summary || "") + "\n" + (rec.body || "") + "\n" + (rec.appName || "")).toLowerCase();
    for (var i = 0; i < ws.length; i++)
        if (hay.indexOf(ws[i]) < 0) return false;
    return true;
}

// `app` "" = every app.
function filter(records, q, app) {
    return records.filter(function (r) {
        return (!app || appKey(r) === app) && matches(r, q);
    });
}

// ── Layouts ───────────────────────────────────────────────────────────────────
function byApp(records) {
    var seen = {}, order = [];
    for (var i = 0; i < records.length; i++) {
        var r = records[i], k = appKey(r), g = seen[k];
        if (!g) { g = { app: k, items: [], latest: r }; seen[k] = g; order.push(g); }
        g.items.push(r);
    }
    return order;
}

// The day-part a notification belongs to, relative to `now`: the last hour, the rest of today,
// yesterday, and everything before. Local midnights, so a DST change can't shift a boundary.
function dayLabel(t, now) {
    if (now - t < 3600000) return "Last hour";
    var d = new Date(now);
    var today = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    var yesterday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1).getTime();
    if (t >= today) return "Earlier today";
    if (t >= yesterday) return "Yesterday";
    return "Earlier";
}

function byDay(records, now) {
    var seen = {}, order = [];
    for (var i = 0; i < records.length; i++) {
        var r = records[i], k = dayLabel(r.time, now), g = seen[k];
        if (!g) { g = { app: k, items: [], latest: r }; seen[k] = g; order.push(g); }
        g.items.push(r);
    }
    return order;
}

// ── The summary strip ─────────────────────────────────────────────────────────
// One entry per app with its count, the app with the newest notification first.
function appCounts(records) {
    return byApp(records).map(function (g) {
        return { app: g.app, count: g.items.length, latest: g.latest };
    });
}

// ── Timed Do Not Disturb ──────────────────────────────────────────────────────
// The next `hour`:00 strictly after `now` — "until tomorrow" at 06:00 means 08:00 today,
// at 23:00 it means 08:00 tomorrow.
function nextMorning(now, hour) {
    var h = hour === undefined ? 8 : hour;
    var d = new Date(now);
    var t = new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, 0, 0, 0).getTime();
    if (t <= now) t = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, h, 0, 0, 0).getTime();
    return t;
}

function pad2(n) { return (n < 10 ? "0" : "") + n; }

// "until 15:40", or "until tomorrow 08:00" when it ends on another day. "" when there is no end.
function untilLabel(until, now) {
    if (!until || until <= now) return "";
    var u = new Date(until), n = new Date(now);
    var hm = pad2(u.getHours()) + ":" + pad2(u.getMinutes());
    var same = u.getFullYear() === n.getFullYear() && u.getMonth() === n.getMonth() && u.getDate() === n.getDate();
    return same ? "until " + hm : "until tomorrow " + hm;
}

// ── Snooze ────────────────────────────────────────────────────────────────────
// A snoozed entry is { rec, wakeAt }. Splits what is due by `now` (oldest first, so they
// come back in the order they were snoozed) from what is still asleep.
function splitSnoozed(snoozed, now) {
    var due = [], waiting = [];
    for (var i = 0; i < snoozed.length; i++)
        (snoozed[i].wakeAt <= now ? due : waiting).push(snoozed[i]);
    due.sort(function (a, b) { return a.wakeAt - b.wakeAt; });
    return { due: due, waiting: waiting };
}

// ── Lists of names (muted apps) ───────────────────────────────────────────────
function toggleIn(list, v) {
    var i = list.indexOf(v);
    if (i < 0) return list.concat([v]);
    var next = list.slice();
    next.splice(i, 1);
    return next;
}
