#!/usr/bin/env bash
# Install SquiggleBotSidebar the omarchy way: user-owned symlinks, nothing
# copied into system paths. The sidebar (and the squigglebot mascot bundled
# in it) runs inside the omarchy shell as the gersham.squigglebotsidebar
# full-bar plugin.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p ~/.config/omarchy/plugins ~/.config/squigglebot ~/.local/bin
chmod +x bin/squigglebot bin/squigglebot-agent bin/squigglebot-voice
ln -sfn "$PWD" ~/.config/omarchy/plugins/gersham.squigglebotsidebar
ln -sf "$PWD/bin/squigglebot" ~/.local/bin/squigglebot
ln -sf "$PWD/bin/squigglebot-agent" ~/.local/bin/squigglebot-agent
ln -sf "$PWD/bin/squigglebot-voice" ~/.local/bin/squigglebot-voice
# The standalone gersham.squigglebot plugin is folded into this repo. Remove
# a stale install so two copies never register the same `squigglebot` IPC
# target or double-render the mascot.
rm -f ~/.config/omarchy/plugins/gersham.squigglebot
if [ ! -f ~/.config/squigglebot/agent-prompt.md ]; then
  cp prompts/agent-prompt.md ~/.config/squigglebot/agent-prompt.md
  echo "seeded ~/.config/squigglebot/agent-prompt.md"
fi
if [ ! -f ~/.config/squigglebot/config.json ]; then
  cp config.default.json ~/.config/squigglebot/config.json
  echo "seeded ~/.config/squigglebot/config.json"
fi
omarchy plugin enable gersham.squigglebotsidebar 2>/dev/null || true
echo "installed. reload the shell with: omarchy restart shell"
echo "then talk to him: squigglebot tell \"hello\""
