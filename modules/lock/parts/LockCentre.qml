pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../overview"
import "../../discord"

// ── LockCentre ── part of LockScreen.qml; `lockSurface` is its lock surface (one per screen). ──
ColumnLayout {
    id: centre
    required property var lockSurface
    property alias field: field
    property alias shake: shake

    anchors.centerIn: parent
    // Wide enough for the surface.clock to live INSIDE it. A monospace "01:06" at 120px
    // is five full-width advances — about 360px — so the old 340 column would
    // have had the time overflowing its own container the moment the font
    // changed, which is the sort of thing that looks fine until the hour ticks
    // over to a wider digit.
    width: Math.min(lockSurface.width - Tokens.spacingXxl * 2, 420)
    spacing: 0

    scale: lockSurface.contentScale

    // ── Time ──────────────────────────────────────────────────────────
    // Light, not bold. At this size weight reads as shouting, and the surface.clock is
    // the thing you glance at, not the thing you act on — the field below it is.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        opacity: lockSurface.reveal
        transform: Translate { y: (1 - lockSurface.reveal) * -16 }

        // ── Why this is fillWidth + AlignHCenter, not AlignHCenter ────
        // It was `Layout.alignment: Qt.AlignHCenter` with `letterSpacing: -2`,
        // and it sat visibly off-centre. Qt applies letter spacing as an advance
        // AFTER every character including the last, so the measured width carries
        // a trailing -2px that has nothing drawn in it, and centring the BOX
        // therefore does not centre the GLYPHS. Letting the text span the full
        // column and centring inside it makes the metric irrelevant — the fix
        // holds whatever the font or the spacing does later.
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(lockSurface.clock.date, "HH:mm")
            // ── Blocky ────────────────────────────────────────────
            // Tokens has already walked the installed families and handed back
            // one that exists. CodeNewRoman's mono was the first attempt at
            // "blocky" and it is not — it is a typewriter face, which at this size
            // reads thin and narrow. A geometric extra-bold is what the word
            // actually means.
            //
            // Still monospace, and that still earns its place twice over: every
            // digit is the same width, so the time does not shuffle sideways when
            // 01:09 becomes 01:10.
            font.family: Tokens.fontBlock
            font.pixelSize: Tokens.fontHero
            font.weight: Font.ExtraBold
            color: Colors.of(QsWindow.window).fg
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingSm
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(lockSurface.clock.date, "dddd, d MMMM")
            variant: "body"
            emphasis: "dim"
            // Opened up to sit under the mono surface.clock as a deliberate contrast
            // rather than looking like it wanted to match and missed.
            font.letterSpacing: 2
        }
    }

    // ── The auth block ────────────────────────────────────────────────
    // Avatar, name, field, feedback — grouped, and entering a beat after the
    // surface.clock so the eye lands on the time and is then led down to the thing it
    // has to do.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingXxl + Tokens.spacingXl
        spacing: 0

        opacity: lockSurface.revealLate
        transform: Translate { y: (1 - lockSurface.revealLate) * 30 }

        // ── The login capsule ─────────────────────────────────────────
        // Who, what to type, and a way to send it, in ONE pill: the avatar on the
        // left answers "whose password is this box expecting" (which is otherwise
        // unanswerable until you have already got it wrong), the name sits over the
        // field, and a round button on the right submits — a visible way to finish
        // that is not "press Enter and hope". Enter still works.
        //
        // Wrapped in a plain Item so the shake below has something to move it
        // WITHIN — animating a laid-out child's own position fights the layout,
        // which reasserts it on the next pass.
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth:  380
            implicitHeight: 68

            Surface {
                id: fieldBox
                anchors.centerIn: parent
                width:  380
                height: 68
                elevation: Tokens.elevationCard
                // Fully round at rest, but through the shared corner language
                // rather than around it: `squareMode` is what every pill in the
                // bar binds, so turning the shell square squares this too.
                squareMode:   Config.barShape
                cornerRadius: height / 2
                focused:      field.activeFocus

                // Translucent, tracking the same surface-opacity setting as the
                // bar and the panels. This is the one surface in the shell where
                // that works without a compositor blur rule: the lock is the
                // topmost surface and drew its own blurred backdrop a few lines
                // up — so the glass is real here rather than a request.
                fillOpacity: Config.surfaceOpacity

                // The one place colour is spent: the border goes danger on a
                // rejected password. On this palette `danger` and `primary` can
                // resolve to the same colour (see PowerPanel), so this is a
                // supporting cue — the message line below is what actually says
                // what happened.
                border.color: lockSurface.noticeIsError ? Colors.of(QsWindow.window).danger
                            : field.activeFocus     ? Colors.of(QsWindow.window).outlineFocus
                            :                         Colors.of(QsWindow.window).outlineFor(Tokens.elevationCard)
                Behavior on border.color { ColorAnimation { duration: Motion.standard } }

                // ── Avatar ────────────────────────────────────────────
                // A monogram by default, a photo if this machine happens to have one.
                Item {
                    id: avatar
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    width:  52
                    height: 52

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.16)
                        border.width: Tokens.borderWidth
                        // Picks up the focus tint while PAM is thinking, so the thing you
                        // are looking at is the thing that reacts.
                        border.color: lockSurface.noticeIsError ? Colors.of(QsWindow.window).danger
                                    : lockSurface.busy          ? Colors.of(QsWindow.window).outlineFocus
                                    :                         Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).text, 0.28)
                        Behavior on border.color { ColorAnimation { duration: Motion.standard } }

                        StyledText {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: lockSurface.userName === "" ? "?" : lockSurface.userName.charAt(0).toUpperCase()
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontDisplay
                            font.weight: Font.Medium
                            color: Colors.of(QsWindow.window).primary
                        }
                    }

                    // MASKED, not clipped. `clip` is rectangular — it knows nothing about
                    // `radius`, so a clipped photo keeps its square corners and pokes out
                    // of the circle. Same idiom as the Discord call avatars.
                    Item {
                        anchors.fill: parent
                        anchors.margins: Tokens.borderWidth

                        layer.enabled: true
                        layer.smooth:  true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource:  avatarMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin:  1.0
                        }

                        Image {
                            id: face
                            anchors.fill: parent
                            source: lockSurface.facePath === "" ? "" : "file://" + lockSurface.facePath
                            // 2× the drawn size for HiDPI, then mipmapped — decoding at
                            // the drawn size and point-sampling makes a small round photo
                            // look soft.
                            sourceSize: Qt.size(128, 128)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            mipmap: true
                            smooth: true
                            visible: face.status === Image.Ready
                        }
                    }

                    Item {
                        id: avatarMask
                        anchors.fill: parent
                        anchors.margins: Tokens.borderWidth
                        layer.enabled: true
                        visible: false
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "white"
                        }
                    }
                }

                // ── Submit ────────────────────────────────────────────
                // Never disabled and never hidden, like the field: submit() itself
                // ignores an empty field or an attempt already running. The spinner
                // replaces the arrow while PAM thinks, so "checking" is on the thing
                // you pressed.
                Rectangle {
                    id: go
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    width:  52
                    height: 52
                    radius: width / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary,
                               goHover.hovered || field.text !== "" ? 1.0 : 0.82)
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                    scale: goTap.pressed ? 0.92 : (goHover.hovered ? 1.05 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 6.0; damping: 0.34; epsilon: 0.002 } }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: !lockSurface.busy
                        name: "chevron_right"
                        variant: "headline"
                        color: Colors.of(QsWindow.window).fgOnPrimary
                    }
                    BusyDot {
                        anchors.centerIn: parent
                        running: lockSurface.busy
                        tint:    Colors.of(QsWindow.window).fgOnPrimary
                    }

                    HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { id: goTap; onTapped: lockSurface.submit() }
                }

                // ── Name over the field ───────────────────────────────
                ColumnLayout {
                    anchors.left:  avatar.right
                    anchors.right: go.left
                    anchors.leftMargin:  Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        visible: lockSurface.userName !== ""
                        text: lockSurface.userName
                        variant: "caption"
                        font.weight: Font.DemiBold
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }

                    TextInput {
                        id: field
                        Layout.fillWidth: true

                        verticalAlignment: TextInput.AlignVCenter

                        // NEVER disabled, even mid-authentication. A field that stops
                        // accepting input while PAM is thinking is indistinguishable
                        // from a lockscreen that has hung, which is the single most
                        // alarming thing this surface could do. Submission is what is
                        // gated (see submit()), not typing.
                        enabled: true
                        focus:   true

                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        // The default 1-second reveal of the last character is a
                        // shoulder-surfing hole on a screen that is, by definition,
                        // visible to whoever is standing there.
                        passwordMaskDelay: 0

                        color: Colors.of(QsWindow.window).fg
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontBody
                        selectionColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.35)
                        selectedTextColor: Colors.of(QsWindow.window).fg
                        clip: true

                        // No `text:` binding — see the note on surface state above.
                        onAccepted: lockSurface.submit()

                        // Focus is taken back whenever the lock appears. The session
                        // lock protocol hands this surface exclusive keyboard input,
                        // so there is nothing to compete with — but the FIELD still
                        // has to be the thing inside the surface holding it.
                        Component.onCompleted: field.forceActiveFocus()

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible:  field.text === "" && !lockSurface.busy
                            text:     "Password"
                            variant:  "body"
                            emphasis: "dim"
                        }
                    }
                }
            }

            // A short, sharp horizontal shake on rejection. Durations are
            // literals, not Motion tokens, and deliberately: this is a fixed
            // physical gesture rather than a transition, and running it through
            // Config.motionScale would turn a 2× preference into a wobble. The
            // preference that DOES apply — motion off entirely — is honoured by
            // reject() simply not starting it.
            SequentialAnimation {
                id: shake
                NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to:  9; duration: 45 }
                NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to: -8; duration: 65 }
                NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to:  5; duration: 60 }
                NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to:  0; duration: 55 }
            }
        }

        // ── One line of feedback ──────────────────────────────────────
        // Fixed height and always present, so the layout never jumps under the
        // field you are typing in. "Checking" is the spinner on the submit button;
        // this line is for what came back ("wrong password").
        Item {
            Layout.fillWidth:  true
            Layout.topMargin:  Tokens.spacingLg
            implicitHeight: 18

            StyledText {
                anchors.centerIn: parent
                width:   parent.width
                visible: !lockSurface.busy
                horizontalAlignment: Text.AlignHCenter
                text:    lockSurface.notice
                variant: "caption"
                color:   lockSurface.noticeIsError ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                elide:   Text.ElideRight
            }
        }

        // Only from the second failure on. One wrong password is a typo and
        // saying "1 failed attempt" about it is nagging; a count that you did not
        // put there yourself is worth seeing.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            visible: lockSurface.attempts > 1 && !lockSurface.busy
            horizontalAlignment: Text.AlignHCenter
            text: lockSurface.attempts + " failed attempts"
            variant: "micro"
            color: Colors.of(QsWindow.window).fgDim
        }

        // ── The compositor did not honour the lock ────────────────────
        // Rare, and worth shouting about: `secure` false means the surface is
        // drawn but the session is not actually locked, so anyone can get past
        // it. Better to say so than to imply a protection that is not there.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingLg
            visible: !Lock.secure
            horizontalAlignment: Text.AlignHCenter
            text: "This session is NOT securely locked — the compositor refused the lock."
            variant: "caption"
            color:   Colors.of(QsWindow.window).warning
            wrapMode: Text.WordWrap
        }
    }
}
