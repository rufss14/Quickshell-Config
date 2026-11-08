import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../../config"
import "../../components"
import "../../services"

// ── NotificationToast ─────────────────────────────────────────────────────────
// One notification, as a card. The toast form on screen, and — with `inCentre` —
// a row in the overview's notification drawer (no timer, no countdown, close and
// time always shown).
//
// ── The dwell timer ───────────────────────────────────────────────────────────
// A toast auto-expires after Notifications.timeoutFor(n) — but PAUSES while you're
// pointing at it, because the moment you reach for a notification is the worst
// moment to yank it away. Critical notifications (timeout 0) never expire on their
// own; you dismiss them.
//
// Progress runs a NumberAnimation on `remaining` rather than counting on a Timer,
// so the countdown is smooth and pause/resume is one line (animation.paused).
//
// ── Urgency, without a stripe ──────────────────────────────────────────────────
// The old flat left stripe read as dated. Urgency now lives where the eye already
// goes: the app avatar wears a ring in the urgency tint (full for critical, faint
// otherwise), the app name is tinted, and the countdown carries the same colour.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    required property var notif
    property bool inCentre: false        // centre rows: no timer, no countdown bar

    signal expired()
    signal dismissed()

    // Two contexts, two depths. Floating (the desktop toast stack) sits on the
    // bare wallpaper like the bar and ScreenshotToast — elevationCard, so its
    // fill is the same `surface` colour as everything else out there instead of
    // the lifted `surfaceHigh` grey Popup gives it. Drawer rows (`inCentre`) sit
    // inside OverviewNotifications' own Nested app-group card, one real level
    // deeper — Card→Nested→Popup, the "card in a card" lift that file documents.
    elevation: root.inCentre ? Tokens.elevationPopup : Tokens.elevationCard
    // A softer corner than the default card — a toast is a friendly, transient
    // thing, not a dense panel, and the extra roundness reads as lighter.
    cornerRadius: Tokens.radiusCard
    // A hover accent, toasts only: it marks the card you're about to act on. Rows
    // in the drawer don't get it — the whole list is hoverable and a travelling
    // outline would be noise.
    focused: hover.hovered && !root.inCentre

    // A toast with an image attachment is a touch wider so the picture has room;
    // its height grows with the preview anyway.
    implicitWidth: root.showPreview ? 400 : 372
    implicitHeight: body.implicitHeight + Tokens.spacingLg * 2

    // Toasts lift a touch under the pointer — an acknowledgement that they're
    // interactive. Visual only (scale doesn't touch layout), and off in the centre.
    scale: (!root.inCentre && hover.hovered) ? 1.015 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.standard
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.emphasizedDecel
        }
    }

    // ── Held snapshot ─────────────────────────────────────────────────────────
    // The server can destroy a toast's live Notification out from under it — an
    // app closing/replacing an old one the instant a new one for the same
    // conversation lands is the common case — and every display field below reads
    // straight off `notif`, which goes null the moment that happens: the card
    // blanks mid-stack instead of just sitting there like a normal toast. Same fix
    // as ScreenshotToast's `held` — copy the cosmetic fields out on the way in and
    // never clear them, so a dead notif falls back to what it last knew instead of
    // nothing. `disp` is what every DISPLAY read below uses; actions/dismiss stay
    // on the live object and simply stop working once it's gone, which is fine —
    // the toast just finishes its own already-running dwell like any other.
    property var _held: ({ appName: "", appIcon: "", summary: "", body: "",
                            image: "", urgency: NotificationUrgency.Normal, time: 0 })
    function _refreshHeld() {
        if (!root.notif) return
        root._held = {
            appName: root.notif.appName || "", appIcon: root.notif.appIcon || "",
            summary: root.notif.summary || "", body: root.notif.body || "",
            image: root.notif.image || "", urgency: root.notif.urgency,
            time: (typeof root.notif.time === "number") ? root.notif.time : 0
        }
    }
    Component.onCompleted: root._refreshHeld()
    onNotifChanged: root._refreshHeld()
    // A PLAIN snapshot of the live fields, not the live object itself: `notif || _held` handed out the
    // Notification, and when the server destroyed it every binding reading `disp.urgency` (and the other
    // seven) ran once against a null before `notif` itself had been told — eight "Cannot read property of
    // null" warnings per dismissed toast. The binding still follows the live fields while the notification
    // is up, and falls back to the held copy the moment it is gone.
    readonly property var disp: {
        const n = root.notif
        if (!n) return root._held
        return {
            appName: n.appName || "", appIcon: n.appIcon || "", summary: n.summary || "", body: n.body || "",
            image: n.image || "", urgency: n.urgency, time: (typeof n.time === "number") ? n.time : 0
        }
    }

    readonly property color tint: Notifications.urgencyTint(root.disp)
    readonly property int   dwell: root.inCentre ? 0 : Notifications.timeoutFor(root.disp)
    readonly property bool  isCritical: root.disp.urgency === NotificationUrgency.Critical
    // Low urgency has a grey "tint", so its accent dot would be a grey speck that
    // says nothing — hidden for those, shown for normal and critical.
    readonly property bool  isLow: root.disp.urgency === NotificationUrgency.Low

    // The small avatar is the APP's identity — its icon, resolved from appIcon or
    // the app name. Deliberately NOT the notification's image: that's the CONTENT
    // (a screenshot, a photo, album art) and gets its own large preview below, so a
    // media notification reads as "Spotify · <big album art>" rather than shrinking
    // the art into a 44px square.
    // Resolved by the service, so a toast and the centre's tile agree on the app's icon — and on
    // the theme it comes from (the user's Papirus; see Notifications.appIconFor).
    readonly property string appIconSource: Notifications.appIconFor({
        appName: root.disp.appName, appIcon: root.disp.appIcon || root.hintIconName,
        desktopEntry: root.notif?.desktopEntry ?? ""
    })

    // The notification's own image (image-data / image-path hint). It's used TWO
    // ways depending on what it is — a sender's avatar goes in the small icon, a
    // real attachment gets a big preview — so it's loaded once (previewImg) and
    // routed from its shape.
    // An icon NAME is not an image. libnotify (notify-send -i battery-good) sends the
    // name as the image-path hint, which Quickshell turns into image://icon/<name>.
    // Loaded as a picture, a name the Qt theme lacks comes back as Quickshell's
    // missing-texture checkerboard — small and square, so it passed for an avatar.
    // Such a hint is routed to the icon path instead (appIconSource), where a miss
    // falls back to the bell glyph.
    readonly property string hintIconName: {
        const i = root.disp.image || ""
        return i.indexOf("image://icon/") === 0 ? i.slice(13).split("?")[0] : ""
    }
    readonly property string imageHint:
        root.hintIconName !== "" ? "" : (root.disp.image || "")

    // ── Avatar vs attachment ──────────────────────────────────────────────────
    // Chat apps put the SENDER'S AVATAR in this same hint as an attached photo, and
    // there's no spec field saying which is which. The tell: an avatar is SMALL and
    // SQUARE (a ~128px face). Anything larger, or non-square, is content worth
    // previewing — Discord's attachment thumbnails come through bigger than the
    // avatar, so the size test catches them even when they're roughly square. Needs
    // the image loaded for its dimensions.
    readonly property bool imageIsAvatar: {
        if (root.imageHint === "" || previewImg.status !== Image.Ready) return false
        const w = previewImg.implicitWidth
        const h = previewImg.implicitHeight
        if (w <= 0 || h <= 0) return false
        const a = w / h
        return (a >= 0.85 && a <= 1.18) && Math.max(w, h) <= 200
    }

    // The big preview is ONLY a real attachment.
    readonly property bool showPreview:
        root.imageHint !== "" && previewImg.status === Image.Ready && !root.imageIsAvatar

    // The small avatar shows the sender's avatar when there is one, else the app
    // icon. (Discord, for one, sends the sender's 128px avatar here for every
    // message — it never includes the attached image in the notification, so a
    // Discord photo message shows the avatar, not the picture. The big preview is
    // for apps that DO send the content — screenshot tools, image viewers.)
    readonly property string avatarSource:
        root.imageIsAvatar ? root.imageHint : root.appIconSource

    HoverHandler { id: hover }

    // A faint wash of the urgency colour for critical notifications — so "this is
    // important" is legible at a glance, not only on inspection of the avatar ring.
    // Inset by the border so it sits inside the card's rounded edge.
    Rectangle {
        anchors.fill: parent
        anchors.margins: Tokens.borderWidth
        radius: root.radius - Tokens.borderWidth
        color: root.isCritical ? Colors.of(QsWindow.window).alpha(root.tint, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    // ── Dwell / countdown ─────────────────────────────────────────────────────
    property real remaining: 1.0
    NumberAnimation on remaining {
        id: dwellAnim
        running: root.dwell > 0 && !root.inCentre
        // Gated on `running`, not a bare hover: a drawer row (dwell 0, never
        // running) still gets hovered, and toggling `paused` on an animation that
        // isn't running is what emitted the "setPaused() cannot be used" warning.
        paused: dwellAnim.running && hover.hovered
        from: 1.0; to: 0.0
        duration: root.dwell
        onFinished: if (root.dwell > 0) root.expired()
    }

    // A toast whose notification is REPLACED in place (replaces_id — same live object,
    // mutated, no new toast) restarts its countdown, so an app updating a live toast
    // (a download's percent, a track change) isn't yanked away mid-update. Only a live
    // Notification carries these signals; a centre record is a plain object with none,
    // so the target resolves to null there and nothing connects.
    Connections {
        target: (root.dwell > 0 && !root.inCentre && root.notif
                 && typeof root.notif.dismiss === "function") ? root.notif : null
        function onSummaryChanged() { root._refreshHeld(); dwellAnim.restart() }
        function onBodyChanged()    { root._refreshHeld(); dwellAnim.restart() }
    }

    // Tap invokes the notification's default action; middle-tap dismisses. A
    // TapHandler, not a MouseArea, so it COEXISTS with the overlay's swipe-to-
    // dismiss DragHandler: `DragThreshold` means a swipe is not counted as a tap and
    // the drag takes the gesture instead.
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        gesturePolicy: TapHandler.DragThreshold
        onTapped: function(point, button) {
            if (button === Qt.MiddleButton) { root.dismissed(); return }
            const def = Notifications.defaultAction(root.notif)
            if (def) { Notifications.invoke(def); root.dismissed() }
        }
    }

    ColumnLayout {
        id: body
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.top:   parent.top
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingLg
        anchors.topMargin:   Tokens.spacingLg
        spacing: Tokens.spacingSm

        // ── Header: [avatar]? · text · app-icon / close ───────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingMd

            // The avatar, on the left — the SENDER'S picture when the notification
            // carries one, otherwise the app's icon. Always shown.
            AvatarIcon {
                Layout.alignment: Qt.AlignTop
                d: 44
                source: root.avatarSource
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingXs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    // Urgency accent dot: the one spot of colour in the header, so
                    // the app name stays neutral and the colour MEANS urgency rather
                    // than just decorating the app's own name.
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: root.tint
                        visible: !root.isLow
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.disp.appName || "Notification"
                        variant: "caption"
                        emphasis: "muted"
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    // Small time, in the centre only (a toast is "now").
                    StyledText {
                        visible: root.inCentre
                        text: root.timeAgo
                        variant: "caption"
                        emphasis: "dim"
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.disp.summary || ""
                    variant: "body"
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.disp.body || ""
                    variant: "caption"
                    emphasis: "muted"
                    textFormat: Text.MarkdownText
                    wrapMode: Text.WordWrap
                    maximumLineCount: root.inCentre ? 6 : 4
                    elide: Text.ElideRight
                    onLinkActivated: (url) => Qt.openUrlExternally(url)
                }
            }

            // App icon, top-right (where the X used to be — toasts dismiss by
            // dragging now). Only when the LEFT avatar is the sender's picture, so
            // the app is still identified without repeating its icon twice.
            AvatarIcon {
                Layout.alignment: Qt.AlignTop
                d: 30
                source: root.appIconSource
                visible: !root.inCentre && root.imageIsAvatar
            }

            // Drawer keeps a close button — a row in a scrolling list can't be
            // swiped away the way a toast can.
            PanelButton {
                Layout.alignment: Qt.AlignTop
                variant: "ghost"
                implicitWidth:  22
                implicitHeight: 22
                glyph: "󰅖"
                visible: root.inCentre
                onActivated: root.dismissed()
            }
        }

        // ── Content image preview ─────────────────────────────────────────────
        // The notification's OWN image (a screenshot, a photo, album art), shown
        // large and aspect-correct, height-capped so a tall image can't push the
        // toast off the screen. Real rounded clipping via ClippingRectangle.
        ClippingRectangle {
            id: previewClip
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            Layout.preferredHeight: previewClip.previewH
            visible: root.showPreview
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.4)

            readonly property int previewH: {
                if (previewImg.implicitWidth <= 0) return 0
                return Math.min(180, Math.round(previewClip.width
                    * previewImg.implicitHeight / previewImg.implicitWidth))
            }

            Image {
                id: previewImg
                anchors.fill: parent
                // Loaded even when it turns out to be an avatar (square) — we need
                // its dimensions to decide, and the clip is just hidden in that case.
                source: root.imageHint
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                // Width only — preserves aspect and reports the scaled natural size,
                // so the ratio previewH is computed from stays correct. A two-dim
                // sourceSize would square the image and break the aspect.
                sourceSize.width: 512
                smooth: true
            }
        }

        // ── Actions ───────────────────────────────────────────────────────────
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: root.notif && root.notif.actions.length > 0
                ? Tokens.spacingXs : 0
            visible: root.notif && root.notif.actions.length > 0
            spacing: Tokens.spacingSm

            Repeater {
                model: root.notif ? root.notif.actions : []

                PanelButton {
                    required property var modelData
                    // The freedesktop "default" action fires on clicking the body,
                    // not as its own button — showing it labelled "default" is noise.
                    visible: modelData.identifier !== "default"
                    variant: "normal"
                    label: modelData.text
                    onActivated: {
                        Notifications.invoke(modelData)
                        root.dismissed()
                    }
                }
            }
        }
    }

    // ── AvatarIcon — the app's icon in a rounded, ringed tile ─────────────────
    // 44px in the drawer (on the left), 30px on a toast (top-right). Wears the
    // urgency ring, and falls back to a tinted bell when the app hands us no usable
    // icon (or one that fails to load at this size — dialog-error and friends).
    component AvatarIcon: Rectangle {
        id: av
        property int d: 44
        property string source: root.appIconSource

        implicitWidth:  av.d
        implicitHeight: av.d
        radius: av.d >= 40 ? Tokens.radiusPill : Tokens.radiusSm
        color: Colors.of(QsWindow.window).surfaceContainer
        border.width: root.isCritical ? 2 : Tokens.borderWidth
        border.color: root.isCritical ? root.tint : Colors.of(QsWindow.window).alpha(root.tint, 0.35)
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        ClippingRectangle {
            anchors.fill: parent
            anchors.margins: Tokens.spacingXs
            radius: av.radius - 2
            color: "transparent"

            Image {
                id: avImg
                anchors.fill: parent
                visible: av.source !== "" && avImg.status !== Image.Error
                source: av.source
                sourceSize: Qt.size(av.d * 2, av.d * 2)
                fillMode: Image.PreserveAspectCrop
                mipmap: true
                smooth: true
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: av.source === "" || avImg.status === Image.Error
            glyph: "󰂚"
            variant: av.d >= 40 ? "title" : "body"
            color: root.tint
        }
    }

    // ── Countdown bar ─────────────────────────────────────────────────────────
    // Hugs the bottom, inset from the rounded corners, with a faint track so the
    // remaining time reads as depletion rather than a bare shrinking sliver.
    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin:   Tokens.spacingLg
        anchors.rightMargin:  Tokens.spacingLg
        anchors.bottomMargin: Tokens.spacingSm
        height: 3
        radius: height / 2
        visible: root.dwell > 0 && !root.inCentre
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

        Rectangle {
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            width: parent.width * root.remaining
            radius: parent.radius
            color: root.tint
            // A soft leading glow so the depleting end reads as "time", not a cut.
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: root.tint
                visible: root.remaining > 0.02 && root.remaining < 0.995
            }
        }
    }

    // ── Relative time, for the centre ─────────────────────────────────────────
    // A record carries the REAL arrival time (epoch ms); a live toast has no `time`
    // field and is "now" anyway. Falling back to the delegate's creation time is why
    // restored history used to read "now" for every row regardless of age.
    property double _created: Date.now()
    readonly property double arrived:
        root.disp.time > 0 ? root.disp.time : root._created
    property int _tick: 0
    Timer { running: root.inCentre; interval: 30000; repeat: true; onTriggered: root._tick++ }
    readonly property string timeAgo: {
        void root._tick
        const s = Math.max(0, Math.floor((Date.now() - root.arrived) / 1000))
        if (s < 60)    return "now"
        if (s < 3600)  return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }
}
