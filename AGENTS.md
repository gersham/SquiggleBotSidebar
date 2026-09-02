# AGENTS.md

## Project intent

SquiggleBotSidebar is a distributable Omarchy Quickshell full-bar plugin
(`gersham.squigglebotsidebar`), developed as a user-space plugin: no edits to
`/usr/share/omarchy/`, no second Quickshell process. The squigglebot mascot —
formerly the standalone `gersham.squigglebot` bar-widget plugin from
`~/Sources/personal/squigglebot` — is **bundled in this repo** as of the
merge; that repo and plugin are deprecated. Do not resurrect the old
standalone desktop Quickshell instance either (`quickshell/shell.qml`, the
`~/.config/quickshell/squigglebot` config).

## Layout

- `Bar.qml` — the full-bar entry point. Takes over only when the bar
  position is vertical; otherwise instantiates the built-in `omarchy.bar`
  as a passthrough. Header (Omarchy mark + mascot), the three shell.json
  widget sections mapped onto the vertical axis (middle centred in the run
  between top and bottom), clock. Widgets drag between slots like the
  built-in bar: a per-cell left-button overlay (`WidgetCell` dragArea) lifts
  past a 10px threshold, `SidebarPanel.dropAt` resolves region + insertion
  (regions split at the midpoints of the empty runs, so empty slots accept
  drops), `DragGhostPanel` draws the snapshot + accent marker, and
  `dropWidget` writes through `shell.mutateShellConfig` (top/middle/bottom →
  left/center/right). Non-drag left presses are forwarded to the widget's
  registered click target (WidgetButton) like the built-in bar does.
- `Widget.qml` — the squigglebot bar widget, loaded directly by Bar.qml's
  header (no registry lookup): mascot rendering, reactions, say bubble
  (PopupWindow + SpeechBubble beside the bar), sleep/fidgets, voice
  waveform, and the `squigglebot` IPC target in the omarchy shell instance.
- `quickshell/ChatHost.qml` — the conversational stack, instantiated by the
  widget's primary instance only: agent send/reply queues, channels, slash
  commands, the keyboard input bubble (layer-shell, exclusive keyboard), and
  the breakout chat window (FloatingWindow, geometry remembered in
  `~/.local/state/squigglebot/chatwin.json`) — now the fallback: `openChat()`
  runs `squigglebot-chat` unless `chatMode` is "window" or the launcher exits 3.
- `quickshell/Mascot.qml`, `quickshell/SpeechBubble.qml`,
  `quickshell/engine/*.mjs` — shared renderer + engine. Engine files under
  `engine/` are ported from open-mascot (MIT): keep upstream-derived files
  close to upstream (Qt-V4 compat only — no object spread,
  `Object.fromEntries`, `flatMap`, `Object.hasOwn`, no use-before-declaration
  of module consts); squigglebot's own extensions (mouth.mjs, preset.mjs,
  controller.mjs) are fair game.
- `bin/squigglebot` — CLI; a thin wrapper over `omarchy-shell squigglebot
  <fn> [args]`.
- `bin/squigglebot-agent` — headless run of the omarchy default agent with
  per-channel Hermes-style memory (`channels/<name>/{MEMORY.md,history.log,
  summary.txt}` under `~/.local/state/squigglebot/`). With codex/claude each
  channel is one persistent agent session (`channels/<name>/session.<agent>`):
  first message = `codex exec` / `claude -p --session-id` with the full
  prompt, later ones = `codex exec resume` / `claude -p --resume` with just
  the `[squiggle-bridge]`-marked message; a resume that yields nothing drops
  the id and reopens. `--interactive-argv` prints the argv that resumes the
  thread in the agent's TUI (exit 3 = no session support). Agents block
  reading an open stdin pipe under quickshell — keep `</dev/null` on every
  invocation. `SQUIGGLE_AGENT=claude` overrides the agent for testing.
