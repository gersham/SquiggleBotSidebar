# FattyMcSidebar

A total-conversion sidebar for Omarchy’s Quickshell desktop shell.

FattyMcSidebar is intended to become a full Omarchy `bar` plugin: a
replaceable sidebar surface with its own layout, visual language, navigation,
and interaction model. The project is currently a design and implementation
skeleton.

## Goals

- Provide a substantially wider, information-rich Omarchy sidebar.
- Keep the experience coherent as one product rather than a collection of
  unrelated widgets.
- Use Omarchy’s supported plugin boundary and the existing long-running shell.
- Remain removable so users can return to the built-in Omarchy bar safely.

## Planned shape

```text
manifest.json     Plugin metadata and the full-bar entry point
Bar.qml           Main sidebar surface
README.md         User-facing documentation
AGENTS.md         Contributor and agent guidance
```

## Development

The implementation will target Omarchy Quattro and should be validated against
the installed shell before publishing:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Bar.qml
```

## Status

Skeleton only. The plugin manifest and QML implementation will be added after
the sidebar interaction and visual design are settled.

## License

License to be selected before the first public release.
