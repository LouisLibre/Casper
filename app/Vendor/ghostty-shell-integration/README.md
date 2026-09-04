# Shell integration

Copy of the bash and zsh shell integration scripts from libghostty-spm
1.5.1 (MIT, see LICENSE), with one change: the prompt-start mark is
`OSC 133;A;cl=line` instead of `OSC 133;A`.

The `cl=line` option tells libghostty that clicking inside the prompt's
input line may move the cursor, which it does by sending arrow keys.
Without it libghostty ignores prompt clicks entirely, so the package's
unmodified scripts never get click-to-move. Ghostty's own scripts send the
same option.

At launch the app links `shell-integration` in its assembled resources
directory to this folder instead of the package bundle (see
`GhosttyRuntime.pinResourcesDirectory`). Terminfo still comes from the
package.

To update: copy `Sources/GhosttyTerminal/Resources/Ghostty/shell-integration`
from the new package version over `shell-integration`, re-apply the
`cl=line` change to every `133;A` mark, and update the version above.
