import QtQuick
import Quickshell
import "../config"

// ── TabStrip ──────────────────────────────────────────────────────────────────
// A panel's or settings page's page switch. It is SegmentSwitch now (2026-10-25): the
// shell had two segmented controls with two looks, and one control is the consistent
// answer. The name stays so a call site reads as what it is for. Use it for PAGES of a
// panel, whole views swapped in place. A value picked from a handful of options is a
// ChipRow; an action is a PanelButton.
// ─────────────────────────────────────────────────────────────────────────────
SegmentSwitch {
    id: root
}
