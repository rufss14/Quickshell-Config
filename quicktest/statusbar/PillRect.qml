import QtQuick
import "../theming" as T

// ── PillRect ──────────────────────────────────────────────────────────────────
// Shared background rectangle for all bar pills.
// Extracted to its own file to avoid Qt inline-component property warnings.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    color:        T.Theme.bg
    opacity:      0.90
    border.color: T.Theme.barBorder
    border.width: 1
    // clip: true  — removed: causes anchored children to be cut off during y-slide transitions
}
