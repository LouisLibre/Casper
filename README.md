![Casper's purple ghost app icon](app/casper/Assets.xcassets/AppIcon.appiconset/icon_128x128.png)

# Casper

**Your notch has a terminal now.**

A native macOS terminal that opens from your notch, built with [libghostty](https://github.com/Lakr233/libghostty-spm).

Click the purple ghost or press **Control + left Option** (⌃⌥) to reach your shell without rearranging your workspace. Same place every time.

<!-- Product demo placeholder: show the notch opening over an existing workspace, switching terminal tabs, and collapsing while a process keeps running. Add the finished media here. -->

## One Terminal. Zero Context-switching.

- **Get to work from any app.** Bring the terminal into view with a click or ⌃⌥, then start typing.
- **Return to work on any app.** Click or CMD+TAB into your other apps and it tucks back in.
- **Give each job a tab.** Keep an agent, a dev server, and a shell in separate tabs. Switch by number or drag tabs into the order you want.
- **Tuck it away mid-task.** Collapse the panel while a command runs. Your shells, processes, and scrollback stay alive while Casper stays open.
- **Keep output in sight.** Pin the panel while you work in another app. Drag the bottom edge or a bottom corner to resize it.

## Build from source

There are no [published releases](https://github.com/LouisLibre/Casper/releases) yet. Build from source with Xcode.

**Requirements:** macOS 15.6 or later and Xcode 26.

1. Clone this repository and open `app/casper.xcodeproj` in Xcode.
2. Let Xcode resolve the Swift packages, including `libghostty-spm` **1.5.1**.
3. On the Xcode sidebar click the casper project > Select "casper" in targets › Go to "Signing & Capabilities" tab and either set Team to your own or set Signing Certificate to "Sign to Run Locally"
4. Choose **Product → Run** (⌘R). Casper starts collapsed; click the purple ghost or press ⌃⌥ **Control + Left Option** together to open it.

To keep the app, move `casper.app` out of `build/` and into /Applications.

## Usage

The panel collapses on ⌃⌥, a click outside it, or ⌘Tab to another app. Hovering never opens it, and moving the pointer away never collapses it. Collapsing doesn't resize the terminal, so TUIs work perfectly.

Pin (⌘P) turns off collapsing for clicking or tabbing away, so the panel stays open over other apps while you work in them.

Tabs sit in a row under the panel. ⌘T adds one, ⌘1–⌘0 jump to the first ten, and you can drag them into a new order. Put an agent in one, a dev server in another and a shell in a third; all of them keep running while the panel is collapsed. Right-click a tab to reveal its directory in Finder.

Drop a file from Finder on the terminal and it arrives as a shell-escaped path. It supports displaying images on Agents.

## All Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌃ + left ⌥ | Expand or collapse the panel |
| ⌘T | Open a terminal tab |
| ⌘1–⌘9 / ⌘0 | Select tabs 1–9 / the tenth tab |
| ⌘[ / ⌘] | Previous / next tab |
| ⌘W | Close the active tab; the last tab asks to quit |
| ⌘M | Collapse the panel |
| ⌘P | Pin or unpin the panel |
| ⌘⇧+ / ⌘⇧− | Grow / shrink the panel |
| ⌘+ / ⌘− | Increase / decrease font size |
| ⌘S | Open Casper settings |
| ⌘, | Open ghostty configuration file |
| ⌘⇧, | Reload ghostty configuration file |
| ⌘Q | Quit after confirmation |
| Hold ⌘ for about a second | Show each control's shortcut as a badge, while the panel has focus | fixed |

## Casper Configuration

ettings (⌘S) has three toggles:

| Setting | Effect |
| --- | --- |
| Open at login | Registers Casper to run at startup. macOS may ask for approval in System Settings › Login Items. |
| Show in Dock | On by default. Gives Casper a Dock icon and a ⌘Tab entry. Turning it off removes dock icon and ⌘Tab entry |
| Transparent background | ON gives a frosted backdrop. OFF uses the ghostty theme's solid background color. |

For fonts, colors, themes, and terminal key bindings, press **⌘,** or choose **Open in Editor** in Settings. This creates `~/.config/casper/config.ghostty` from the bundled defaults on first use. Edit it using [Ghostty's configuration syntax](https://ghostty.org/docs/config/reference). Choose a [bundled theme](app/Vendor/ghostty-themes/themes) by name; the default is **Dark Pastel**.

Save, return to the terminal, and press **⌘⇧,** to reload. Fonts and colors can update in existing terminals; padding and some other settings need a new tab.

## FAQ

**Does it work without a notch?**

Yes. Casper draws a small strip at the top center. It uses one display at a time, preferring a notched display and otherwise using macOS's main screen.

**What happens when I collapse it or quit?**

Collapsing keeps the terminals running. Quitting ends the terminal sessions. On restart, Casper opens fresh shells in the saved tab order and directories, as last reported by shell integration. Running programs and scrollback are not restored after quitting.

**Why doesn't ⌃⌥ open the panel?**

Maybe its overlapping with some other app shortcut. You can still click the purple ghost to open Casper.

## Contributing

[Issues](https://github.com/LouisLibre/Casper/issues) are open; include your macOS version, display setup and steps to reproduce.

## Credits

Casper uses [Ghostty](https://ghostty.org/) through [Lakr233's libghostty-spm](https://github.com/Lakr233/libghostty-spm), pinned at 1.5.1. Its bundled themes come from [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes), via Ghostty's theme distribution. The bash and zsh integration is libghostty-spm's MIT scripts plus Casper's [patches](app/Vendor/ghostty-shell-integration/README.md).
