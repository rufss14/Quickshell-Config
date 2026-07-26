# Third-party logos

Not mine, not the shell's. Kept apart from `assets/icons/` (which is this project's own
artwork) so the provenance line stays visible.

| file          | source                                                        | notes |
|---------------|---------------------------------------------------------------|-------|
| hyprland.svg  | `hyprwm/Hyprland` → `assets/header.svg` (BSD-3-Clause repo)    | Upstream ships a **banner**: droplet + "Hyprland" wordmark, 1006×347. This is that file with the wordmark `<g>` removed and the viewBox cropped square around the droplet (`path.st7`). Gradients and paths are untouched — the mark is upstream's, only the framing is ours. |
| wayland.png   | `https://wayland.freedesktop.org/wayland.png`                  | The official mark. PNG because there is no public SVG: the source lives in freedesktop's `wayland-web` GitLab, which requires sign-in to fetch. 117×150 — fine at the 96px it's drawn at, soft if ever drawn much larger. |

Both are project trademarks, used here to identify those projects on an About page.
Fine for a personal config; check with the projects before redistributing.

Rejected: `/usr/share/icons/Papirus/*/apps/wayland.svg` is installed and scalable, but
it's Papirus's restyled take on the mark, not the mark.
