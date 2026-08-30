# AGENTS.md

## Project intent

FattyMcSidebar is a distributable Omarchy Quickshell full-bar plugin. It must
be developed as a user-space plugin and must not require edits to
`/usr/share/omarchy/` or a second Quickshell process.

## Working rules

- Keep the plugin self-contained and removable.
- Treat the installed Omarchy shell and its documented plugin contract as the
  compatibility boundary.
- Prefer Omarchy’s existing `qs.Ui` and `qs.Commons` primitives where they
  provide the needed behavior.
- Keep geometry, colors, and interaction constants explicit and easy to tune.
- Do not silently change the user’s unrelated `shell.json`, `shell.toml`,
  Hyprland configuration, or other plugins.
- Document every external command, dependency, service, privilege boundary,
  and network interaction.
- Preserve a safe recovery path to `omarchy.bar` during development.

## Verification

Before considering a change complete:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Bar.qml
```

Also test discovery, enable/disable, shell restart, removal, multiple
monitors, the supported bar positions, keyboard focus, and recovery to the
built-in bar. Do not claim live behavior from static validation alone.

## Current compatibility note

The local Omarchy 4.0 shell has had a known full-bar plugin loader issue where
injected properties can arrive after QML construction. Keep entry-point
properties compatible with the actual installed runtime and verify the full
bar on the target shell before publishing.