- `bin/squigglebot-chat [channel]` — the breakout: focuses the channel's
  terminal if open, else bootstraps the thread (one greeting run) and opens
  `xdg-terminal-exec --app-id=org.omarchy.squigglebot-chat.<channel>` via
  uwsm-app with the resume argv. Floating/centered/45%x70% comes from an
  `o.window(...)` rule injected with `hyprctl eval`, guarded by a Lua global
  so it is added once per Hyprland config lifetime — nothing is written to
  the user's Hyprland config. This Hyprland only accepts Lua dispatchers
  (`hl.dsp.focus({ window = "address:..." })`); legacy `focuswindow`,
  `closewindow`, `resizewindowpixel` are rejected with exit 7.
- `bin/squigglebot-voice` — the summon-key entry (press/release), recording,
  live mic levels, voxtype transcription. Resolved relative to Widget.qml
  for click-to-cancel; symlinked into `~/.local/bin` by install.sh for the
  Hyprland binding.
- `open-mascot-studio/` — gitignored: an independent checkout of the
  upstream engine project, not part of this repo.

## The header ↔ widget contract

Bar.qml hosts Widget.qml in its header with `interactive: true` — the
widget's own MouseArea handles hover/click/double-click; the sidebar draws
its Omarchy mark above him for the menu actions. The header injects
`bar`, `moduleName` (kept as `"gersham.squigglebot"` — also still listed in
`supersededWidgets` so a stale shell.json entry never double-renders in the
grid), and `settings` (`interactive`, `scale`), and reads `implicitHeight`
following from an assigned width. The widget's public API used by hosts:
`poke()/express(name)/play(name)/rest()/say(...)/hush()/cancelInProgress()`.

`cancelInProgress()` is the click-to-cancel path: it aborts a voice
recording/transcription (via `bin/squigglebot-voice cancel`, resolved
relative to Widget.qml) or closes an open input bubble, returning true when
it consumed the click so the host can fall through to its own click action
otherwise.

## Working rules

- Keep the plugin self-contained and removable; preserve a safe recovery
  path to `omarchy.bar` (the horizontal-position passthrough is that path).
- Prefer Omarchy's existing `qs.Ui` and `qs.Commons` primitives.
- Keep geometry, colors, and interaction constants explicit and easy to tune.
- Do not silently change the user's unrelated `shell.json`, `shell.toml`,
  Hyprland configuration, or other plugins.
- One ChatHost per shell process: it's gated on the primary screen's widget
  instance. Visual reactions relay across instances; conversation state does
  not.
- The widget reads the shell's reactive `Color` singleton for theme colors —
  no colors.toml parsing, no file watching for themes.
- In-process rendering costs real CPU in the shell: keep the sample throttle
  (idle 6fps / busy 30fps) and check shell CPU after adding animation paths.
- User-facing config: mascot settings injected in Bar.qml's header;
  `~/.config/squigglebot/config.json` (agent tuning: agentMode/agentModel/
  agentThinking/agentCli — also settable via /slash commands);
  `~/.config/squigglebot/agent-prompt.md` (persona).

## Verification

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Bar.qml Widget.qml quickshell/ChatHost.qml quickshell/SpeechBubble.qml
omarchy restart shell        # QML only reloads on restart
squigglebot ping && squigglebot tell "/status"
```

Widget QML errors are swallowed by the daemonized shell — check
`journalctl --user` or run the shell in the foreground. Test through the
CLI/IPC (`squigglebot tell`, `summon`, `chat`) and with `wtype` for keyboard
paths; `hyprctl layers -j` / `clients -j` give window geometry ground truth.
The main monitor is 5120x2160 at Hyprland scale 1.6 — grim screenshots are
physical pixels (logical × 1.6).

Also test discovery, enable/disable, shell restart, removal, multiple
monitors, both vertical bar positions plus the horizontal passthrough,
keyboard focus, and recovery to the built-in bar. Do not claim live behavior
from static validation alone.

## Current compatibility note

The local Omarchy 4.0 shell has had a known full-bar plugin loader issue where
injected properties can arrive after QML construction. Keep entry-point
properties compatible with the actual installed runtime (nothing `required`,
nothing dereferenced at construction) and verify the full bar on the target
shell before publishing.
