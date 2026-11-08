import QtQuick
import Quickshell
import "../config"
import "../services"

// ── InputField ────────────────────────────────────────────────────────────────
// A single-line text field in the panel's surface language.
//
// ── Why this exists ───────────────────────────────────────────────────────────
// There were six copies of it — DiscordPage's `CredField`, WidgetsPage's `OptField`,
// and one-off TextInputs in LockPage, LanguagePage, HyprlandPage, KeyboardPage and
// BarPage. CredField's own comment says it was "modelled on WidgetsPage's OptField",
// which is the copy being made in writing. They had already drifted: only one of them
// showed an invalid state, only one masked its text, and the placeholder in half of
// them didn't elide, so a long hint ran out past the rounded corner.
//
// This is their union, and the differences that were real are properties.
//
// ── Reporting: committed vs edited ────────────────────────────────────────────
// The two copies disagreed about WHEN to tell the caller, and both were right for
// their own case:
//
//   • `committed` fires on Enter and on losing focus. The default, and what you want
//     when acting on the value is expensive — rescanning a directory, writing a file.
//     Both, never just Enter: a field you finish by clicking elsewhere is the common
//     case, and Enter-only silently drops that edit.
//   • `edited` fires per keystroke, for a caller that has to track "is there anything
//     unsaved" live. A Save button gated on commit-only stays dead until you happen
//     to click away, which reads as the button being broken.
//
// Both always fire; a caller connects to whichever it needs.
//
// ── Seeding ───────────────────────────────────────────────────────────────────
// `seed` is the value from outside. It is applied only while UNFOCUSED, so a save
// that round-trips through a service and comes back can't yank the text out from
// under someone who is still typing in it.
//
// `setText()` is the imperative escape hatch beside it, for a FORM being opened or
// reset — "put this in the box now". Two reasons it can't be `seed`: seed fires on
// CHANGE, so re-opening a form on the same value sets nothing, and seed politely
// refuses while focused, which is wrong when the caller is the one driving.
//
// ── The three copies this was supposed to replace, and didn't ─────────────────
// This file's header used to say it replaced DiscordPage's CredField and
// WidgetsPage's OptField. It didn't — it was added ALONGSIDE them, so for a while
// there were seven implementations where there had been six, and the copies drifted
// exactly as predicted: OptField's placeholder never elided and its box was 4px
// shorter, HyprlandPage's Field had no focus outline, no invalid state, a different
// selection colour and a different type size. All three are gone now; `mono` and
// `accepted` below are what they genuinely had and this didn't.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    property string placeholder: ""
    // Room reserved before the text, for something the caller draws inside the field (the overview's operator chips).
    property real leadingSpace: 0
    property string seed:        ""

    // Optional: the empty field TYPES hints after `hintLead` — [{ key, text }] — instead
    // of showing `placeholder`, the way the launcher's does (components/TypedPlaceholder).
    // For a field with something to teach (a search that takes a few kinds of word).
    property string hintLead: ""
    property var    hints:    []

    // Masks the text. No reveal button, deliberately — the same call CredField made:
    // a shell-wide "show password" affordance is a bigger promise than one field.
    property bool secret: false

    // Draws the danger outline. The caller owns validation; this only shows it.
    property bool invalid: false

    // Monospace, for a field holding something whose ALIGNMENT carries meaning — a
    // keybind combo, a Lua dispatch. From HyprlandPage's Field, which is where the
    // only callers are.
    property bool mono: false
    // Room kept clear at the right end for something the caller lays over the field (a send button
    // inside the pill — the overview's AI composer).
    property int trailingSpace: 0

    readonly property alias text: input.text
    readonly property alias editing: input.activeFocus

    signal committed(string value)
    signal edited(string value)

    // Every key, BEFORE the field acts on it. A caller that accepts the event keeps
    // it from the field — the overview's search takes ←/→/Tab/digits this way while
    // the field holds focus for typing.
    signal keyPressed(var event)

    // A Material Symbols name drawn in front of the text ("search"); "" for none.
    property string icon: ""

    // ── accepted: Enter, and ONLY Enter ───────────────────────────────────────
    // The third case, and the one `committed` must not be used for. `committed` also
    // fires on blur, which is right when the field EDITS something that already
    // exists — clicking away should keep your edit, not drop it.
    //
    // It is wrong when the field's action CREATES something. HyprlandPage's "add a
    // keybind" form is the live example: on `committed` it would add a keybind every
    // time you clicked out of a half-filled box. A create needs a deliberate act, and
    // Enter is it.
    signal accepted(string value)

    function clear() { input.text = "" }
    function forceFocus() { input.forceActiveFocus() }
    // Lets go of focus (fires `committed`, as any blur does). `focus = false` on the field itself would
    // not do it: the TextInput inside is what holds focus, and this Surface is not a focus scope.
    function blur() { input.focus = false }

    // See the `seed` note in the header for why this exists next to it.
    function setText(v) { input.text = v }

    implicitHeight: Tokens.fieldHeight
    elevation: Tokens.elevationNested
    cornerRadius: Tokens.radiusSm
    focused: input.activeFocus
    border.color: root.invalid      ? Colors.of(QsWindow.window).danger
                : input.activeFocus ? Colors.of(QsWindow.window).outlineFocus
                                    : Colors.of(QsWindow.window).outlineFor(root.elevation)

    onSeedChanged: if (!input.activeFocus) input.text = root.seed
    Component.onCompleted: input.text = root.seed

    MaterialIcon {
        id: lead
        visible: root.icon !== ""
        anchors.left: parent.left
        anchors.leftMargin: Tokens.spacingMd
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        font.pixelSize: Tokens.iconSm
        color: input.activeFocus ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgMuted
    }

    // Draws itself round the field on focus (see FocusTrace); the border above already says
    // "focused" at once. Not while invalid: that outline is the danger colour and stays plain.
    // Off for a field that sits among loud neighbours (the overview's search): the border alone says "focused".
    property bool trace: true
    FocusTrace {
        active: root.trace && input.activeFocus && !root.invalid
        radius: root.radius
    }

    TextInput {
        id: input
        Accessible.role: Accessible.EditableText
        Accessible.name: root.placeholder
        anchors.fill: parent
        anchors.leftMargin:  (root.icon !== "" ? Tokens.spacingMd * 2 + Tokens.iconSm : Tokens.spacingMd) + root.leadingSpace
        anchors.rightMargin: Tokens.spacingMd + root.trailingSpace
        verticalAlignment: TextInput.AlignVCenter
        font.family: root.mono ? Tokens.fontMono : Tokens.fontFamily
        font.pixelSize: Tokens.fontLabel
        color: Colors.of(QsWindow.window).fg
        selectionColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.35)
        selectByMouse: true
        clip: true

        echoMode: root.secret ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"

        // Offered to the caller first (keyPressed); otherwise observed, not accepted:
        // the event goes on to the field.
        Keys.onPressed: event => {
            root.keyPressed(event)
            if (!event.accepted) Sfx.typed(event.key, event.text, event.modifiers)
        }

        onTextChanged: root.edited(input.text)
        onAccepted: { root.accepted(input.text); root.committed(input.text) }
        onActiveFocusChanged: if (!input.activeFocus) root.committed(input.text)

        StyledText {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text === "" && root.hints.length === 0
            text: root.placeholder
            variant: "caption"
            emphasis: "dim"
            // Elides, which only one of the six copies did. A placeholder is a hint
            // and hints are long; the ones that didn't elide ran past the corner.
            elide: Text.ElideRight
        }

        TypedPlaceholder {
            anchors.fill: parent
            visible: input.text === "" && root.hints.length > 0
            lead: root.hintLead !== "" ? root.hintLead : root.placeholder
            hints: root.hints
            separator: " · "
            variant: "caption"
        }
    }
}
