pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "parts"
// The media pair, the calendar, the notification centre, the brightness sliders and the
// call bar are all the overview's own cards, instantiated here rather than reimplemented
// — see "the two media cards" below for what that cost and what it bought.
import "../overview"
import "../discord"

// ── LockScreen ────────────────────────────────────────────────────────────────
// The session lock: one surface per screen, over a blurred, moving still of
// whatever the wallpaper currently is.
//
// ── One object, every screen ──────────────────────────────────────────────────
// NOT wrapped in Variants, unlike every other surface in shell.qml. WlSessionLock
// builds a WlSessionLockSurface per output ITSELF from the `surface` component, and
// keeps doing so as monitors come and go — which it has to, because a monitor
// plugged in while the session is locked must not appear as an unlocked gap. Putting
// this in Variants would mean N locks each trying to lock the same session.
//
// ── Authentication is per surface, and that is deliberate ─────────────────────
// Each surface owns its own PamContext. The alternative — one shared conversation
// driven by whichever screen has focus — sounds tidier and is worse: PAM is a
// stateful conversation, and two surfaces feeding one context interleaves their
// messages. A per-surface context means the screen you typed into is the screen that
// answers, and the others simply never start one.
//
// ── What may appear on a surface nobody has authenticated to ──────────────────
// Ambient facts, in the corners: the time, the weather, how many notifications are
// waiting (the COUNT — never a summary, never a body, because the whole point of a
// lock is that the person looking at it might not be you), and what is playing.
//
// What it lets an unauthenticated person DO is a shorter list, and each entry was an
// explicit call: skip a track, and end the session (log out / restart / shut down,
// behind the same two-step arming the overview uses). Nothing that reads private
// state, nothing that changes a setting, no session switcher. The session actions are
// there because someone at the keyboard can already reach the power button on the
// case — and they are behind Config.lockShowPower because "log out" is the one that
// genuinely costs something: unsaved work in every window behind this lock.
//
// ── The failure mode this file is written around ──────────────────────────────
// If this client dies without unlocking, the compositor keeps the session locked
// forever — that is ext-session-lock-v1 working correctly. So nothing here may throw
// on a path that runs before unlock is possible, and nothing may leave the user
// facing a box that cannot accept input. `secure` is surfaced rather than assumed,
// PAM failing to start is SHOWN rather than swallowed, there is no state in which the
// password field is uneditable while the lock is up, and the one thing that delays an
// unlock (the exit animation) is driven by a Timer that cannot be cancelled rather
// than by an animation's completion signal.
// ─────────────────────────────────────────────────────────────────────────────
WlSessionLock {
    id: lock

    locked: Lock.locked

    // Mirror the compositor's answer back into the service so `lock status` can report
    // it. `secure` is false when the compositor did not grant the lock — the surface
    // says so in words, because a password box that is not actually protecting
    // anything is worse than no password box.
    onSecureChanged: Lock.secure = lock.secure

    // ── StatCard and GlanceCard ───────────────────────────────────────────────
    // Both used to be declared inline here. They now live in components/, because the
    // greeter needs the identical two shapes and a copy in each file is how the two
    // surfaces would quietly stop matching. The reasoning for each — why StatCard is
    // shared while About's GaugeTile and the desktop's SysmonWidget deliberately are
    // not, and why GlanceCard is a card rather than a pill — moved with them.
    //
    // `sampleInterval` is passed rather than read from SysInfo inside the component, so
    // components/ stays free of any dependency on services/.

    WlSessionLockSurface {
        id: surface
        // Reached by the view files in parts/.
        property alias centre: centre
        property alias clock: clock

        // The floor under everything, and the fallback when there is genuinely no
        // picture anywhere — no still wallpaper set and no scene running.
        color: Colors.of(QsWindow.window).base

        // ══ What the lock draws on ════════════════════════════════════════════
        // A session-lock surface is ABOVE every layer including the background, so the
        // real wallpaper — still image or running scene — is not visible through it.
        // Whatever the lock shows, it has to draw itself.
        //
        // ── The scene preview is TINY, and that drives everything below ───────
        // Measured, on this library: the running scene's preview.gif is 224×224, 48
        // frames, 80ms each — a 3.84-second loop at 12.5fps. That is the entire asset
        // Wallpaper Engine publishes. There is no higher-resolution still and no way to
        // capture the live scene, so any lock that wants to look like the scene is
        // working from a thumbnail.
        //
        // Two consequences, both handled rather than hoped away:
        //
        //   · Upscaled 11× and lightly blurred, it looks exactly like what it is. The
        //     answer is not a better upscale, it is MORE blur — see previewBlur below.
        //     Past a certain radius the source resolution stops being visible at all and
        //     what is left is the scene's colour and movement, which is the part worth
        //     having.
        //   · A 3.84s loop repeats visibly if you can still make out shapes. The same
        //     heavier blur is what stops that being a "weird loop" and starts it being
        //     an ambient drift.
        //
        // `lockBackdrop` exists because that trade is a matter of taste and the other
        // side of it is legitimate: a 4K still from the image library is sharper and
        // more detailed than any scene preview will ever be, at the cost of not being
        // what is actually on the desktop.
        //
        //   "auto"  the running scene's preview, else the still wallpaper
        //   "image" always the still wallpaper, even while a scene is running
        //   "none"  no picture — the palette's own colour and the vignette
        //
        // The Material Wallpaper is no file, so it is drawn here instead (backdropMaterial), through the
        // same blur and scrim, for "auto" and "image" alike.
        readonly property bool backdropMaterial: Config.wallMaterial && Config.lockBackdrop !== "none"
        readonly property string backdrop: {
            if (Config.lockBackdrop === "none" || surface.backdropMaterial) return ""
            if (Config.lockBackdrop === "image") return Wallpaper.currentPath
            return WallpaperEngine.currentPreview !== "" ? WallpaperEngine.currentPreview
                                                        : Wallpaper.currentPath
        }

        // True when the picture is a Workshop preview rather than a wallpaper file — the
        // difference between ~224px and ~4K, which is the difference between needing the
        // blur to hide the source and needing it only to keep the type legible.
        readonly property bool backdropIsPreview:
            surface.backdrop !== "" && surface.backdrop === WallpaperEngine.currentPreview

        // Most Workshop previews are GIFs and the rest are JPEGs — an Image renders a
        // GIF's first frame and stops, so the two need different elements. Branching on
        // the EXTENSION rather than on "is a scene running" is the same rule the gallery
        // tiles use: the file itself cannot be out of sync with what it is.
        readonly property bool backdropIsGif: surface.backdrop.toLowerCase().endsWith(".gif")

        readonly property bool hasBackdrop: surface.backdropMaterial
            || (surface.backdropIsGif
                ? motionShot.status === Image.Ready
                : stillShot.status  === Image.Ready)

        // ── Why the poll, and why it is let go again ──────────────────────────
        // WallpaperEngine.running and .current are read back from the renderer's own
        // command line by a poll that is REFCOUNTED OFF unless something is watching —
        // so they are stale by default, and a scene you started by hand reads as "no
        // scene running". That is what made the first version of this fall back to a
        // flat colour even with a scene up: the lock asked a service that had not
        // looked in hours.
        //
        // acquire() is the shell-wide idiom for "I need this service live" (WallpaperPanel
        // and WallpaperPage both hold it while open). It is released after a few seconds
        // rather than for the lock's whole lifetime because the answer cannot change:
        // nothing can start or stop a wallpaper while the session is locked, so the poll
        // only has to run long enough to answer once. A lock left up overnight must not
        // be spawning a pgrep every two seconds until morning.
        property bool _wpeHeld: false
        // One handler: a second `Component.onCompleted` on the same object is a
        // duplicate-assignment error, not an addition.
        Component.onCompleted: {
            WallpaperEngine.acquire()
            surface._wpeHeld = true
            wpeRelease.start()
            Weather.acquire()
            surface.lockedAt = Date.now()
            surface._syncCava()
            surface._syncSys()
        }
        Component.onDestruction: {
            if (surface._wpeHeld)  WallpaperEngine.release()
            if (surface._cavaHeld) Cava.release()
            if (surface._sysHeld)  SysInfo.release()
            Weather.release()
        }

        Timer {
            id: wpeRelease
            interval: 4000
            repeat: false
            onTriggered: {
                if (!surface._wpeHeld) return
                surface._wpeHeld = false
                WallpaperEngine.release()
            }
        }

        // ══ Reveal ════════════════════════════════════════════════════════════
        // One driver, 0 → 1, for the whole entrance, run backwards for the exit.
        // Everything that moves reads off it rather than owning an animation, so the
        // lock arrives and leaves as one gesture instead of nine things each easing on
        // their own schedule.
        //
        // The wallpaper's BLUR is part of it: at 0 the picture is sharp, at 1 it is
        // fully defocused. So locking looks like the desktop going out of focus behind
        // the lock, and unlocking looks like it coming back — the transition explains
        // what happened rather than decorating it.
        property real reveal: 0

        // Everything but the clock trails it. A second animation would drift out of sync
        // with the first; remapping the same driver cannot.
        readonly property real revealLate: Math.max(0, Math.min(1, (surface.reveal - 0.22) / 0.78))
        readonly property real revealLast: Math.max(0, Math.min(1, (surface.reveal - 0.45) / 0.55))

        // ── Scale ─────────────────────────────────────────────────────────────
        // Entering, the stack settles from slightly small. LEAVING, it lifts slightly
        // large — the same driver read the other way round, so an unlock reads as the
        // lock being taken off the screen rather than as the entrance played backwards.
        // Both from `reveal`, so nothing can chase anything.
        readonly property real contentScale: surface.leaving
            ? 1.0 + 0.05 * (1 - surface.reveal)
            : 0.96 + 0.04 * surface.revealLate

        NumberAnimation {
            id: revealIn
            target: surface
            property: "reveal"
            from: 0
            to: 1
            duration: Motion.spatialSlow
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.emphasizedDecel
            running: true
        }

        NumberAnimation {
            id: revealOut
            target: surface
            property: "reveal"
            to: 0
            duration: Motion.exit
            easing.type: Motion.exitCurve
        }

        // ══ Backdrop ══════════════════════════════════════════════════════════
        // Blurred through `layer.effect` rather than by pointing a MultiEffect at a
        // hidden source. That matters here and not in the earlier still-only version:
        // an invisible item is not rendered, and an AnimatedImage that is never rendered
        // is an AnimatedImage whose frames may never reach the texture. Rendering into a
        // layer and letting the effect draw the layer is well-defined for both.
        Item {
            id: backdropLayer
            anchors.fill: parent
            visible: surface.hasBackdrop

            layer.enabled: true
            layer.smooth:  true
            // ── Blur at quarter resolution, not at the panel's ────────────────
            // Three problems, one fix. A Workshop preview is 224×224 (measured, not
            // assumed) — blowing that up to a 1440p screen and THEN blurring means every
            // pass runs over 3.7M pixels of upscaled thumbnail, every animated frame, and
            // the GIF's own dither pattern gets faithfully magnified into the visible
            // cross-hatch rather than dissolved. Rendering the layer into a quarter-size
            // texture blurs at the scale the source actually has, throws the dither away
            // with it, and costs a sixteenth of the fill — and because the result is a
            // smooth upscale of an already-soft image, nothing is lost.
            //
            // blurMax drops to match: the radius is in TEXTURE pixels, so 20 here reaches
            // as far as 80 did at full size.
            layer.textureSize: Qt.size(Math.max(320, Math.round(surface.width  / 4)),
                                       Math.max(180, Math.round(surface.height / 4)))
            layer.effect: MultiEffect {
                blurEnabled: true
                // The reveal driver, straight through. Blurred rather than shown sharp
                // for a reason beyond looks: a lock has to stay legible over a picture
                // it has never seen — one that may be white, busy, or high-contrast
                // exactly where the clock sits. Blur plus the scrim turns any wallpaper
                // into a predictable backdrop, so the type never fights the photo.
                blur: surface.reveal
                // ── Two different jobs, two different radii ───────────────
                // A 4K wallpaper only needs enough blur to stop competing with the type;
                // it has detail worth keeping and 20 (≈80 at full size) is plenty.
                //
                // A 224px scene preview needs enough blur that its RESOLUTION disappears
                // — and that is a much bigger number, because anything less leaves you
                // looking at a magnified thumbnail and watching its four-second loop go
                // round. Past 56 the source stops being legible as an image at all and
                // what survives is the scene's colour and motion, which was the only part
                // worth having. It reads as an intentional wash rather than as a bad
                // upscale, and the loop stops being something the eye can catch.
                blurMax: surface.backdropIsPreview ? 56 : 20
                autoPaddingEnabled: false
                // -0.12 is the same darkening OverviewNowPlaying uses behind album art,
                // and it is deliberately gentle: the darkening and the scrim below
                // COMPOUND, and between them it is easy to end up with a lockscreen that
                // technically shows your wallpaper while being indistinguishable from a
                // grey rectangle. These are the numbers to turn up if type is hard to read.
                brightness: -0.12
                saturation: -0.1
            }

            Image {
                id: stillShot
                anchors.fill: parent
                source: (surface.backdrop === "" || surface.backdropIsGif)
                            ? "" : "file://" + surface.backdrop
                fillMode: Image.PreserveAspectCrop
                // Caps the decode at the screen's own size — without it a 4K picture on
                // a 1080p screen decodes at 4K for four times the memory. Safe here
                // because there is no sourceClipRect in play; the two together are the
                // trap CLAUDE.md records.
                sourceSize: Qt.size(surface.width, surface.height)
                asynchronous: true
                cache: true
                smooth: true
            }

            // Held still: it is about to be blurred, and a lock is no place for a frame loop.
            Loader {
                anchors.fill: parent
                active: surface.backdropMaterial
                sourceComponent: MaterialWallpaper { running: false }
            }

            AnimatedImage {
                id: motionShot
                anchors.fill: parent
                source: surface.backdropIsGif ? "file://" + surface.backdrop : ""
                fillMode: Image.PreserveAspectCrop
                // No sourceSize: a Workshop preview is a few hundred pixels wide, so
                // there is nothing to cap — and capping an animated decode costs more
                // than it saves. It is about to be blurred to nothing anyway.
                asynchronous: true
                // Two switches, and they mean different things. `lockSceneAnimate` is the
                // real escape hatch for the loop: a still frame cannot repeat, and under
                // the drift below a frozen frame reads as an ambient background rather
                // than as a broken video. Config.motionEnabled is the shell-wide "stop
                // things moving on their own", which this obeys as well.
                playing: Motion.ambientOn && Config.lockSceneAnimate
                cache: true
                smooth: true

                // ── Play it at the speed it was authored ──────────────────────
                // This is NOT the scene. There is no way to get the scene: the renderer
                // draws on the background layer and a session-lock surface is above it by
                // protocol, so the compositor is not showing you the wallpaper at all
                // while locked — this file has to draw its own. The only footage Wallpaper
                // Engine publishes is the Workshop preview, and for this scene that is 48
                // frames at 80ms: a 3.84-second loop at 12.5fps, measured.
                //
                // It briefly ran at 0.55× here, to make the loop less obviously a loop.
                // That was the wrong trade and it is the reason it looked choppy: the
                // frame COUNT is fixed, so slowing playback does not add motion, it just
                // holds each of twelve frames a second on screen for longer — stutter,
                // bought in exchange for hiding a repeat nobody had complained about.
                // Authored speed is the only speed that looks like the wallpaper does.
                speed: 1.0
            }

            // ── Drift ─────────────────────────────────────────────────────────
            // A very slow push-in. Only ever scaling up, so the frame stays covered, and
            // only over a picture that is already defocused, so there is nothing to go
            // soft. This is what stops a lock you are staring at from reading as a
            // screenshot.
            //
            // ── And it is the actual answer to the "weird loop" ───────────────
            // I turned this OFF for animated previews on the reasoning that the scene
            // already moves, so two motions at once would be soup. That was exactly
            // backwards. A 3.84-second loop is obvious precisely because everything else
            // holds still: the eye gets a fixed frame of reference and the repeat lands
            // in the same place every time. Drifting the frame on a 45-second cycle means
            // the loop never comes back to the same composition, and at this blur radius
            // there is no detail left to recognise it by.
            //
            // The duration is a literal rather than a Motion token on purpose: Motion's
            // scale is for UI motion, where every value is something the user is waiting
            // on. This is ambient — forty-five seconds is not "slow feedback", it is the
            // point — and running it through Config.motionScale would let a 2× preference
            // turn it into a minute-and-a-half crawl.
            SequentialAnimation on scale {
                running: Motion.ambientOn && surface.hasBackdrop
                loops: Animation.Infinite
                NumberAnimation { from: 1.0;  to: 1.10; duration: 45000; easing.type: Motion.ambient }
                NumberAnimation { from: 1.10; to: 1.0;  duration: 45000; easing.type: Motion.ambient }
            }
        }

        // ── Scrim ─────────────────────────────────────────────────────────────
        // A vignette rather than a flat wash, and in the palette's own base colour
        // rather than plain black — so the lock is tinted by the same wallpaper-derived
        // scheme as the rest of the shell instead of reading as a grey sheet dropped on
        // top. Heavier at the edges, lighter through the middle band where the clock and
        // the field sit, which gives the centre somewhere to sit ON rather than floating
        // on an even field of nothing. Drawn over the flat base colour too when there is
        // no picture, so the composition is identical either way.
        Rectangle {
            anchors.fill: parent
            opacity: surface.reveal
            gradient: Gradient {
                GradientStop { position: 0.00; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.74) }
                GradientStop { position: 0.34; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.42) }
                GradientStop { position: 0.66; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.42) }
                GradientStop { position: 1.00; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.80) }
            }
        }

        // ══ The PAM conversation ══════════════════════════════════════════════
        // The flow, which is not obvious from the API: start() opens a conversation, and
        // PAM then ASKS for the password by emitting pamMessage with responseRequired
        // set. So the password cannot be handed over up front — it is held here until
        // the prompt arrives, then answered.
        PamContext {
            id: pam

            config: Config.lockPamConfig
            // `user` deliberately unset: it defaults to the user the shell is running
            // as, which is the only correct answer and avoids hardcoding a name into a
            // config other people install.

            onPamMessage: {
                // Only ever answer a prompt that is actually asking for something. A PAM
                // stack can emit informational messages ("Account expires in…") with
                // responseRequired false, and responding to one desynchronises the
                // conversation.
                if (pam.responseRequired) {
                    pam.respond(surface.pending)
                    // Cleared the moment it is spent, so the plaintext lives for one call
                    // rather than until the next attempt overwrites it.
                    surface.pending = ""
                } else if (pam.message !== "") {
                    surface.notice = pam.message
                }
            }

            onCompleted: function(result) {
                surface.busy = false

                if (result === PamResult.Success) {
                    surface.finish()
                    return
                }

                // Everything else keeps the lock up. The wording distinguishes the three
                // because they need different reactions from a person: a typo, a
                // locked-out account, and a broken PAM stack are not the same problem.
                surface.reject(
                      result === PamResult.MaxTries ? "Too many attempts — wait, then try again."
                    : result === PamResult.Error    ? "Authentication error."
                    :                                 "Incorrect password.")
            }

            onError: function(err) {
                surface.busy = false

                // StartFailed almost always means Config.lockPamConfig names a file that
                // is not in /etc/pam.d. Said plainly, with the fix in it, because the
                // person reading it is locked out and cannot go and search.
                surface.reject(err === PamError.StartFailed
                    ? "Cannot start PAM (\"" + Config.lockPamConfig + "\"). Switch to a TTY with Ctrl+Alt+F2 to recover."
                    : "Authentication is unavailable.")

                Lock.lastError = PamError.toString(err)
            }
        }

        // ══ Surface state ═════════════════════════════════════════════════════
        // Note what is NOT here: a `password` property mirroring the field.
        //
        // The obvious build is `TextInput { text: surface.password }` plus an
        // onTextChanged writing back, and it is broken in a way that only shows up on the
        // second attempt: typing into a TextInput assigns `text` imperatively, which
        // DESTROYS the declarative binding. From the first keystroke onward, clearing
        // `surface.password` no longer clears the field — so a failed attempt would leave
        // the old password on screen while the code believed it had wiped it. The field
        // is the single source of truth instead, and clearing means assigning to
        // `field.text`.
        property string pending:  ""    // handed to PAM when it asks, then cleared
        property string notice:   ""
        property bool   noticeIsError: false
        property bool   busy:     false
        property int    attempts: 0
        // Latched once authentication has succeeded: the exit animation is playing and
        // nothing may start another attempt during it.
        property bool   leaving:  false

        function reset() {
            centre.field.text      = ""
            surface.pending = ""
        }

        function submit() {
            if (surface.busy || surface.leaving || centre.field.text === "") return
            surface.busy    = true
            surface.notice  = ""
            surface.noticeIsError = false
            surface.pending = centre.field.text

            // A context that already ran is not reusable — a second attempt needs a fresh
            // start(). start() returning false means PAM never opened at all, and onError
            // does not fire for that, so it is handled here.
            if (!pam.start()) {
                surface.busy = false
                surface.reject("Cannot start PAM (\"" + Config.lockPamConfig + "\"). Switch to a TTY with Ctrl+Alt+F2 to recover.")
                Lock.lastError = "start() refused"
            }
        }

        // Wrong password, or PAM could not be asked. Clears the field, says why, and
        // shakes — the shake is the part you feel before you have read anything, which is
        // what stops the second attempt being typed into a field you thought had accepted
        // the first.
        function reject(message) {
            surface.reset()
            surface.attempts++
            surface.notice = message
            surface.noticeIsError = true
            if (Config.motionEnabled) centre.shake.restart()
        }

        // ── Leaving ───────────────────────────────────────────────────────────
        // Authentication succeeded. Play the reveal backwards — the blur lifts and the
        // desktop comes back into focus underneath while the stack scales gently away —
        // and unlock when it is done.
        //
        // The unlock is fired by a TIMER, not by revealOut's completion signal, and that
        // is the whole safety argument for delaying it at all: an animation can be
        // stopped, retargeted, or never started (duration 0 when motion is off), and any
        // of those would leave a correct password sitting in front of a lock that never
        // opens. A Timer fires regardless of what happens to the visuals, and its
        // interval is bounded to a few frames.
        function finish() {
            if (surface.leaving) return
            surface.leaving = true
            surface.reset()
            surface.notice = ""
            surface.noticeIsError = false
            revealIn.stop()
            revealOut.start()
            unlockTimer.start()
        }

        Timer {
            id: unlockTimer
            interval: Math.max(80, Motion.exit + 40)
            repeat: false
            onTriggered: Lock.unlock()
        }

        // ── Clock ─────────────────────────────────────────────────────────────
        // Its own clock rather than a shared one: this surface exists only while the lock
        // is up, and a minute-resolution tick that runs for that long costs nothing.
        // Quickshell's SystemClock stops when nothing is bound to it.
        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        // ── Who is unlocking ──────────────────────────────────────────────────
        // From the environment, never hardcoded — this config is published, and PAM is
        // already authenticating whoever the shell runs as.
        readonly property string userName: Lock.userName

        // ── Finding a login photo without asking Image to fail three times ────
        // The probe now lives in the Lock service (Lock.facePath: one probe, not one per
        // screen, re-run at each lock). Why it is a probe at all:
        //
        // The first version pointed the Image at each candidate in turn and advanced on
        // Image.Error. It worked, and it logged six warnings every time the lock went up
        // — three candidates × two monitors — because "this file does not exist" is a
        // WARNING to Qt no matter how expected it is to us. A lockscreen that prints
        // errors on a completely normal path trains you to ignore its errors.
        //
        // So the filesystem is asked first, by something whose job is answering that
        // question, and the Image is only ever pointed at a path already known to exist.
        // Most installs have none of these, which is why the monogram underneath is the
        // real answer and this is the bonus.
        // Config.lockAvatar goes FIRST when set, so an explicit choice always beats a
        // stray ~/.face someone's display manager left behind. It is still probed rather
        // than trusted: the file can be deleted or renamed long after it was picked, and
        // the monogram is a better answer than a broken-image box on a locked screen.
        readonly property string facePath: Lock.facePath

        // ══ The two media cards ═══════════════════════════════════════════════
        // The overview's own OverviewNowPlaying and OverviewLyrics, instantiated here
        // rather than reimplemented. What was here before was a hand-rolled media card
        // with its own player selection, its own position clock and a single static
        // lyric line — three things the overview already does better, and three things
        // that would have drifted from it the first time either was touched.
        //
        // Both needed one change to be reusable, and only one: they gated their timers
        // and the lyric wave on `UiState.overviewOpen` directly, which is false by
        // definition on a locked screen. That is now an `active` property defaulting to
        // the overlay's state, so the overview passes nothing and this passes true.
        //
        // The card owns the player, the clock and the AlbumArt palette; the lyrics read
        // the card's position rather than starting a second timer, exactly as the
        // overview wires them — two clocks following one song drift apart, and the
        // progress bar and the lyrics would disagree about where it is.
        readonly property bool mediaShown: Config.lockShowMedia && lockMediaPair.nowPlaying.player !== null

        // ── Lyrics are off for YouTube, and that is not arbitrary ─────────────
        // Lyric lookup is keyed on artist and title. Spotify and the like hand MPRIS a
        // real `xesam:artist` and `xesam:title`, so the match is usually exact. YouTube
        // hands over the VIDEO title — "Artist - Song (Official Music Video) [4K]", or a
        // one-hour mix, or a stream — and the artist field is often the channel. So the
        // lookup either misses, or worse, matches a different song and scrolls confident
        // wrong words in time with your music.
        //
        // The card already knows where the audio is coming FROM: `source` resolves the
        // xesam:url host before falling back to the app, so this is browser-agnostic —
        // YouTube in Firefox and YouTube in a PWA both answer "youtube".
        //
        // Off is the DEFAULT, not the rule. Config.lockLyricsOnYouTube turns them back on
        // for anyone who mostly plays properly-titled music there.
        readonly property bool lyricsUseful:
            Config.lockLyricsOnYouTube || (lockMediaPair.nowPlaying.source?.id ?? "") !== "youtube"


        // ══ What arrived while you were away ══════════════════════════════════
        // The delta since the lock went up, NOT Notifications.count — that is the whole
        // retained history, which saturates at maxHistory and would sit there reading
        // "100 notifications" forever. "Three things happened while you were gone" is the
        // only number worth putting on a lockscreen, and records carry a timestamp, so it
        // survives the history being evicted underneath it.
        property real lockedAt: 0
        readonly property int notifNew: {
            if (surface.lockedAt === 0) return 0
            const recs = Notifications.records
            let n = 0
            for (let i = 0; i < recs.length; i++)
                if ((recs[i].time ?? 0) >= surface.lockedAt) n++
            return n
        }

        // ══ Corner chips ══════════════════════════════════════════════════════
        // Ambient, glanceable, and each one absent when it has nothing to say — so on a
        // machine with no weather location and nothing waiting, the corners are simply
        // empty and the composition is a clean centre. Built as Surfaces at card
        // elevation with the shell's own translucency, because the shell is made of
        // pills and a lockscreen that invented its own chip shape would be the one
        // surface that opted out of the language.

        // ── Weather, top left ─────────────────────────────────────────────────
        GlanceCard {
            anchors.left: parent.left
            anchors.top:  parent.top
            anchors.margins: Tokens.spacingXxl

            visible: Weather.hasLocation && Weather.ready

            glyph:    Weather.glyph(Weather.code, Weather.isDay)
            headline: Weather.temp(Weather.tempC) + Weather.unit
            detail:   Weather.describe(Weather.code)
                      + (Weather.place !== "" ? "  ·  " + Weather.place : "")
            tint:     Colors.of(QsWindow.window).info

            opacity: surface.revealLast
            transform: Translate { x: (1 - surface.revealLast) * -22 }
        }

        // ── Notifications, right edge ─────────────────────────────────────────
        // The overview's actual notification centre, not a chip counting things. The
        // count-only rule from before was about not PREVIEWING a notification's contents
        // on a surface where the reader might not be you — this is that decision
        // reversed, deliberately and at your request, so the switch that governs it is
        // the honest place for the caveat rather than a comment nobody reads.
        //
        // Config.lockShowNotifications now means "show the centre", and its detail line
        // on the settings page says what that discloses.
        OverviewNotifications {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Tokens.spacingXxl

            visible: Config.lockShowNotifications
            // Shorter than the overview's 460: this shares a screen edge with nothing,
            // but it also sits beside a password field, and a list tall enough to reach
            // the top of the screen makes the lock look like a notification app.
            maxListHeight: 360

            opacity: surface.revealLast
            transform: Translate { x: (1 - surface.revealLast) * 26 }
        }


        // ══ Top middle: system stats, and the call under them ═════════════════
        // SysmonWidget is the desktop's own monitor tile, not a third rendering of
        // SysInfo. It takes an `opts` object because it is normally driven by a
        // configured desktop widget; a literal one is exactly what that parameter is —
        // there is no persisted lock-screen widget to read it from, and inventing a
        // config entry so this could look it up would be ceremony around a constant.
        //
        // It already refcounts SysInfo off its own `active`, so nothing here has to
        // acquire or release: switch the card off and the sampler stops.
        LockStats {
            id: lockStats
            lockSurface: surface
        }


        // ══ Session actions, left edge ════════════════════════════════════════
        // The same three the overview's PowerPanel offers, minus Lock (you are looking
        // at it), and armed the same way: picking an action does NOT fire it, a second
        // and DIFFERENTLY PLACED click does. That two-step is not ceremony — colour
        // cannot carry the warning on this palette, where `danger` and `primary` can
        // resolve to the same value, so the spelled-out consequence and the moved target
        // are what actually stop a misclick ending the session.
        //
        // ── On offering these at all ──────────────────────────────────────────
        // Anyone standing at the keyboard can already cut the power with the button on
        // the case, so "shut down" gives away nothing. Log out is the one with teeth: it
        // discards unsaved work in every window behind this lock, and it is reachable by
        // someone who could not get past the password. That is the trade, it is a real
        // one, and it is why this is a setting rather than a decision made for you.
        property string armed: ""

        readonly property var powerActions: [
            {
                key: "logout", symbol: "logout", label: "Log out",
                detail: "Ends the session and closes everything",
                tint: Colors.of(QsWindow.window).focus
            },
            {
                key: "reboot", symbol: "restart_alt", label: "Restart",
                detail: "Reboots the machine",
                tint: Colors.of(QsWindow.window).warning
            },
            {
                key: "shutdown", symbol: "power_settings_new", label: "Shut down",
                detail: "Powers the machine off",
                tint: Colors.of(QsWindow.window).danger
            }
        ]

        // Session owns key → command (log out is a Hyprland dispatch, not a process —
        // Hypr.exitSession has why; the rest are systemctl), the table the power menu uses.
        function fire(action) { Session.run(action.key) }

        readonly property var armedAction:
            surface.powerActions.find(a => a.key === surface.armed) ?? null

        // Forgets an armed action rather than leaving it primed indefinitely. Same
        // four seconds PowerPanel uses.
        Timer {
            id: disarm
            interval: 4000
            onTriggered: surface.armed = ""
        }
        onArmedChanged: {
            if (surface.armed !== "") disarm.restart()
            else                      disarm.stop()
        }

        // ── Top right: three round chips in one tray, nothing written down ────────
        // The panels' own header-action tray (ChipTray / ChipButton). It is deliberately
        // quiet — these are not what the surface is for, and a lockscreen whose loudest
        // element is "Shut down" has its priorities backwards. Arming lights the chip and
        // opens the confirmation under the tray, which says what will happen in words
        // before offering the button that does it.
        LockSessionActions {
            id: lockSessionActions
            lockSurface: surface
        }

        // ══ The centre ════════════════════════════════════════════════════════
        // Time, then who you are, then the one field. Everything else on this surface is
        // in a corner; this column is the only thing you can act on.
        LockCentre {
            id: centre
            lockSurface: surface
        }

        // ══ The spectrum ══════════════════════════════════════════════════════
        // The same bottom-of-screen visualizer CavaBG draws on the desktop, drawn here
        // instead — it cannot be drawn THROUGH: CavaBG is a layer-shell surface on
        // `bottom`, and this lock sits above every layer, so while the session is locked
        // the real one is simply not visible.
        //
        // Its own Config switch rather than following Config.cavaBg, because these are
        // genuinely different questions: the desktop one competes with your windows,
        // this one competes with nothing. Wanting it in exactly one of the two places is
        // an ordinary preference, not a contradiction.
        //
        // The cava REFERENCE is refcounted and only held while the bars are actually
        // wanted — a locked screen that quietly kept an audio analyser running because
        // the setting was on once is the same waste CavaBG had to be fixed for.
        // ── The sampler behind the three stat cards ───────────────────────────
        // SysInfo is refcounted for the same reason cava is: it reads /proc and the
        // hwmon tree once a second, and a locked screen that kept sampling because the
        // setting was on once is exactly the waste the refcount exists to prevent. This
        // used to come free from SysmonWidget, which does its own acquire/release — the
        // three cards read SysInfo directly, so the holding is ours now.
        readonly property bool statsWanted: Config.lockShowStats && !surface.leaving

        property bool _sysHeld: false
        function _syncSys() {
            if (surface.statsWanted === surface._sysHeld) return
            if (surface.statsWanted) SysInfo.acquire()
            else                     SysInfo.release()
            surface._sysHeld = surface.statsWanted
        }
        onStatsWantedChanged: surface._syncSys()

        readonly property bool cavaWanted: Config.lockShowCava && !surface.leaving

        property bool _cavaHeld: false
        function _syncCava() {
            if (surface.cavaWanted === surface._cavaHeld) return
            if (surface.cavaWanted) Cava.acquire()
            else                    Cava.release()
            surface._cavaHeld = surface.cavaWanted
        }
        onCavaWantedChanged: surface._syncCava()

        // 32 bars mirrored to 64 — bass meeting in the middle, treble at both edges, the
        // way cava itself presents a stereo field. Shaped with the same expansive curve,
        // so quiet passages stay low and transients shoot.
        readonly property int  cavaBars:   Cava.barCount * 2
        readonly property var  cavaLevels: Cava.shapedMirrored
        readonly property real cavaSlotW:  surface.width / Math.max(1, surface.cavaBars)

        Item {
            id: viz
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            height: 180

            visible: surface.cavaWanted
            // Dimmer than the desktop's. There it IS the decoration; here it is behind a
            // password field, and a full-strength spectrum under the thing you are typing
            // into is the visualizer arguing with the lock.
            opacity: 0.45 * surface.revealLast

            Repeater {
                model: surface.cavaBars

                Rectangle {
                    id: bar
                    required property int index

                    x: bar.index * surface.cavaSlotW + (surface.cavaSlotW - width) / 2
                    width: Math.max(2, surface.cavaSlotW * 0.6)
                    anchors.bottom: parent.bottom
                    color: Colors.of(QsWindow.window).focus

                    readonly property real target: Math.max(2, Math.round(
                        (bar.index < surface.cavaLevels.length ? surface.cavaLevels[bar.index] : 0)
                        * viz.height))
                    height: bar.target

                    // Fast attack, slow decay — what makes a spectrum read as responding
                    // to music rather than sloshing. Lifted deliberately from CavaBG: two
                    // visualizers in one shell moving differently would read as a bug.
                    Behavior on height {
                        NumberAnimation {
                            duration: bar.target > bar.height ? 35 : 220
                            easing.type: Motion.respondCurve
                        }
                    }
                }
            }
        }

        // ══ Bottom left: brightness ═══════════════════════════════════════════
        // The overview's own sliders. Renders nothing at all when no display can be
        // driven, so a machine with no DDC and no backlight gets no empty stub — which is
        // also why this is safe to place unconditionally.
        //
        // Reachable without authenticating, and deliberately: a screen you cannot see is
        // a screen you cannot type a password into, and anyone who can reach the
        // monitor's own buttons can do this without asking the shell.
        //
        // Wrapped rather than configured directly, and that wrapper is load-bearing:
        // OverviewBrightness binds its OWN `visible` to "is there a display I can drive",
        // so assigning `visible` from out here would destroy that binding and leave an
        // empty 0-wide stub on every machine without DDC. The setting gates the wrapper;
        // the component keeps its own answer.
        Item {
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin:  Tokens.spacingXxl
            anchors.bottomMargin: Tokens.spacingXxl

            width:  bright.width
            height: bright.height

            visible: Config.lockShowBrightness
            opacity: surface.revealLast
            transform: Translate { y: (1 - surface.revealLast) * 20 }

            OverviewBrightness { id: bright }
        }

        // ══ Bottom left: the calendar ═════════════════════════════════════════
        // The overview's card. It needed the same one-line change the media pair did —
        // its month timer was gated on the overlay being open, so on a machine left
        // locked overnight it would have been showing yesterday.
        CalendarCard {
            anchors.left:   parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin:   Tokens.spacingXxl
            anchors.bottomMargin: Tokens.spacingXxl

            visible: Config.lockShowCalendar
            active:  Config.lockShowCalendar

            opacity: surface.revealLast
            transform: Translate { y: (1 - surface.revealLast) * 20 }
        }

        // ══ Bottom centre: the media pair ═════════════════════════════════════
        LockMediaPair {
            id: lockMediaPair
            lockSurface: surface
        }

        // Every time the lock goes up, start from a clean field with focus in it.
        Connections {
            target: Lock
            function onLockedChanged() {
                if (!Lock.locked) return
                surface.reset()
                surface.notice = ""
                surface.noticeIsError = false
                surface.busy     = false
                surface.leaving  = false
                surface.attempts = 0
                surface.lockedAt = Date.now()
                centre.field.forceActiveFocus()
            }
        }
    }
}
