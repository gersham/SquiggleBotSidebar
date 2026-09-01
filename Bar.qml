import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// SquiggleBotSidebar — a total-conversion vertical sidebar for the Omarchy shell.
//
// Takeover is conditional. The sidebar only replaces the bar when the user's
// configured bar position is vertical ("left" or "right"). On a horizontal
// bar it hands the surface back to the built-in omarchy.bar untouched, so
// selecting this plugin can never leave a horizontal user without a bar.
Item {
  id: root

  // ---------------------------------------------------------------- context
  //
  // The host assigns these AFTER construction: a plugin bar arrives through
  // `Loader.source` (shell.qml pluginBarLoader), which builds the root object
  // with nothing set and only then calls configureBar(). None of these may be
  // `required`, and nothing may dereference them at construction time.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: null

  // --------------------------------------------------------------- geometry
  //
  // Kept explicit and in one place so the sidebar is easy to re-proportion.
  property int sidebarWidth: 64
  // One column at 64px. Two would be 26px each, under the 27px Style.bar.iconSlot
  // that widgets size their icon slots from, so they would start clipping.
  property int gridColumns: 1
  property int contentPad: 4
  // Horizontal gutter between grid columns. Unused at one column.
  property int columnGap: 4
  // Vertical space between stacked widgets. Zero on purpose: a widget's
  // implicitHeight already carries its own padding (BarIconButton pads a 16px
  // glyph out to the 27px Style.bar.iconSlot), so the built-in bar stacks them
  // flush at spacing 0. Adding a gap here puts more air between two widgets
  // than the tray puts between its own icons, and the rhythm visibly breaks.
  property int stackGap: 0
  // Width of the squigglebot header slot; the mascot's height follows its
  // blob's aspect ratio. 44 fills most of the 56px inner column without
  // touching it. The omarchy mark sits above the mascot at markSize (the
  // menu affordance).
  property int mascotWidth: 44
  property int markSize: 20
  // Clock sizes are ceilings, not fixed sizes: both labels shrink to fit the
  // column rather than overflow it. These sit at roughly where the 56px inner
  // width lands them, so they bind directly instead of being silently clamped.
  property int clockSize: 18
  property int clockDateSize: 12

  readonly property int columnWidth: Math.floor(
    (sidebarWidth - contentPad * 2 - columnGap * (gridColumns - 1)) / gridColumns)
  readonly property int gridWidth: columnWidth * gridColumns + columnGap * (gridColumns - 1)

  // ------------------------------------------------------------- activation
  readonly property string position: {
    var config = root.barConfig
    if (config && typeof config === "object" && config.position)
      return String(config.position)
    return "top"
  }
  readonly property bool vertical: position === "left" || position === "right"
  // The single switch that decides sidebar vs. passthrough.
  readonly property bool takeover: vertical

  // ----------------------------------------------------------- widget model
  //
  // The hybrid contract: the sidebar owns its own layout, but every widget
  // already in the user's shell.json keeps rendering. The bar's horizontal
  // sections map onto the vertical axis: `left` stacks under the header
  // (top-aligned), `center` floats at the sidebar's vertical middle, and
  // `right` sits above the clock (bottom-aligned).
  // Widgets the sidebar supersedes with its own native surface. Suppressed
  // here rather than removed from shell.json: the entries stay on disk, so
  // switching back to omarchy.bar restores them untouched.
  property var supersededWidgets: [
    "omarchy.menu",             // the sidebar's logo header
    "gersham.menu",             // user clone of omarchy.menu — same surface
    "gersham.squigglebot",      // hosted by the logo header, not the grid
    "gersham.clock-status",     // the sidebar's clock
    "omarchy.clock",
    "gersham.workspaces-icons", // the sidebar's desktop selector (pending)
    "omarchy.workspaces"
  ]

  // Reading root.barConfig inside the call still creates the binding
  // dependency, so the section properties re-resolve on layout changes.
  function sectionEntries(name) {
    var config = root.barConfig
    var layout = config && typeof config === "object" ? config.layout : null
    var section = layout && typeof layout === "object" ? layout[name] : null
    if (!Array.isArray(section)) return []
    var out = []
    for (var j = 0; j < section.length; j++) {
      var entry = section[j]
      if (!entry || typeof entry !== "object" || !entry.id) continue
      if (root.supersededWidgets.indexOf(Util.canonicalWidgetId(String(entry.id))) !== -1) continue
      out.push(entry)
    }
    return out
  }

  readonly property var topEntries: sectionEntries("left")
  readonly property var middleEntries: sectionEntries("center")
  readonly property var bottomEntries: sectionEntries("right")

  // "Tue 7th" — short weekday plus an ordinal day of month. 11th/12th/13th are
  // the exceptions the naive "1st/2nd/3rd" rule gets wrong.
  function ordinalDay(day) {
    var suffix = "th"
    if (day % 100 < 11 || day % 100 > 13) {
      if (day % 10 === 1) suffix = "st"
      else if (day % 10 === 2) suffix = "nd"
      else if (day % 10 === 3) suffix = "rd"
    }
    return day + suffix
  }

  function entryId(entry) {
    return entry && entry.id ? Util.canonicalWidgetId(String(entry.id)) : ""
  }

  // Widgets read their settings off the same object they appear as in
  // shell.json — the id is bookkeeping, everything else is theirs.
  function entrySettings(entry) {
    var out = ({})
    if (!entry || typeof entry !== "object") return out
    for (var key in entry) if (key !== "id") out[key] = entry[key]
    return out
  }

  // ------------------------------------------------------- widget-facing API
  //
  // Hosted widgets get `bar` injected and expect the built-in bar's surface.
  // These are the members widgets actually touch; keep them in sync when a
  // hosted widget turns out to need more.
  property string fontFamily: Style.font.family
  // Widgets size themselves against barSize. In the sidebar a widget lives in
  // one grid cell, so the cell is what "the bar is this thick" means here.
  readonly property int barSize: root.columnWidth
  property bool foregroundAnimationEnabled: true
  property color foreground: Color.bar.text
  property color barForeground: Color.bar.text
  property color background: Color.bar.background
  property color urgent: Color.bar.active
  // The built-in bar's hover-reveal handshake. Nothing in the sidebar hides
  // on hover, so these stay inert — but widgets assign to them.
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property var layoutConfig: {
    var config = root.barConfig
    var layout = config && typeof config === "object" ? config.layout : null
    return layout && typeof layout === "object" ? layout : ({ left: [], center: [], right: [] })
  }

  // Click-target and popout bookkeeping. The built-in bar uses these to close
  // one widget's panel when another opens; the skeleton keeps the registry
  // honest so widgets behave, and routes popouts one-at-a-time.
  property var clickTargets: []
  property var activePopout: null

  function registerClickTarget(target) {
    if (!target || root.clickTargets.indexOf(target) !== -1) return
    var next = root.clickTargets.slice()
    next.push(target)
    root.clickTargets = next
  }

  function unregisterClickTarget(target) {
    root.clickTargets = root.clickTargets.filter(function(item) { return item !== target })
    if (root.activePopout === target) root.activePopout = null
  }

  function requestPopout(target) {
    root.activePopout = target
    return true
  }

  function releasePopout(target) {
    if (root.activePopout === target) root.activePopout = null
  }

  function switchPanelFrom(target) {
    root.activePopout = null
  }

  // BarWidget.broadcast() relays a method to every live instance of a widget,
  // one per monitor surface. Without this the guard in broadcast() makes it a
  // silent no-op and a refresh lands on one screen only.
  property var moduleCells: []

  function registerModuleCell(cell) {
    if (!cell || root.moduleCells.indexOf(cell) !== -1) return
    var next = root.moduleCells.slice()
    next.push(cell)
    root.moduleCells = next
  }

  function unregisterModuleCell(cell) {
    root.moduleCells = root.moduleCells.filter(function(item) { return item !== cell })
  }

  function moduleWidgets(name) {
    var wanted = String(name || "")
    var out = []
    for (var i = 0; i < root.moduleCells.length; i++) {
      var cell = root.moduleCells[i]
      if (cell && cell.moduleName === wanted && cell.widgetItem) out.push(cell.widgetItem)
    }
    return out
  }

  function run(command) {
    if (!command) return
    Quickshell.execDetached(["sh", "-c", String(command)])
  }

  // Tooltips are not implemented in the skeleton. Widgets call these
  // unconditionally, so they must exist and must be harmless.
  function showTooltip(target, text) {}
  function hideTooltip(target) {}

  // Second precision even though the sidebar only shows HH:MM. At minute
  // precision the tick is armed once per minute against the next boundary,
  // and a suspend/resume lands the display in whatever minute it went to
  // sleep in until that stale tick finally fires — a visibly wrong clock for
  // up to a minute after unlock. Ticking every second re-reads the wall clock
  // often enough that resume corrects within a second. It is not the repaint
  // cost it looks like: the formatted strings only change on the minute, and
  // an unchanged Text.text is not re-rendered.
  SystemClock {
    id: sidebarClock

    precision: SystemClock.Seconds
  }

  readonly property string clockTime: Qt.formatDateTime(sidebarClock.date, "HH:mm")
  readonly property string clockDate: Qt.formatDateTime(sidebarClock.date, "ddd") + " "
    + root.ordinalDay(sidebarClock.date.getDate())

  // ------------------------------------------------------------ passthrough
  //
  // Horizontal bar: rebuild the built-in bar rather than render anything of
  // our own. It declares `required` properties, so it has to be created with
  // an initial property map — Loader.source could not satisfy them.
  property var passthroughBar: null

  function destroyPassthrough() {
    if (!root.passthroughBar) return
    root.passthroughBar.destroy()
    root.passthroughBar = null
  }

  function buildPassthrough() {
    if (root.passthroughBar || root.omarchyPath === "" || !root.barConfig) return
    var url = "file://" + root.omarchyPath + "/shell/plugins/bar/Bar.qml"
    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    if (comp.status !== Component.Ready) {
      console.warn("SquiggleBotSidebar: cannot host the built-in bar for a horizontal"
        + " position: " + comp.errorString())
      return
    }
    var builtinManifest = root.shell && root.shell.barManifestFor
      ? root.shell.barManifestFor("omarchy.bar") : null
    root.passthroughBar = comp.createObject(root, {
      omarchyPath: root.omarchyPath,
      barWidgetRegistry: root.barWidgetRegistry,
      barConfig: root.barConfig,
      shell: root.shell,
      manifest: builtinManifest
    })
    if (!root.passthroughBar)
      console.warn("SquiggleBotSidebar: built-in bar passthrough failed to instantiate")
  }

  // Position, and the injected context it is read from, both arrive late and
  // can change at runtime (`omarchy bar set position`), so the two modes are
  // re-decided on every change rather than once at startup.
  function syncMode() {
    if (root.takeover) destroyPassthrough()
    else buildPassthrough()
  }

  onTakeoverChanged: syncMode()
  onBarConfigChanged: {
    if (root.passthroughBar && "barConfig" in root.passthroughBar)
      root.passthroughBar.barConfig = root.barConfig
    syncMode()
  }
  onOmarchyPathChanged: syncMode()
  Component.onCompleted: syncMode()
  Component.onDestruction: destroyPassthrough()

  // ----------------------------------------------------------------- surface
  Variants {
    model: root.takeover ? Quickshell.screens : []

    delegate: Component {
      SidebarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  component SidebarPanel: PanelWindow {
    id: panel

    anchors {
      top: true
      bottom: true
      left: root.position === "left"
      right: root.position === "right"
    }

    implicitWidth: root.sidebarWidth
    color: root.background
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Auto
    WlrLayershell.namespace: "squigglebotsidebar"
    WlrLayershell.layer: WlrLayer.Top

    // The sidebar is opaque, so every pointer event inside it belongs to it —
    // including the ones landing on bare surface between widgets. Without a
    // backstop those fall through to whatever the compositor has underneath,
    // which a scrolling layout will happily put there. Declared first so it
    // sits beneath the real controls and only catches what they did not.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.AllButtons
      onWheel: function(wheel) { wheel.accepted = true }
    }

    Item {
      anchors.fill: parent
      anchors.margins: root.contentPad

      // The sidebar's head: the Omarchy mark on top, squigglebot beneath
      // it. The mark carries the actions of the built-in omarchy.menu
      // widget: left click summons the root menu, right click opens a
      // terminal. The mascot is this repo's own Widget.qml \u2014 the squigglebot
      // bar widget, bundled here since the standalone gersham.squigglebot
      // plugin was folded in \u2014 hosted interactive, so clicks on him are his
      // own: curious on hover, summon (input bubble) or poke on click,
      // click-to-cancel while a voice recording or input bubble is up.
      Item {
        id: logoHeader

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        // Mark block, a contentPad of air, the mascot at his full implicit
        // height, and a contentPad below — he is never squeezed by the
        // sections underneath, which anchor to this item's bottom.
        height: markBox.height
          + (squiggleLoader.item
            ? root.contentPad + squiggleLoader.item.implicitHeight
            : 0)
          + root.contentPad

        // The Omarchy mark: the menu affordance above the mascot.
        Item {
          id: markBox

          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.markSize + root.contentPad * 2

          Text {
            id: logoGlyph

            anchors.centerIn: parent
            font.family: "omarchy"
            font.pixelSize: root.markSize
            color: logoArea.containsMouse
              ? root.foreground
              : Util.alpha(root.foreground, 0.85)
            text: "\ue900"

            Behavior on color { ColorAnimation { duration: 120 } }
          }

          MouseArea {
            id: logoArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                root.run("xdg-terminal-exec")
              } else {
                root.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
              }
            }
          }
        }

        Loader {
          id: squiggleLoader

          anchors.top: markBox.bottom
          anchors.topMargin: root.contentPad
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.mascotWidth
          height: item ? item.implicitHeight : 0
          // The bundled widget (Widget.qml, sibling of this file). Loaded
          // through a Loader rather than declared inline so the header keeps
          // the same moduleCell registration shape as a WidgetCell.
          sourceComponent: Widget {}

          // Registered like a WidgetCell so moduleWidgets() finds the header
          // instance too \u2014 that is how the widget's IPC relay and
          // BarWidget.broadcast() reach every monitor's copy.
          readonly property string moduleName: "gersham.squigglebot"
          readonly property var widgetItem: item

          Component.onCompleted: root.registerModuleCell(squiggleLoader)
          Component.onDestruction: root.unregisterModuleCell(squiggleLoader)

          // Injected twice, like WidgetCell: some widgets build derived
          // state in Component.onCompleted before the first assignment.
          onLoaded: {
            injectProps()
            Qt.callLater(injectProps)
          }

          function injectProps() {
            if (!item) return
            if ("bar" in item) item.bar = root
            if ("moduleName" in item) item.moduleName = "gersham.squigglebot"
            if ("settings" in item) item.settings = ({ interactive: true, scale: 1 })
          }
        }
      }

      // ------------------------------------------------------------- clock
      Column {
        id: clockBlock

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 2

        Text {
          width: clockBlock.width
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: root.clockSize
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: 10
          color: root.foreground
          text: root.clockTime
        }

        Text {
          width: clockBlock.width
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: root.clockDateSize
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: 8
          color: Util.alpha(root.foreground, 0.6)
          text: root.clockDate
        }
      }

      // -------------------------------------------------- widget sections
      //
      // Three plain stacks — the vertical translation of the bar's
      // left/center/right. Zero-height cells (widgets still loading) cost
      // nothing in a Column, and with one grid column no widget ever moves
      // between containers, so no state is lost to reparenting.
      Column {
        id: topSection

        anchors.top: logoHeader.bottom
        anchors.topMargin: root.contentPad * 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.gridWidth
        spacing: root.stackGap

        Repeater {
          model: root.topEntries

          WidgetCell {
            required property var modelData

            entry: modelData
          }
        }
      }

      Column {
        id: middleSection

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.gridWidth
        spacing: root.stackGap

        Repeater {
          model: root.middleEntries

          WidgetCell {
            required property var modelData

            entry: modelData
          }
        }
      }

      Column {
        id: bottomSection

        anchors.bottom: clockBlock.top
        anchors.bottomMargin: root.contentPad * 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.gridWidth
        spacing: root.stackGap

        Repeater {
          model: root.bottomEntries

          WidgetCell {
            required property var modelData

            entry: modelData
          }
        }
      }
    }
  }

  // A single section cell hosting one registry widget. One column wide, and
  // exactly as tall as the widget wants to be — the parent Column stacks it.
  component WidgetCell: Item {
    id: cell

    property var entry: null

    width: root.columnWidth
    height: widgetItem ? Math.max(0, Math.round(widgetItem.implicitHeight)) : 0

    readonly property string moduleName: root.entryId(entry)
    readonly property var widgetItem: widgetLoader.item

    Component.onCompleted: root.registerModuleCell(cell)
    Component.onDestruction: root.unregisterModuleCell(cell)
    readonly property var moduleSettings: root.entrySettings(entry)
    // Reading `widgets` (not just calling a lookup function) is what creates
    // the binding dependency, so the cell re-resolves when a plugin loads,
    // reloads, or is disabled.
    readonly property var registryComponent: {
      var registry = root.barWidgetRegistry
      if (!registry) return null
      var widgets = registry.widgets
      var name = cell.moduleName
      return name && widgets[name] ? widgets[name].component : null
    }

    // No cell chrome. The grid is a layout, not a set of buttons — widgets
    // paint their own affordances and a frame around each one just adds noise.

    Loader {
      id: widgetLoader

      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.height
      active: cell.registryComponent !== null
      sourceComponent: cell.registryComponent

      // Injected twice: some widgets build derived state in
      // Component.onCompleted before the first assignment lands.
      onLoaded: {
        cell.injectProps()
        Qt.callLater(cell.injectProps)
      }
    }

    function injectProps() {
      var target = widgetLoader.item
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = cell.moduleName
      if ("settings" in target) target.settings = cell.moduleSettings
    }

    onModuleSettingsChanged: injectProps()
  }
}
