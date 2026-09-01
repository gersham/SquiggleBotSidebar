# SquiggleBotSidebar

A total-conversion vertical sidebar for [Omarchy](https://omarchy.org/)'s
Quickshell desktop shell, headed by **squigglebot** — a Grok-bot-style AI
mascot wired to your omarchy default coding agent.

The mascot code that used to live in the standalone `gersham.squigglebot`
bar-widget plugin is bundled here (that plugin is deprecated): rendering,
reactions, speech bubbles, the keyboard/voice input bubble, the chat window,
and the agent bridge all ship in this repo and run inside the omarchy shell
process. No separate Quickshell instance.

squigglebot's engine is a native QML port of
**[open-mascot](https://github.com/0oooh/open-mascot-studio)** by
[0oooh](https://github.com/0oooh) — the mascot engine, its expressions,
animations, and character design all come from that project. The engine's
pure-JS core runs unmodified inside Qt's JS engine; the browser SVG renderer
is replaced with QtQuick Shapes.

## Install

```bash
./install.sh                 # plugin + CLI symlinks, seed config
omarchy restart shell
squigglebot tell "hello"
```

The sidebar only takes over when the configured bar position is vertical
(`left` or `right`); on a horizontal bar it hosts the built-in `omarchy.bar`
untouched, so enabling it can never leave you without a bar.

## Layout

The header carries the Omarchy mark (left click: root menu, right click:
terminal) with the mascot beneath it. He idles in your theme's accent color,
blinks, fidgets, dozes off when ignored. The bar's `left`/`center`/`right`
widget sections from shell.json keep rendering, translated onto the vertical
axis (top / middle / bottom), and a clock sits at the foot.

## Talking to him

- **Summon hotkey** (e.g. the NuPhy AI key — `squigglebot-voice
  press`/`release` bound in `~/.config/hypr/bindings.lua`): **tap** opens a
  keyboard input bubble beside him on keyup — type, **Return** sends,
  **Shift+Return** newline, **Ctrl+Return** sends and opens the chat window,
  **Esc** cancels; tapping again dismisses. **Hold** to talk: recording
  starts on keydown, the bar mascot becomes a live waveform of your mic,
  and releasing transcribes with voxtype and sends the text as if typed.
- **Click him**: same input bubble. **Double-click**: the chat window.
- **CLI**: `squigglebot tell "..."` — plus `say`, `hush`, `ask`, `summon`,
  `chat`, `channel`, `heard`, `emotion`, `play`, `poke`, `sleep`, `wake`,
  `amnesia`, `status`. All over the shell's IPC
  (`omarchy-shell squigglebot ...`), so hooks/scripts/agents can drive him.
- **The chat window** (`squigglebot chat`, double-click, the ⧉ button on his
  bubble, or Ctrl+Return): a conventional LLM chat with the full history,
  clickable document links, and the channel picker. It remembers its size
  and position. While it's open, replies land there instead of bubbles.

What you send goes to the omarchy default agent (`omarchy default agent`;
codex, claude, opencode, crush, pi run headlessly) via `bin/squigglebot-agent`
with an editable persona prompt (`~/.config/squigglebot/agent-prompt.md`).
It answers as squiggle in strict JSON — reply text (with **bold**/*italic*/
__underline__ markdown), an after-animation or held emotion, bubble seconds —
and he performs it, visibly mulling (thinking/curious/listening rotation)
while the agent works. Messages queue and run serially; queued replies show
one after another.

He can **do things**: `agentMode` in `~/.config/squigglebot/config.json`
sets trust — `read`, `write` (default: sandboxed edits/commands from $HOME),
or `full` (no sandbox). **Long answers** arrive as self-contained HTML docs
(`~/.cache/squigglebot/docs/`, pruned weekly), referenced by an underlined
clickable title.

## Channels & memory

Conversations are scoped by channel (`#general`, `#system`, ...): switch via
the chevron panel in the chat window, a leading `#channel ` in any input
(the token is eaten as you type), `/join`, or `squigglebot channel <name>`.
Each channel keeps Hermes-style memory under
`~/.local/state/squigglebot/channels/<name>/`: `MEMORY.md` (durable facts
the agent curates itself), `history.log` (full transcript, never truncated —
he greps it for older specifics), and a rolling `summary.txt` for prompt
compactness. Delete via a chip's hover-×, `/drop`, or `squigglebot channel
rm <name>`; `squigglebot amnesia [name|all]` wipes memory.

**Slash commands** (either input, handled locally): `/help /channels /join
/drop /amnesia /model /thinking /mode /agent /emotion /play /sleep /wake
/doc /status /hush`. `/model`, `/thinking`, `/agent`, `/mode` persist to the
config and steer the agent CLI.

## Personality

Fidgets every 15–40s while idling (glances, head tilts, peeks, yawns, hops);
dozes off through a nodding sequence after `sleepAfter` seconds (widget
setting, default 60) and wakes with a stretch; hover makes him curious;
omarchy hooks (`hooks/`, installed via `omarchy hook install`) have him
announce theme switches and fret about low battery.

## Configuration

- **Sidebar geometry**: explicit constants at the top of `Bar.qml`
  (`sidebarWidth`, `mascotWidth`, paddings, clock sizes).
- **Mascot settings** (injected by the header in `Bar.qml`; the same keys a
  shell.json bar-widget entry would carry): `shape`, `bodyColor`/`eyeColor`
  (hex or theme key — follows theme switches), `scale`, `mouth`,
  `interactive`, `sleepAfter`, `fidgets`, `idleFps`, `busyFps`,
  `pokeAnimation`, `bubbleColor`, `bubbleTextColor`, `eyes`.
- **Agent tuning**: `~/.config/squigglebot/config.json` (`agentMode`,
  `agentModel`, `agentThinking`, `agentCli`) — or the slash commands.
- **Persona**: `~/.config/squigglebot/agent-prompt.md`.

## Development

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Bar.qml Widget.qml
omarchy restart shell        # QML only reloads on restart
```

## Credits & license

The mascot engine, character design, expressions, and animations are from
[open-mascot / Open Mascot Studio](https://github.com/0oooh/open-mascot-studio)
by [0oooh](https://github.com/0oooh), MIT licensed. SquiggleBotSidebar (the
sidebar, widget, conversation layer, agent bridge, and CLI) is released under
the same [MIT license](LICENSE).
