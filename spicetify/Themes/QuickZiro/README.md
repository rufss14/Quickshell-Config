# QuickZiro

Spotify's theme in the shell. It is [Ziro](https://github.com/schnensch0/ziro) by schnensch
(MIT, `LICENSE`), with the shell's colours fed in: `scripts/themes/spotify/pwspice.py --style ziro`
writes the `[Pywal]` scheme of `color.ini` from the shell's palette, and Spicetify's `Pywal`
colour scheme reads it. `user.css` is Ziro's with local changes.

`scripts/theme-setup.sh` copies `user.css` into Spicetify's `Themes/QuickZiro` and keeps an
existing `color.ini`, since that holds the palette.
