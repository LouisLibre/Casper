# Casper

![Casper app icon](app/casper/Assets.xcassets/AppIcon.appiconset/icon_128x128.png)

**Your notch has a terminal now.** Casper is a terminal that opens from your notch, built with [libghostty](https://github.com/Lakr233/libghostty-spm).



Click the notch icon or press **Control + Left Option** (⌃⌥) to open your terminal. Stop searching across all windows & spaces. 

Same place, every time.

## Casper Usage

- **Open Casper from anywhere.** Bring the terminal into focus with a notch click or ⌃⌥
- **Return to any other app.** Click or ⌘TAB into your other apps and it tucks back in.
- **Give each job a tab.** Keep an agent, a dev server, and a shell in separate tabs.
- **Tuck it away mid-task.** Collapse the panel while a command runs. Your shells, processes, and scrollback stay alive.
- **Keep output in sight.** Pin the panel to disable collapsing while you work in another app. 

## Casper Demo



https://github.com/user-attachments/assets/50c2aa14-1edf-40d7-bb9b-309dc53523cb




## Build from source

**Requirements:** macOS 15.6 or later and Xcode 26.

1. Clone this repository and open `app/casper.xcodeproj` in Xcode.
2. Wait until Xcode resolves the Swift packages, including `libghostty-spm` **1.5.1**.
3. On the Xcode sidebar click the casper project > Select "casper" in targets › Go to "Signing & Capabilities" tab and either set Team to your own or set Signing Certificate to "Sign to Run Locally"
4. Click **Product → Run** (⌘R). Casper starts collapsed; click the purple ghost or press ⌃⌥ **Control + Left Option** together to open it.

To keep the app, move `casper.app` out of `build/` and into /Applications.

## Common Shortcuts

The terminal expands with ⌃⌥, or a click in the notch icon, or ⌘Tab into Casper.

The terminal collapses with ⌃⌥, or a click outside it, or ⌘Tab into other apps. 

Pin (⌘P) turns off collapsing for clicking outside it, or for ⌘Tab into other apps, so the panel stays open over the other apps.

Tabs sit in a row under the panel. ⌘T adds one, ⌘1–⌘9 jumps between the 1st to 9th tab, and you can drag them into a new order. Put an agent in one, a dev server in another and a shell in a third; all of them keep running while the panel is collapsed.

### All Shortcuts Table

| Shortcut | Action |
| --- | --- |
| ⌃ + left ⌥ | Toggle to expand or collapse the panel |
| ⌘T | Open a terminal tab |
| ⌘1–⌘9 / ⌘0 | Select tabs 1–9 / the tenth tab |
| ⌘[ | Previous tab |
| ⌘] | Next tab |
| ⌘W | Close the active tab; the last tab asks to quit |
| ⌘M | Default macOS minimize shortcut, it collapses the panel |
| ⌘P | Pin or unpin the panel |
| ⌘⇧+ / ⌘⇧− | Grow / shrink the panel |
| ⌘+ / ⌘− | Increase / decrease font size |
| ⌘S | Open Casper settings |
| ⌘, | Open ghostty configuration file |
| ⌘⇧, | Reload ghostty configuration file |
| ⌘Q | Quit after confirmation |
| Hold ⌘ for a second | Display all shortcut hints in the app |

## Casper Configuration

Settings (⌘S) has three toggles:

| Setting | Effect |
| --- | --- |
| Open at login | Registers Casper to run at startup. macOS may ask for approval in System Settings › Login Items. |
| Show in Dock | On by default. Gives Casper a Dock icon and a ⌘Tab entry. Turning it off removes dock icon and the ⌘Tab entry |
| Transparent background | ON gives a frosted backdrop. OFF uses the ghostty theme's solid background color. |

For fonts, colors, themes, and terminal key bindings, press **⌘,** or choose **Open in Editor** in Settings. This creates `~/.config/casper/config.ghostty` from the bundled defaults on first use. Edit it using [Ghostty's configuration syntax](https://ghostty.org/docs/config/reference). Choose a [bundled theme](app/Vendor/ghostty-themes/themes) by name; the default is **Dark Pastel**.

Save, return to the terminal, and press **⌘⇧,** to reload. Fonts and colors can update in existing terminals; padding and some other settings need a new tab.

## FAQ

**Does it work without a notch?**

Yes. Casper draws a small strip at the top center. It uses one display at a time, preferring a notched display and otherwise using macOS's main screen.

**What happens when I collapse it or quit?**

Collapsing keeps the terminals running. Quitting ends the terminal sessions. On quitting and then restoring the app, Casper will remember only the number of tabs, their order and their directories. Previously running programs and scrollback are not restored after quitting.

**Why doesn't ⌃⌥ open the panel?**

Maybe its overlapping with some other app shortcut. You can still click the notch purple ghost icon to open Casper.

## Contributing

[Issues](https://github.com/LouisLibre/Casper/issues) are open; include your macOS version, display setup and steps to reproduce.

## Credits

Casper uses [Ghostty](https://ghostty.org/) through [Lakr233's libghostty-spm](https://github.com/Lakr233/libghostty-spm), pinned at 1.5.1. Its bundled themes come from [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes), via Ghostty's theme distribution. The bash and zsh integration is libghostty-spm's MIT scripts plus Casper's [patches](app/Vendor/ghostty-shell-integration/README.md).
