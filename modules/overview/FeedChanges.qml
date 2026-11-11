import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"

// ── FeedChanges ───────────────────────────────────────────────────────────────
// The left face's "What's changed" page (OverviewFeed): the patch notes (services/Changelog,
// assets/changelog.json). The newest release is the page:
//   · a hero card — the version on a turning cookie, the release's name and date, "New" when you
//     haven't seen it, its one-paragraph summary (no glow or sheen — the user didn't like them);
//   · the highlights, a row each (an icon, a title, a sentence);
//   · the sections (FeedNoteSection), cards that show three lines and open to all of them;
//   · older releases under "Earlier", folded, each opening to its own sections.
// Everything rises in a beat after the one above (ViewEnter) each time the page comes into view.
// After two seconds on the page the notes count as seen (Config.changelogSeen); what was new stays
// marked for the rest of this look (`seenAtOpen`).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool current: false
    property color accent: Colors.of(QsWindow.window).primary
    readonly property Flickable flick: scroller

    readonly property var latest: Changelog.latest
    readonly property var older: Changelog.versions.slice(1)
    // What was seen when this page was built (assigned once, not a binding — see the header).
    property string seenAtOpen: ""
    Component.onCompleted: root.seenAtOpen = Config.changelogSeen
    function wasNew(v) {
        if (root.seenAtOpen === "") return true
        const a = v.split(".").map(Number), b = root.seenAtOpen.split(".").map(Number)
        for (let i = 0; i < Math.max(a.length, b.length); i++)
            if ((a[i] || 0) !== (b[i] || 0)) return (a[i] || 0) > (b[i] || 0)
        return false
    }

    // The cascade plays each time the page comes into view (a beat after, so it's on screen).
    property bool lit: false
    onCurrentChanged: { root.lit = false; if (root.current) litSoon.restart() }
    Timer { id: litSoon; interval: 60; onTriggered: root.lit = root.current }
    Timer { interval: 2000; running: root.current; onTriggered: Changelog.markSeen() }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        FeedHeader {
            Layout.fillWidth: true
            Layout.fillHeight: false
            symbol: "update"
            title: Translation.tr("What's")
            tail: Translation.tr("new")
            accent: root.accent
            hot: heroHover.hovered
            subtitle: !root.latest ? ""
                    : root.seenAtOpen !== "" && root.wasNew(root.latest.version) ? Translation.tr("New since v%1").arg(root.seenAtOpen)
                    : "Quicktest v" + root.latest.version + (root.latest.date ? "  ·  " + Changelog.dateLabel(root.latest.date) : "")
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: scroller
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: body.implicitHeight + Tokens.spacingLg
                boundsBehavior: Flickable.StopAtBounds
                // Scrolled by the face's wheel and drag (OverviewFeed); a mouse drag here is the swipe.
                interactive: false

                Column {
                    id: body
                    width: scroller.width
                    spacing: Tokens.spacingMd

                    // ── The release ─────────────────────────────────────────────
                    ClippingRectangle {
                        id: hero
                        visible: root.latest !== null
                        width: body.width
                        height: heroCol.implicitHeight + Tokens.spacingLg * 2
                        radius: Tokens.radiusCard
                        color: Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceContainer, 0.92)
                        border.width: Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).alpha(root.accent, 0.45)
                        ViewEnter { target: hero; active: root.lit; rise: Tokens.spacingXl }

                        Column {
                            id: heroCol
                            x: Tokens.spacingLg
                            y: Tokens.spacingLg
                            width: hero.width - Tokens.spacingLg * 2
                            spacing: Tokens.spacingMd

                            Row {
                                spacing: Tokens.spacingLg
                                Item {
                                    width: Tokens.sideCardUnit * 1.7
                                    height: Tokens.sideCardUnit * 1.7
                                    ShapeBox {
                                        anchors.fill: parent
                                        fallback: "cookie"
                                        fillColor: Colors.of(QsWindow.window).alpha(root.accent, heroHover.hovered ? 0.34 : 0.22)
                                        strokeColor: Colors.of(QsWindow.window).alpha(root.accent, 0.7)
                                        strokeWidth: 2
                                        Behavior on fillColor { ColorAnimation { duration: Motion.respond } }
                                        RotationAnimator on rotation {
                                            from: 0; to: 360
                                            duration: 30000
                                            loops: Animation.Infinite
                                            running: root.current && Motion.ambientOn
                                        }
                                    }
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: root.latest ? "v" + root.latest.version : ""
                                        variant: "title"
                                        font.weight: Font.Bold
                                        color: root.accent
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: heroCol.width - Tokens.sideCardUnit * 1.7 - Tokens.spacingLg
                                    spacing: Tokens.spacingXs
                                    Row {
                                        spacing: Tokens.spacingSm
                                        Rectangle {
                                            visible: root.latest !== null && root.wasNew(root.latest.version)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: newText.implicitWidth + Tokens.spacingMd
                                            height: newText.implicitHeight + Tokens.spacingXs
                                            radius: height / 2
                                            color: root.accent
                                            StyledText {
                                                id: newText
                                                anchors.centerIn: parent
                                                text: Translation.tr("New")
                                                variant: "micro"
                                                font.weight: Font.Bold
                                                color: root.accent.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg
                                            }
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.latest ? Changelog.dateLabel(root.latest.date) : ""
                                            variant: "caption"
                                            emphasis: "dim"
                                        }
                                    }
                                    StyledText {
                                        width: parent.width
                                        text: root.latest ? root.latest.name : ""
                                        variant: "headline"
                                        font.weight: Font.Bold
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                            StyledText {
                                width: heroCol.width
                                text: root.latest ? root.latest.summary : ""
                                variant: "caption"
                                emphasis: "muted"
                                wrapMode: Text.Wrap
                            }
                        }
                        HoverHandler { id: heroHover }
                    }

                    // ── A newer release than this one, out already ──────────────
                    Rectangle {
                        id: outNow
                        visible: ShellUpdate.available
                        width: body.width
                        height: outRow.implicitHeight + Tokens.spacingMd * 2
                        radius: Tokens.radiusCard - Tokens.spacingXs
                        color: Colors.of(QsWindow.window).alpha(root.accent, 0.16)
                        Row {
                            id: outRow
                            x: Tokens.spacingMd
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.spacingSm
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "celebration"
                                color: root.accent
                                font.pixelSize: Tokens.iconMd
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: outNow.width - Tokens.spacingMd * 2 - Tokens.iconMd - Tokens.spacingSm
                                text: Translation.tr("v%1 is out — the update panel installs it.").arg(ShellUpdate.latest)
                                variant: "caption"
                                font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    // ── Highlights ──────────────────────────────────────────────
                    StyledText {
                        id: hiTitle
                        visible: root.latest !== null && (root.latest.highlights ?? []).length > 0
                        topPadding: Tokens.spacingSm
                        text: Translation.tr("Highlights")
                        variant: "label"
                        font.weight: Font.DemiBold
                        emphasis: "muted"
                        ViewEnter { target: hiTitle; active: root.lit; delay: Motion.stagger * 2 }
                    }
                    Repeater {
                        model: root.latest ? (root.latest.highlights ?? []) : []
                        delegate: Rectangle {
                            id: hi
                            required property var modelData
                            required property int index
                            width: body.width
                            height: hiRow.implicitHeight + Tokens.spacingMd * 2
                            radius: Tokens.radiusCard - Tokens.spacingXs
                            color: Colors.of(QsWindow.window).fade(hiHover.hovered
                                       ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh, root.accent, 0.1)
                                       : Colors.of(QsWindow.window).surfaceContainer, 0.88)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            ViewEnter { target: hi; active: root.lit; delay: Motion.stagger * (3 + hi.index) }
                            Row {
                                id: hiRow
                                x: Tokens.spacingMd
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.spacingMd
                                ScallopChip {
                                    id: hiChip
                                    anchors.verticalCenter: parent.verticalCenter
                                    symbol: hi.modelData.symbol
                                    tint: root.accent
                                    hot: hiHover.hovered
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: hi.width - Tokens.spacingMd * 3 - hiChip.width
                                    spacing: 1
                                    StyledText {
                                        width: parent.width
                                        text: hi.modelData.title
                                        variant: "body"
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        width: parent.width
                                        text: hi.modelData.text
                                        variant: "caption"
                                        emphasis: "dim"
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                            HoverHandler { id: hiHover }
                        }
                    }

                    // ── Everything, by part of the shell ────────────────────────
                    StyledText {
                        id: allTitle
                        visible: root.latest !== null
                        topPadding: Tokens.spacingSm
                        text: Translation.tr("Everything new")
                        variant: "label"
                        font.weight: Font.DemiBold
                        emphasis: "muted"
                        ViewEnter { target: allTitle; active: root.lit; delay: Motion.stagger * 9 }
                    }
                    Repeater {
                        model: root.latest ? root.latest.sections : []
                        delegate: FeedNoteSection {
                            required property var modelData
                            required property int index
                            width: body.width
                            section: modelData
                            accent: root.accent
                            lit: root.lit
                            delay: Motion.stagger * (10 + Math.min(index, 8))
                        }
                    }

                    // ── Earlier releases ────────────────────────────────────────
                    StyledText {
                        visible: root.older.length > 0
                        topPadding: Tokens.spacingSm
                        text: Translation.tr("Earlier")
                        variant: "label"
                        font.weight: Font.DemiBold
                        emphasis: "muted"
                    }
                    Repeater {
                        model: root.older
                        delegate: Rectangle {
                            id: rel
                            required property var modelData
                            property bool open: false
                            width: body.width
                            height: relCol.implicitHeight + Tokens.spacingMd * 2
                            Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                            clip: true
                            radius: Tokens.radiusCard - Tokens.spacingXs
                            color: Colors.of(QsWindow.window).fade(relHover.hovered && !rel.open
                                       ? Colors.of(QsWindow.window).surfaceHigh : Colors.of(QsWindow.window).surfaceContainer, 0.88)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            Column {
                                id: relCol
                                x: Tokens.spacingMd
                                y: Tokens.spacingMd
                                width: rel.width - Tokens.spacingMd * 2
                                spacing: Tokens.spacingMd
                                Item {
                                    width: relCol.width
                                    height: Math.max(relPill.height, relText.implicitHeight)
                                    Rectangle {
                                        id: relPill
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: relV.implicitWidth + Tokens.spacingMd
                                        height: relV.implicitHeight + Tokens.spacingXs * 2
                                        radius: height / 2
                                        color: Colors.of(QsWindow.window).alpha(root.accent, 0.18)
                                        StyledText {
                                            id: relV
                                            anchors.centerIn: parent
                                            text: "v" + rel.modelData.version
                                            variant: "caption"
                                            font.weight: Font.Bold
                                            color: root.accent
                                        }
                                    }
                                    Column {
                                        id: relText
                                        anchors.left: relPill.right
                                        anchors.leftMargin: Tokens.spacingSm
                                        anchors.right: relChev.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        StyledText {
                                            width: parent.width
                                            text: rel.modelData.name
                                            variant: "body"
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            width: parent.width
                                            text: Changelog.dateLabel(rel.modelData.date)
                                            variant: "caption"
                                            emphasis: "dim"
                                        }
                                    }
                                    MaterialIcon {
                                        id: relChev
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "expand_more"
                                        color: Colors.of(QsWindow.window).fgMuted
                                        font.pixelSize: Tokens.iconMd
                                        rotation: rel.open ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
                                    }
                                    HoverHandler { id: relHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: rel.open = !rel.open }
                                }
                                StyledText {
                                    visible: rel.open
                                    width: relCol.width
                                    text: rel.modelData.summary
                                    variant: "caption"
                                    emphasis: "dim"
                                    wrapMode: Text.Wrap
                                }
                                Repeater {
                                    model: rel.open ? rel.modelData.sections : []
                                    delegate: FeedNoteSection {
                                        required property var modelData
                                        required property int index
                                        width: relCol.width
                                        section: modelData
                                        accent: root.accent
                                        flat: true
                                        lit: rel.open
                                        delay: Motion.stagger * index
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Scrollbar { flickable: scroller }
        }
    }
}
