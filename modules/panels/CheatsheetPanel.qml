pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── CheatsheetPanel ───────────────────────────────────────────────────────────
// Every keybind in the user's Hyprland config, grouped and searchable.
//
// ── It reads the config, not hyprctl ──────────────────────────────────────────
// None of this is new plumbing: HyprConfig already parses binds.lua for the Hyprland
// settings page, because `hyprctl binds` reports a Lua-defined bind as an opaque
// `__lua` callback and so cannot say what any of them DO. That parse produces exactly
// the record a cheatsheet wants — combo, description, resolved action text, and the
// section comment it was declared under — and until now only one settings page ever
// looked at it. hypr-config.py's own comments even talk about expanding for-loop binds
// "so they show in the cheatsheet". This is that cheatsheet.
//
// ── Refcounted, like every other HyprConfig consumer ──────────────────────────
// The service reads three .lua files and watches them. Nothing should run while the
// sheet is closed, so this acquires on show and releases on hide rather than at
// construction — the window itself stays cheap.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Driven by the window. Acquire/release follow it rather than the component's
    // lifetime, so a closed sheet holds no watches.
    property bool shown: false

    signal closeRequested()

    onShownChanged: {
        if (root.shown) {
            HyprConfig.acquire()
        } else {
            HyprConfig.release()
            root.query = ""
        }
    }
    Component.onDestruction: if (root.shown) HyprConfig.release()

    property string query: ""

    // ── Grouping ──────────────────────────────────────────────────────────────
    // By the section comment the bind sits under in binds.lua, which is the author's
    // own organisation — better than anything we could infer from the dispatcher, and
    // it means the sheet reorganises itself when the config is reorganised.
    //
    // Binds with no section land in one "Other" group at the end rather than each
    // becoming a group of one.
    readonly property var groups: {
        const q = root.query.trim().toLowerCase()
        const out = []
        const byName = ({})

        for (const b of HyprConfig.binds) {
            if (!b) continue

            // Search covers the things you'd actually reach for: the keys, what it
            // does, and the user's own description.
            if (q !== "") {
                const hay = ((b.combo || "") + " "
                           + (b.desc || "") + " "
                           + ((b.action && b.action.text) || "") + " "
                           + (b.section || "")).toLowerCase()
                if (hay.indexOf(q) < 0) continue
            }

            const name = (b.section || "").trim() || "Other"
            if (byName[name] === undefined) {
                byName[name] = out.length
                out.push({ name: name, binds: [] })
            }
            out[byName[name]].binds.push(b)
        }

        // "Other" last — it is the leftovers, not a peer of the named sections.
        out.sort((a, b) => (a.name === "Other") - (b.name === "Other"))
        return out
    }

    readonly property int matchCount: {
        let n = 0
        for (const g of root.groups) n += g.binds.length
        return n
    }

    function focusSearch() { search.forceFocus() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingLg

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingMd

            StyledText { text: "Keybinds"; variant: "title" }

            StyledText {
                // The count answers "did my search find anything" without a separate
                // empty state having to appear and shift the layout.
                text: HyprConfig.reading ? "reading config…"
                    : root.query === "" ? root.matchCount + " binds"
                                        : root.matchCount + " of " + HyprConfig.binds.length
                variant: "caption"
                emphasis: "dim"
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: Translation.tr("ESC to close")
                variant: "caption"
                emphasis: "dim"
            }
        }

        InputField {
            id: search
            Layout.fillWidth: true
            placeholder: Translation.tr("Search keys, actions or sections…")
            // Live, not on commit: this is a filter, and a filter that only applies
            // when you click away is not a filter.
            onEdited: function(value) { root.query = value }
        }

        // ── The binds ─────────────────────────────────────────────────────────
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: sheet.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ColumnLayout {
                id: sheet
                width: parent.width
                spacing: Tokens.spacingLg

                Repeater {
                    model: root.groups

                    ColumnLayout {
                        id: group
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        StyledText {
                            text: group.modelData.name
                            variant: "label"
                            emphasis: "muted"
                        }

                        Repeater {
                            model: group.modelData.binds

                            RowLayout {
                                id: bindRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Tokens.spacingMd

                                // The combo, in mono so the modifiers line up down the
                                // column and the sheet can be scanned by shape.
                                StyledText {
                                    Layout.preferredWidth: 190
                                    text: bindRow.modelData.combo || "—"
                                    variant: "body"
                                    font.family: Tokens.fontMono
                                    color: Colors.of(QsWindow.window).primary
                                    elide: Text.ElideRight
                                }

                                // The user's own description wins over the derived
                                // action text: they wrote it precisely because the
                                // dispatcher name wasn't the point.
                                StyledText {
                                    Layout.fillWidth: true
                                    text: (bindRow.modelData.desc || "").trim() !== ""
                                        ? bindRow.modelData.desc
                                        : ((bindRow.modelData.action
                                            && bindRow.modelData.action.text) || "")
                                    variant: "body"
                                    elide: Text.ElideRight
                                }

                                // Mouse binds behave differently enough to be worth
                                // marking — you can't press them from the keyboard.
                                Badge {
                                    visible: bindRow.modelData.mouse === true
                                    label: "mouse"
                                }
                            }
                        }
                    }
                }

                // ── Nothing matched ───────────────────────────────────────────
                // Distinguishes "your search found nothing" from "the config has no
                // binds", because those want completely different reactions from you.
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingXl
                    visible: root.matchCount === 0 && !HyprConfig.reading
                    horizontalAlignment: Text.AlignHCenter
                    text: root.query !== ""
                        ? "No bind matches “" + root.query + "”"
                        : "No binds found — is your Hyprland config .lua and where "
                          + "the shell expects it?"
                    variant: "body"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Keys.onEscapePressed: root.closeRequested()
}
