import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/launcher.js" as Logic

// ── LauncherField ─────────────────────────────────────────────────────────────
// The launcher's search pill: a glyph that says what Enter will do, the mode chip, the
// text, and ONE trailing button — stop while an answer is streaming, clear while there
// is text, otherwise help. (It used to be four buttons in a row, three of which only
// made sense some of the time; one slot that changes is easier to read than four that
// each might be hidden.)
//
// It owns the text and the prefix rule, and nothing else: keys are handed up
// (`keyed`) so the panel decides what each means in exactly one place.
//
// ── The prefix is CONSUMED, not carried ───────────────────────────────────────
// Typing `>`, `?` or `+` into an EMPTY field switches mode and the character disappears
// into the chip. A mode you can see is worth more than a character you have to notice,
// and the field then holds only what you meant to type — which is also what lets a
// chat follow-up work without retyping `?` every turn. Only when the field was empty:
// backspacing "a?" down to "?" is editing, not choosing a mode.
//
// ── M3E ───────────────────────────────────────────────────────────────────────
// The leading mark sits on an expressive shape that MORPHS with the mode (`shape`, set by
// the panel: a cookie at rest, a squircle for run, a sunburst for ask…) and turns to the
// accent when a mode is up; the glyph pops in on a spring when it changes and gives a small
// nudge for each letter typed. The mode chip is a tonal pill whose width springs open from
// nothing, so the text slides over to meet it.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    property string mode: ""            // "" | "run" | "ask" | "pkg" | "clip" | "emoji" — owned by the panel
    property string modeLabel: ""
    property string shape: "cookie9"    // the badge's M3E shape (MorphShape)
    property string icon: "search"      // Material Symbols name for the leading mark
    property bool   busy: false         // an answer is streaming → trailing Stop
    property bool   helpOpen: false
    // What the empty field says. In a mode or a chat it is just `placeholder`; otherwise
    // `lead` stays put and the field types one of `hints` after it — [{ key, text }] — and
    // erases it for the next, so it teaches its own prefixes while it is empty.
    property string placeholder: ""
    property string lead: ""
    property var    hints: []

    readonly property var pal: Colors.of(QsWindow.window)

    readonly property alias text: input.text
    readonly property bool editing: input.activeFocus

    // The text changed (after a mode prefix was taken out of it).
    signal edited(string text)
    // A prefix character was typed into the empty field; the panel sets the mode.
    signal prefixTyped(string mode)
    signal keyed(var event)
    signal stopRequested()
    signal helpToggled()

    function setText(t) { input.text = t }
    function clear()    { input.text = "" }
    function focusInput() { input.forceActiveFocus() }

    elevation:    Tokens.elevationNested
    cornerRadius: Tokens.radiusPill
    focused:      input.activeFocus

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingSm
        spacing: Tokens.spacingMd

        // The magnifier gives way to the mode's own glyph — the icon says what Enter
        // will do, which is what the prefix character was only hinting at. In ask mode
        // it is the provider's own mark, so the bar says WHO is answering.
        Item {
            id: badge
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  Tokens.iconXl + Tokens.spacingXs * 2
            implicitHeight: implicitWidth

            // The glyph's pop (a spring with overshoot), kicked by a mode change and,
            // gently, by every letter.
            SpringValue { id: pop; spec: Motion.springSpatialFast; target: 1; epsilon: 0.001 }
            Connections {
                target: root
                function onIconChanged() { pop.jump(0.55) }
                function onModeChanged() { pop.jump(0.55) }
                function onEdited() { pop.kick(1.2) }
            }

            MorphShape {
                anchors.fill: parent
                shape: root.shape
                fillColor: root.mode !== "" ? root.pal.primary : root.pal.primaryContainer
                Behavior on fillColor { ColorAnimation { duration: Motion.respond } }
            }
            Item {
                anchors.fill: parent
                scale: pop.value

                AiMark {
                    anchors.centerIn: parent
                    size: Tokens.iconMd
                    visible: root.mode === "ask"
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.mode !== "ask"
                    name: root.icon
                    color: root.mode !== "" ? root.pal.fgOnPrimary : root.pal.fgOnPrimaryContainer
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
            }
        }

        // Sized to zero with no mode, so the text slides over to meet it rather than the
        // chip popping in on top. Its label is held (set on the way in, kept on the way
        // out): a chip that empties itself the instant the mode clears shrinks blank.
        Rectangle {
            id: chip
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Math.max(0, chipW.value)
            Layout.preferredHeight: chipLabel.implicitHeight + Tokens.spacingSm * 2
            visible: Layout.preferredWidth > 0.5
            opacity: Math.max(0, Math.min(1, chipA.value))
            clip: true
            radius: height / 2
            color: root.pal.primaryContainer

            property string held: ""
            Connections {
                target: root
                function onModeLabelChanged() { if (root.modeLabel !== "") chip.held = root.modeLabel }
            }
            Component.onCompleted: if (root.modeLabel !== "") chip.held = root.modeLabel

            SpringValue {
                id: chipW
                spec: Motion.springSpatial
                target: root.mode !== "" ? chipLabel.implicitWidth + Tokens.spacingMd * 2 : 0
            }
            SpringValue { id: chipA; spec: Motion.springEffects; target: root.mode !== "" ? 1 : 0; epsilon: 0.002 }

            StyledText {
                id: chipLabel
                anchors.centerIn: parent
                text: chip.held
                variant: "caption"
                font.weight: Font.DemiBold
                color: root.pal.fgOnPrimaryContainer
            }
        }

        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            TextInput {
                id: input
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                font.family:    Tokens.fontFamily
                font.pixelSize: Tokens.fontBody
                color:             Colors.of(QsWindow.window).fg
                selectionColor:    Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.28)
                selectedTextColor: Colors.of(QsWindow.window).fg
                clip: true

                property int _prevLen: 0

                onTextChanged: {
                    const was = input._prevLen
                    input._prevLen = text.length
                    if (root.mode === "" && was === 0 && text.length > 0) {
                        const m = Logic.modeFor(text.charAt(0))
                        // `+`, `;` and `:` are each a switch (Settings › Launcher): off, they
                        // are just the character.
                        if (m !== "" && Launcher.modeEnabled(m)) {
                            root.prefixTyped(m)
                            text = text.slice(1)
                            return          // re-enters with the rest
                        }
                    }
                    root.edited(text)
                }

                // Return, Escape and the arrows are not consumed by a TextInput, so the
                // panel gets them from here and from its own root alike.
                Keys.onPressed: function(ev) { Sfx.typed(ev.key, ev.text, ev.modifiers); root.keyed(ev) }

                // ── The placeholder, typed out ────────────────────────────────────
                // "Search apps" stays; after it the field types a hint — the key, then
                // what it does — holds it, erases it, and types the next
                // (components/TypedPlaceholder, shared with the settings and wallpaper
                // searches). Only while the field is empty.
                TypedPlaceholder {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    placeholder: root.placeholder
                    lead: root.lead
                    hints: root.hints
                    variant: "body"
                }
            }
        }

        // One slot: stop > clear > help. Never more than one of them shown.
        PanelButton {
            Layout.alignment: Qt.AlignVCenter
            variant: root.busy || root.helpOpen ? "primary" : "ghost"
            accent:  Colors.of(QsWindow.window).primary
            symbol:  root.busy ? "stop" : input.text.length > 0 ? "close" : "help"
            implicitWidth:  Tokens.fieldHeight - Tokens.spacingSm
            implicitHeight: implicitWidth
            onActivated: {
                if (root.busy) root.stopRequested()
                else if (input.text.length > 0) { root.clear(); root.focusInput() }
                else root.helpToggled()
            }
        }
    }
}
