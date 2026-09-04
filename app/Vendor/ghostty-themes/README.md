# Ghostty themes

The `themes` folder is the theme set Ghostty 1.3.1 ships in
`Ghostty.app/Contents/Resources/ghostty/themes`, taken unmodified from the
tarball its build pins in `build.zig.zon`:

    https://deps.files.ghostty.org/ghostty-themes-release-20260216-151611-fc73ce3.tgz

The files are generated from mbadolato/iTerm2-Color-Schemes (MIT, see LICENSE).

libghostty resolves `theme = <name>` by looking for `<name>` in
`~/.config/ghostty/themes` and then in `<resources dir>/themes`. The
libghostty-spm package ships shell integration and terminfo but no themes, so
the app copies this folder into its bundle and points libghostty at a
resources directory that combines the two (see `GhosttyRuntime.pinResourcesDirectory`).

To update: change the URL to the one pinned by the Ghostty release the package
tracks, re-extract, and replace `themes`.
