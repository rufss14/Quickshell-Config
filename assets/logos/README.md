# Third-party logos

Not mine, not the shell's. Kept apart from `assets/icons/` (which is this project's own
artwork) so the provenance line stays visible.

| file          | source                                                        | notes |
|---------------|---------------------------------------------------------------|-------|
| hyprland.svg  | `hyprwm/Hyprland` → `assets/header.svg` (BSD-3-Clause repo)    | Upstream ships a **banner**: droplet + "Hyprland" wordmark, 1006×347. This is that file with the wordmark `<g>` removed and the viewBox cropped square around the droplet (`path.st7`). Gradients and paths are untouched — the mark is upstream's, only the framing is ours. |
| wayland.png   | `https://wayland.freedesktop.org/wayland.png`                  | The official mark. PNG because there is no public SVG: the source lives in freedesktop's `wayland-web` GitLab, which requires sign-in to fetch. 117×150 — fine at the 96px it's drawn at, soft if ever drawn much larger. |
| quickshell.svg | `quickshell` package → `/usr/share/icons/hicolor/scalable/apps/org.quickshell.svg` | Verbatim copy of the icon Quickshell installs for itself (upstream, LGPL-3.0 repo). Vendored rather than resolved from the icon theme because a from-source build may not install the hicolor icon, and the welcome panel's header would then read as broken. Drawn by `modules/onboard/WelcomePanel.qml` and the About page's Shell card; full colour, same exception as `hyprland.svg` below. |
| quickshell-mono.svg | derived from `quickshell.svg` | The mark's white gear path alone (the green plate dropped), so `TintedIcon` can stencil it in the palette's accent — the full-colour file would stencil to a solid square. Path data untouched. Used by the shell-update button and card. |
| Claude.webp   | supplied by the user (Claude's animated burst) | Animated WebP, 80×80, 192 frames on an orange plate. Qt here has no WebP plugin and the plate can't sit on the shell's surfaces, so `scripts/claude-burst.py` keys the plate out and writes `claude-burst.png`, a white-on-transparent sprite sheet that `components/ClaudeBurst` plays and tints. Regenerate with that script (`--check` verifies the sheet and the component's constants agree). |
| claude-presence.gif | derived from `claude-burst.png` | The same burst, orange (`ClaudeGlyph.claudeOrange`) on black, 256×256, 40 ms steps. Discord animates a rich-presence image only when it comes from an external URL, so this is the file the Claude presence points at via `raw.githubusercontent.com`. Regenerate with `scripts/claude-presence-gif.py` (`--check` verifies it). |

`hyprland.svg`, `wayland.png` and `quickshell.svg` are project trademarks, used here to
identify those projects (an About page, the welcome panel). Fine for a personal config;
check with the projects before redistributing.

Rejected: `/usr/share/icons/Papirus/*/apps/wayland.svg` is installed and scalable, but
it's Papirus's restyled take on the mark, not the mark.
