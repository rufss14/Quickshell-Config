import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../notifications"

// ── OverviewFeed ──────────────────────────────────────────────────────────────
// The overview's drawer (More): one card beside the workspaces, one page at a time, a rail of
// stops under it (SlidingTabs):
//
//     0  What's new       FeedChanges     the version you're on and its patch notes
//     1  Ask              FeedAssistant   a chat that changes the shell (Assistant)
//     2  News             FeedNews        near you or the world (News)
//     3  Notifications    NotificationCentre — the same body and tiles as the bar's panel
//
// The page you were on is Config.overviewFeedPage (a saved setting and VoiceOrb's jump to Ask
// name pages by these indexes, so a new page is appended, not inserted).
//
// A page is built only while it is in view or passing, so one you are not on costs nothing; what must
// survive (the chat, the stories) lives in the services. Each page scrolls its own list natively.
// A page takes `current` (it is the one on show) and `accent` from here.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool shown: false
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var pages: [
        { symbol: "update",        label: Translation.tr("What's new"), badge: Changelog.unseen > 0 },
        { symbol: "auto_awesome",  label: Translation.tr("Ask") },
        { symbol: "newspaper",     label: Translation.tr("News") },
        { symbol: "notifications", label: Translation.tr("Notifications"), badge: Notifications.unseen > 0 }
    ]
    readonly property int count: root.pages.length

    property int index: Math.max(0, Math.min(root.count - 1, Config.overviewFeedPage))

    function go(i) {
        const n = Math.max(0, Math.min(root.count - 1, i))
        if (n === root.index) return
        root.index = n
        Config.overviewFeedPage = n
    }

    // Where the pages are, in pages: it follows `index` on a spring, and a page's offset from it
    // is how far it has slid and faded.
    SpringValue { id: at; target: root.index; spec: Motion.springSpatial; epsilon: 0.002 }

    // ── The rail: a stop per page, under the pages ────────────────────────────
    SlidingTabs {
        id: rail
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: implicitWidth
        height: implicitHeight
        model: root.pages
        position: root.index
        animate: true
        accent: root.accent
        onPicked: index => root.go(index)
    }

    // ── The pages ─────────────────────────────────────────────────────────────
    Item {
        id: viewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: rail.top
        anchors.bottomMargin: Tokens.spacingMd
        clip: true

        Repeater {
            model: root.count
            delegate: Loader {
                id: page
                required property int index
                readonly property real d: page.index - at.value
                width: viewport.width
                height: viewport.height
                x: page.d * Tokens.spacingXxl
                opacity: 1 - Math.min(1, Math.abs(page.d))
                visible: Math.abs(page.d) < 1
                active: root.shown && (Math.abs(page.d) < 1 || page.index === root.index)
                sourceComponent: page.index === 0 ? changesPage : page.index === 1 ? askPage
                               : page.index === 2 ? newsPage : notesPage
                Binding { when: page.item !== null; target: page.item; property: "current"; value: root.shown && page.index === root.index }
                Binding { when: page.item !== null; target: page.item; property: "accent"; value: root.accent }
            }
        }

        Component { id: changesPage; FeedChanges {} }
        Component { id: askPage; FeedAssistant {} }
        Component { id: newsPage; FeedNews {} }
        // The notification centre takes its place in the drawer's contract (`current`, `accent`).
        Component {
            id: notesPage
            Item {
                property bool current: false
                property color accent: Colors.of(QsWindow.window).primary
                NotificationCentre {
                    anchors.fill: parent
                    compact: true
                    fill: true
                }
            }
        }
    }

    // A page that runs past the rail dissolves into the card instead of ending in a hard cut mid-line:
    // a gradient in the card's own colour OVER the viewport (a MultiEffect alpha mask on the viewport's
    // layer drew nothing here). Bottom only: the top holds the page's header. It takes no input.
    Rectangle {
        z: 2
        anchors.left: viewport.left
        anchors.right: viewport.right
        anchors.bottom: viewport.bottom
        height: Tokens.spacingXl * 1.5
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard), 0) }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard), 0.96) }
        }
    }
}
