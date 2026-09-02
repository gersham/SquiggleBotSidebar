import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "quickshell"
import "quickshell/engine/controller.mjs" as Controller
import "quickshell/engine/definition.mjs" as Def
import "quickshell/engine/preset.mjs" as Preset

// Squigglebot as an embeddable Omarchy bar widget.
//
// A host bar (the built-in omarchy.bar, or a full-bar plugin like
// SquiggleBotSidebar) discovers this through the plugin registry and hosts it
// like any other bar-widget: `bar`, `moduleName`, and `settings` are
// injected, geometry comes from the bar's cross axis, and the mascot idles,
// blinks, and follows the omarchy theme's colors.
//
// Interaction is opt-out: by default the widget carries its own hover
// (curious) and click (poke) behavior. A host that wants the surface for its
// own click actions — SquiggleBotSidebar's header opens the root menu — sets
// `interactive: false` in settings and drives the reactions through the
// public API instead: poke(), express(name), play(name), rest().
BarWidget {
  id: root

  // -------------------------------------------------------------- settings
  readonly property real scaleFactor: setting("scale", 0.8)
  readonly property bool interactive: setting("interactive", true)
  readonly property bool mouthOn: setting("mouth", true)
  readonly property real idleFps: setting("idleFps", 6)
  readonly property real busyFps: setting("busyFps", 30)
  readonly property string shapeName: setting("shape", "round")
  readonly property string pokeAnimation: setting("pokeAnimation", "surprised")

  // Colors accept a hex value or an omarchy theme key. Unlike the desktop
  // mascot, which parses colors.toml itself, the widget runs inside the
  // shell and reads the already-parsed reactive Color singleton — so it
  // recolors on theme switch with no file watching.
  function themeColor(name) {
    if (name === "accent") return Color.accent
    if (name === "foreground") return Color.foreground
    if (name === "background") return Color.bar.background
    if (name === "muted") return Color.muted
    if (name === "urgent") return Color.urgent
    return undefined
  }

  // The engine validates colors as six-digit hex. QML color.toString() emits
  // "#aarrggbb" whenever the theme carries alpha, so format from channels.
  function hex6(c) {
    function channel(v) {
      var n = Math.round(Math.min(1, Math.max(0, v)) * 255)
      return (n < 16 ? "0" : "") + n.toString(16)
    }
    return "#" + channel(c.r) + channel(c.g) + channel(c.b)
  }

  function resolveColor(value, fallback) {
    var s = String(value || "")
    if (s[0] === "#") return s
    var c = themeColor(s)
    return c !== undefined ? hex6(c) : fallback
  }

  readonly property string bodyHex: resolveColor(setting("bodyColor", "accent"), "#d3a62a")
  readonly property string eyeHex: resolveColor(setting("eyeColor", "background"), "#181a1c")

  // Shared palette for the conversation windows (ChatHost).
  readonly property string accentHex: resolveColor("accent", "#d3a62a")
  readonly property string fgHex: resolveColor("foreground", "#d2d0c8")
  readonly property string bgHex: resolveColor("background", "#181a1c")
  readonly property string panelHex: hex6(Qt.lighter(Qt.color(bgHex), 1.45))

  // -------------------------------------------------------------- geometry
  //
  // Region of the engine's fixed 560x560 viewbox that hugs the blob
  // (CHARACTER_SCALE 1.28, body center at 280/280) so the mascot fills its
  // item instead of floating in dead margin. No ground shadow in a bar.
  // The margins leave room for his body language: hops lift him up to
  // ~42px and a squish bulges him ~20px wider (preset.mjs addExpressiveSet),
  // and the Mascot renders into a clipped layer.
  property var blobDims: ({ w: 220, h: 270 })
  readonly property real hugPadX: 24
  readonly property real hugPadY: 44
  readonly property real hugL: 280 - (blobDims.w / 2) * 1.28 - hugPadX
  readonly property real hugT: 280 - (blobDims.h / 2) * 1.28 - hugPadY
  readonly property real hugW: blobDims.w * 1.28 + hugPadX * 2
  readonly property real hugH: blobDims.h * 1.28 + hugPadY * 2

  // The bar's cross axis bounds the mascot: slot width in a vertical bar,
  // row height in a horizontal one. The host assigns real geometry after
  // construction, so fall back to barSize until it lands.
  readonly property real crossSize: vertical
    ? (width > 0 ? width : barSize)
    : (height > 0 ? height : barSize)
  readonly property real drawWidth: vertical
    ? crossSize * scaleFactor
    : crossSize * scaleFactor * hugW / hugH
  readonly property real drawHeight: drawWidth * hugH / hugW

  implicitWidth: vertical ? barSize : Math.round(drawWidth) + 4
  implicitHeight: vertical ? Math.round(drawHeight) + 4 : barSize

  // ---------------------------------------------------------------- engine
  property var ctl: null
  property var mascotScene: null
  property bool engineActive: true
  property double lastFrameMs: 0

  function rebuildMascot() {
    var def = Preset.buildMascotDefinition({
      shape: root.shapeName,
      color: root.bodyHex,
      eyeColor: root.eyeHex,
      eyes: setting("eyes", null)
    })
    var check = Def.validateDefinition(def)
    if (!check.ok) {
      console.warn("squigglebot widget: definition invalid: " + check.errors.join("; "))
      return
    }
    root.blobDims = { w: def.blob.width, h: def.blob.height }
    var now = Date.now()
    if (root.ctl) root.ctl.setDefinition(def, now)
    else root.ctl = Controller.createController(def, {
      animation: "idle",
      mouthEnabled: root.mouthOn,
      now: now
    })
    root.engineActive = true
  }

  // Auto-throttle: full rate only while a transition is in flight (isBusy),
  // ambient breathing at the idle rate. In-process each sample costs a
  // measurable slice of a core — engine JS plus a bar repaint — which is why
  // the ambient default sits at 6fps, not the desktop mascot's 12.
  function tick() {
    if (!root.ctl) return
    var now = Date.now()
    var targetFps = root.ctl.isBusy() ? root.busyFps : Math.min(root.idleFps, root.busyFps)
    if (now - root.lastFrameMs < 1000 / targetFps - 1) return
    root.lastFrameMs = now
    root.mascotScene = root.ctl.sample(now)
    var state = root.ctl.getState()
    root.currentAnim = state.expression ? "" : state.animation
    if (root.ctl.consumeOnceCompleted()) {
      if (root.onceFollowUp) {
        var next = root.onceFollowUp
        root.onceFollowUp = ""
        try { root.ctl.play(next, now) } catch (err) {}
      } else {
        idleReturn.restart()
      }
    }
    root.engineActive = root.ctl.isAnimating()
  }

  // ------------------------------------------------------------ public API
  property string currentAnim: ""
  property string onceFollowUp: ""
  // Any of the idle loops (idle, idle-perky, idle-drowsy).
  readonly property bool idling: currentAnim.indexOf("idle") === 0

  // Every animation start goes through here: a return-to-idle still pending
  // from the previous one-shot must not fire on top of the new animation
  // (it used to knock a fresh doze straight back to idle).
  function startAnim(name) {
    if (!root.ctl) return false
    idleReturn.stop()
    afterReturnTimer.stop()
    try { root.ctl.play(name, Date.now()) } catch (err) { return false }
    root.engineActive = true
    return true
  }

  // Play without counting as user activity: used by fidgets and the return
  // to idle, which must not reset the sleep timer.
  function playQuiet(name) {
    startAnim(name)
  }

  function play(name) {
    if (!root.ctl) return
    startAnim(name)
    root.activity()
  }

  // Like play, but one-shots chain back into thinking — the ponder rotation.
  function ponder(name) {
    if (!root.ctl) return
    if (name === root.currentAnim) name = "thinking"
    if (!startAnim(name)) return
    var anim = root.ctl.getDefinition().animations[name]
    if (anim && anim.playback === "once") root.onceFollowUp = "thinking"
  }

  function express(name) {
    if (!root.ctl) return
    idleReturn.stop()
    afterReturnTimer.stop()
    try { root.ctl.setExpression(name, Date.now()) } catch (err) {}
    root.engineActive = true
    root.activity()
  }

  // Return to idle — not user activity, so the sleep clock keeps running.
  // Which idle depends on how long he has been ignored: drowsy once the
  // sleep countdown is well along, otherwise mostly plain idle with the
  // odd perky stretch for variety.
  function rest() {
    if (root.asleep) return
    if (root.drowsy) playQuiet("idle-drowsy")
    else playQuiet(Math.random() < 0.3 ? "idle-perky" : "idle")
  }

  function poke() {
    play(root.pokeAnimation)
  }

  // --------------------------------------------------------------- sleeping
  //
  // Ignored long enough, he gets drowsy (drowsy idle, yawny fidgets) part
  // way through the countdown, then nods off (`dozing`) into the sleeping
  // loop; any activity wakes him with a stretch (`waking`).
  readonly property real sleepAfterS: setting("sleepAfter", 60)
  readonly property real drowsyFraction: setting("drowsyAt", 0.55)
  readonly property bool asleep: currentAnim === "sleeping" || currentAnim === "dozing"
  property bool drowsy: false
  readonly property bool busyTalking: saying
    || voiceMode
    || (chatHost.item && (chatHost.item.hearing || chatHost.item.pondering || chatHost.item.chatOpen || chatHost.item.voiceUp))

  Timer {
    id: sleepTimer

    interval: root.sleepAfterS * 1000
    running: root.visible && root.sleepAfterS > 0 && !root.asleep && !root.busyTalking
    onRunningChanged: {
      if (running) drowsyTimer.restart()
      else drowsyTimer.stop()
    }
    onTriggered: root.goToSleep()
  }

  Timer {
    id: drowsyTimer

    interval: Math.max(1000, root.sleepAfterS * 1000 * Math.min(0.95, Math.max(0.1, root.drowsyFraction)))
    onTriggered: {
      if (!sleepTimer.running) return
      root.drowsy = true
      if (root.idling) root.rest()
    }
  }

  function activity() {
    root.drowsy = false
    if (root.asleep) root.wakeUp()
    else if (sleepTimer.running) {
      sleepTimer.restart()
      drowsyTimer.restart()
    }
  }

  // Returns what happened, so `squigglebot sleep` can report a refusal.
  function goToSleep() {
    if (!root.ctl) return "error: no engine"
    if (root.asleep) return "already asleep"
    if (root.busyTalking) return "busy"
    drowsyTimer.stop()
    root.drowsy = false
    root.onceFollowUp = "sleeping"
    if (!startAnim("dozing")) {
      root.onceFollowUp = ""
      return "error: no dozing animation"
    }
    return "dozing"
  }

  function wakeUp() {
    root.onceFollowUp = ""
    root.drowsy = false
    if (!root.ctl) return
    // Dozing interrupted mid-nod skips the big stretch; he just perks up.
    startAnim(root.currentAnim === "dozing" ? "surprised" : "waking")
  }

  function wakeIfAsleep() {
    if (root.asleep) root.wakeUp()
  }

  // ---------------------------------------------------------------- fidgets
  //
  // One-shots from preset.mjs, weighted: small looks most often, body
  // business (hop, bounce, wiggle, stretch) now and then. Drowsy fidgets are
  // sleepier. A fidget never repeats back to back.
  readonly property bool fidgetsOn: setting("fidgets", true)
  readonly property real fidgetMinS: setting("fidgetMin", 12)
  readonly property real fidgetMaxS: setting("fidgetMax", 32)
  readonly property var fidgetPool: [
    "glance", "glance", "glance", "look-around",
    "tilt", "tilt", "tilt-right",
    "peek", "peek",
    "hop", "bounce", "wiggle", "stretch",
    "yawn"
  ]
  readonly property var drowsyFidgetPool: ["yawn", "yawn", "yawn", "stretch", "glance", "tilt"]
  property string lastFidget: ""

  function nextFidgetMs() {
    var lo = Math.max(3, root.fidgetMinS) * 1000
    var hi = Math.max(lo, root.fidgetMaxS * 1000)
    // Drowsy: sparser, so the drift toward sleep reads as winding down.
    var mult = root.drowsy ? 1.4 : 1
    return (lo + Math.random() * (hi - lo)) * mult
  }

  function pickFidget() {
    var pool = root.drowsy ? root.drowsyFidgetPool : root.fidgetPool
    var pick = pool[Math.floor(Math.random() * pool.length)]
    if (pick === root.lastFidget && pool.length > 1) pick = pool[Math.floor(Math.random() * pool.length)]
    root.lastFidget = pick
    return pick
  }

  Timer {
    id: fidgetTimer

    repeat: true
    running: root.fidgetsOn && root.visible && root.idling && !root.busyTalking
    onRunningChanged: if (running) interval = root.nextFidgetMs()
    onTriggered: {
      if (root.idling && !root.busyTalking) root.playQuiet(root.pickFidget())
      interval = root.nextFidgetMs()
    }
  }

  // ----------------------------------------------------------------- speech
  //
  // The widget's port of the desktop mascot's say: the same speak-then-listen
  // sequence and timing rules, with the layer-shell bubble replaced by a
  // PopupCard anchored beside the bar. He faces the bubble while it shows.
  property string sayText: ""
  property string sayAfter: ""
  property string sayDocTitle: ""
  property string sayDocPath: ""
  readonly property bool saying: sayText !== ""

  function say(text, seconds, after, docTitle, docPath) {
    var t = String(text || "").trim()
    if (!t) return
    root.wakeIfAsleep()
    root.activity()
    root.sayText = t
    root.sayDocTitle = String(docTitle || "")
    root.sayDocPath = String(docPath || "")
    root.sayAfter = after === "none" ? "" : (after || "happy")
    afterReturnTimer.stop()
    // Display time scales with reading length, generously; the flap only as
    // long as the text would take to say. Same formulas as the desktop.
    var ms = Number(seconds) > 0 ? Number(seconds) * 1000
      : Math.min(30000, Math.max(4000, 3000 + 140 * t.length))
    sayTimer.interval = ms
    sayTimer.restart()
    var words = t.split(/\s+/).length
    speakTimer.interval = Math.min(ms, Math.max(1500, 600 + words * 400))
    speakTimer.restart()
    play("speaking")
    lookAtBubble()
  }

  // He faces whichever side of the bar the bubbles hang on: his own speech
  // bubble while saying, and the input box while you type or talk in it.
  readonly property bool inputBubbleUp: chatHost.item ? (chatHost.item.hearing || chatHost.item.voiceUp) && !chatHost.item.chatOpen : false
  readonly property bool lookingAtBubble: saying || inputBubbleUp
  onLookingAtBubbleChanged: if (lookingAtBubble) lookAtBubble(); else lookAway()

  function lookAtBubble() {
    if (!root.ctl) return
    var pos = root.barPosition
    var look = pos === "left" ? [0.9, 0.1]
      : pos === "right" ? [-0.9, 0.1]
      : pos === "bottom" ? [0, -0.9] : [0, 0.9]
    root.ctl.setLookTarget(look[0], look[1])
    root.engineActive = true
  }

  function lookAway() {
    if (!root.ctl || root.lookingAtBubble) return
    root.ctl.clearLookTarget()
    root.engineActive = true
  }

  function hush() {
    endSay(false)
  }

  // completed = the bubble timed out naturally (vs hush/click dismissal);
  // only then does the after-animation play.
  function endSay(completed) {
    sayTimer.stop()
    speakTimer.stop()
    if (!root.saying) return
    root.sayText = ""
    if (!root.ctl) return
    lookAway()
    // Queued replies (ChatHost) take over instead of the after-animation.
    if (chatHost.item && chatHost.item.onHostSayEnded(completed)) {
      root.engineActive = true
      return
    }
    var state = root.ctl.getState()
    if ((state.animation === "speaking" || state.animation === "listening") && !state.expression) {
      var def = root.ctl.getDefinition()
      var next = completed && root.sayAfter && def.animations[root.sayAfter]
        ? root.sayAfter : "idle"
      if (next === "idle") rest()
      else {
        play(next)
        if (def.animations[next].playback === "loop") afterReturnTimer.restart()
      }
    }
    root.engineActive = true
  }

  Timer {
    id: sayTimer

    onTriggered: root.endSay(true)
  }

  // The flap runs out before the bubble does; "listening" is the post-speech
  // wait state while the bubble lingers.
  Timer {
    id: speakTimer

    onTriggered: {
      if (!root.ctl) return
      var state = root.ctl.getState()
      if (state.animation === "speaking" && !state.expression) root.play("listening")
    }
  }

  Timer {
    id: afterReturnTimer

    interval: 2600
    onTriggered: root.rest()
  }

  onBodyHexChanged: rebuildMascot()
  onEyeHexChanged: rebuildMascot()
  onShapeNameChanged: rebuildMascot()
  onMouthOnChanged: if (root.ctl) root.ctl.setMouthEnabled(root.mouthOn)
  Component.onCompleted: rebuildMascot()

  Timer {
    id: idleReturn

    interval: 900
    onTriggered: root.rest()
  }

  // A Timer, not a FrameAnimation: FrameAnimation calls into JS on every
  // vsync regardless of the sampling throttle, which on a high-refresh
  // display is an order of magnitude more wakeups than the handful of
  // samples per second the mascot actually renders.
  Timer {
    interval: 33
    repeat: true
    running: root.visible && root.engineActive
    onTriggered: root.tick()
  }

  // ------------------------------------------------------------ voice mode
  // squigglebot-voice drives recording/transcription over IPC. The visual
  // surface is the input box (ChatHost: live waveform, "transcribing…", then
  // the transcript); the mascot just listens. voiceMode tracks "a take is in
  // flight" for click-to-cancel and the sleep/fidget gates.
  property bool voiceMode: false

  function voiceBegin() {
    voiceMode = true
    activity()
    if (chatHost.item) chatHost.item.voiceBegin()
    if (!root.saying) play("listening")
  }

  function voicePush(v) {
    if (chatHost.item) chatHost.item.voicePush(v)
  }

  function voiceTranscribing() {
    if (chatHost.item) chatHost.item.voiceTranscribing()
    if (!root.saying) play("thinking")
  }

  // The transcript arrived: ChatHost echoes it in the box and sends it.
  function voiceHeard(text) {
    voiceMode = false
    if (chatHost.item) chatHost.item.voiceHeard(text)
  }

  function voiceEnd() {
    voiceMode = false
    if (chatHost.item) chatHost.item.voiceStopped()
    if (!root.saying && !(chatHost.item && chatHost.item.pondering)) rest()
  }

  // Click-to-cancel: a click on the mascot aborts whatever is mid-flight — a
  // voice recording/transcription, an open input bubble, or a transcript
  // echo. Returns true when something was cancelled, so callers can fall
  // through to their normal click action otherwise. The recording is owned
  // by squigglebot-voice, not the widget, so the abort goes through the
  // script's own cancel verb; resolved relative to this file so the plugin
  // needs no PATH assumptions.
  readonly property string voiceScript: Qt.resolvedUrl("bin/squigglebot-voice").toString().replace(/^file:\/\//, "")

  Process {
    id: voiceCancelProc

    command: [root.voiceScript, "cancel"]
  }

  function cancelInProgress() {
    if (root.voiceMode) {
      voiceCancelProc.running = true
      return true
    }
    if (chatHost.item && chatHost.item.hearing) {
      chatHost.item.closeInput(false)
      return true
    }
    if (chatHost.item && chatHost.item.voiceUp) {
      chatHost.item.voiceEnd()
      return true
    }
    return false
  }

  Mascot {
    anchors.centerIn: parent
    width: Math.round(root.drawWidth)
    height: Math.round(root.drawHeight)
    scene: root.mascotScene
    shadowVisible: false
    contentL: root.hugL
    contentT: root.hugT
    contentW: root.hugW
    contentH: root.hugH
    // Render into an offscreen texture so a mascot frame damages only this
    // item's region, not the host bar's full surface.
    layer.enabled: true
    layer.smooth: true
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    visible: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      // Waking him is the reaction; the curious look waits for a hover
      // that finds him already awake.
      var wasAsleep = root.asleep
      root.activity()
      if (!wasAsleep && !root.busyTalking) root.express("curious")
    }
    onExited: if (!root.busyTalking) root.rest()
    onClicked: {
      if (root.cancelInProgress()) return
      if (chatHost.item) chatHost.item.summon()
      else root.poke()
    }
    onDoubleClicked: if (chatHost.item) chatHost.item.openChat()
  }

  // ----------------------------------------------------------- conversation
  // The full conversational stack (agent, channels, input bubble, chat
  // window) — one per shell process, so only the primary screen's widget
  // instance hosts it.
  readonly property bool primaryHost: {
    const screens = Quickshell.screens
    return !bar || !bar.screen || screens.length === 0 || bar.screen === screens[0]
  }

  Loader {
    id: chatHost

    active: root.primaryHost
    sourceComponent: ChatHost {
      host: root
    }
  }

  // Screen-space rect of the mascot, for anchoring the input bubble. The bar
  // window sits flush on its edge, so its on-screen origin follows from the
  // bar position.
  function anchorRectNow() {
    var window = root.QsWindow.window
    if (!window || !window.screen) return null
    var p = window.contentItem.mapFromItem(root, 0, 0)
    var pos = root.barPosition
    var bx = pos === "right" ? window.screen.width - window.width : 0
    var by = pos === "bottom" ? window.screen.height - window.height : 0
    return {
      x: bx + p.x,
      y: by + p.y,
      w: root.width,
      h: root.height,
      side: pos === "right" ? "left" : "right"
    }
  }

  // The speech bubble: the same SpeechBubble the desktop mascot draws —
  // accent rect, tail pointing at him — in a popup beside the bar, on
  // whichever side the bar faces. Clicking it hushes; ⧉ breaks out into the
  // chat window. Suppressed while the chat window is open (replies land
  // there instead).
  readonly property string barPosition: bar && bar.position ? String(bar.position) : "left"

  PopupWindow {
    id: bubbleWindow

    visible: root.saying && !(chatHost.item && chatHost.item.chatOpen)
    color: "transparent"
    implicitWidth: Math.ceil(speech.implicitWidth)
    implicitHeight: Math.ceil(speech.implicitHeight)

    anchor {
      id: bubbleAnchor

      window: root.QsWindow.window
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var window = root.QsWindow.window
        if (!window) return
        var popupWidth = bubbleWindow.implicitWidth
        var popupHeight = bubbleWindow.implicitHeight
        // Same breathing room the desktop keeps between mascot and bubble.
        var gap = Math.max(10, root.drawWidth * 0.12)
        var localX = root.width / 2 - popupWidth / 2
        var localY = root.height + gap
        if (root.barPosition === "left") {
          localX = root.width + gap
          localY = root.height / 2 - popupHeight / 2
        } else if (root.barPosition === "right") {
          localX = -popupWidth - gap
          localY = root.height / 2 - popupHeight / 2
        } else if (root.barPosition === "bottom") {
          localY = -popupHeight - gap
        }
        var point = window.contentItem.mapFromItem(root, localX, localY)
        bubbleAnchor.rect.x = Math.round(point.x)
        bubbleAnchor.rect.y = Math.round(point.y)
      }
    }

    SpeechBubble {
      id: speech

      anchors.fill: parent
      text: root.sayText
      // The tail sits on the edge facing the mascot: bar on the left means
      // the bubble hangs to the right of him, tail on its left edge.
      tailEdge: root.barPosition === "right" ? "right"
        : root.barPosition === "bottom" ? "bottom"
        : root.barPosition === "top" ? "top" : "left"
      refHeight: root.drawHeight
      maxWidth: {
        var window = root.QsWindow.window
        return window && window.screen ? window.screen.width * 0.2 : 640
      }
      // Long replies get the same 50%-of-screen room the chat input takes.
      wideMaxWidth: {
        var window = root.QsWindow.window
        return window && window.screen ? window.screen.width * 0.5 : 1600
      }
      bubbleColor: root.resolveColor(root.setting("bubbleColor", "accent"), "#d3a62a")
      textColor: root.resolveColor(root.setting("bubbleTextColor", "#000000"), "#000000")
      docTitle: root.sayDocTitle
      docPath: root.sayDocPath
      showBreakout: chatHost.item !== null
      onDismissed: root.hush()
      onBreakout: {
        root.hush()
        if (chatHost.item) chatHost.item.openChat()
      }
    }
  }

  // ------------------------------------------------------------------- IPC
  //
  // The desktop mascot's CLI (bin/squigglebot) talks to its own Quickshell
  // instance's socket, which this widget is not part of: the widget lives in
  // the omarchy shell's instance, so it registers its own target there:
  //
  //   omarchy-shell squigglebot emotion angry
  //   omarchy-shell squigglebot play thinking
  //   omarchy-shell squigglebot poke
  //
  // A bar surface exists per monitor and an IPC target routes to a single
  // handler, so every function relays through the host's instance list —
  // the same reason BarWidget.broadcast() exists. On multi-monitor the
  // duplicate registrations log a harmless "will not be used" warning.
  // Always includes this instance: a host that hosts the widget outside its
  // module registry (or hasn't injected moduleName yet) would otherwise make
  // every relay a silent no-op.
  function instances() {
    var out = [root]
    var items = bar && typeof bar.moduleWidgets === "function" && moduleName
      ? bar.moduleWidgets(moduleName) : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && out.indexOf(items[i]) === -1) out.push(items[i])
    }
    return out
  }

  function relay(method, args) {
    var items = root.instances()
    for (var i = 0; i < items.length; i++) {
      var target = items[i]
      if (target && typeof target[method] === "function")
        target[method].apply(target, args || [])
    }
  }

  IpcHandler {
    target: "squigglebot"

    function ping(): string {
      return "pong"
    }

    function emotion(name: string): string {
      if (!name || name === "none" || name === "clear") root.relay("rest")
      else root.relay("express", [name])
      return "ok"
    }

    function play(name: string): string {
      root.relay("play", [name])
      return "ok"
    }

    function poke(): string {
      root.relay("poke")
      return "ok"
    }

    function say(text: string): string {
      root.relay("say", [text])
      return "ok"
    }

    // say with explicit display seconds (0 = auto) and after-animation
    // ("happy" by default, "none" to skip).
    function sayFor(text: string, seconds: real, after: string): string {
      root.relay("say", [text, seconds, after])
      return "ok"
    }

    function hush(): string {
      root.relay("hush")
      return "ok"
    }

    // ---- conversation (handled by the primary instance's ChatHost) ----
    function summon(): string {
      return chatHost.item ? chatHost.item.summon() : "error: not ready"
    }

    function voiceSummon(): string {
      return chatHost.item ? chatHost.item.voiceSummon() : "error: not ready"
    }

    // Gate for squigglebot-voice's press handler: may this key press start a
    // voice take? "no" while the input bubble or chat window is up, or while
    // squiggle is saying something — a tap then is a dismiss/summon toggle,
    // never push-to-talk.
    function voiceGate(): string {
      const c = chatHost.item
      return (root.saying || (c && (c.hearing || c.chatOpen))) ? "no" : "yes"
    }

    function voiceStart(): string {
      root.relay("voiceBegin")
      return "ok"
    }

    function voiceLevel(v: real): string {
      root.relay("voicePush", [v])
      return "ok"
    }

    function voiceStop(): string {
      root.relay("voiceEnd")
      return "ok"
    }

    // Recording stopped, voxtype is working on it.
    function voiceTranscribing(): string {
      root.relay("voiceTranscribing")
      return "ok"
    }

    // The transcript: echoed in the input box and sent to the agent.
    function voiceHeard(text: string): string {
      root.relay("voiceHeard", [text])
      return "ok"
    }

    // The click-to-cancel path, reachable from the CLI for testing.
    function cancel(): string {
      return root.cancelInProgress() ? "cancelled" : "nothing to cancel"
    }

    // TEMP diagnostic for the AI-key probe.
    function keyEvents(): string {
      return chatHost.item ? JSON.stringify(chatHost.item.keyEvents) : "[]"
    }

    function ask(): string {
      if (!chatHost.item) return "error: not ready"
      if (chatHost.item.hearing) {
        chatHost.item.closeInput(false)
        return "closed"
      }
      chatHost.item.openInput()
      return "listening"
    }

    function tell(text: string): string {
      if (!chatHost.item) return "error: not ready"
      if (!text) return "error: empty message"
      return chatHost.item.sendUserText(text) ? "pondering" : "ok"
    }

    function chat(mode: string): string {
      if (!chatHost.item) return "error: not ready"
      if (mode === "close" || (mode === "toggle" && chatHost.item.chatOpen)) {
        chatHost.item.closeChat()
        return "closed"
      }
      chatHost.item.openChat()
      // Terminal mode hands off to squigglebot-chat; nothing to report open.
      return chatHost.item.chatOpen ? "open" : (chatHost.item.chatMode === "terminal" ? "terminal" : "closed")
    }

    function channel(name: string): string {
      if (!chatHost.item) return "error: not ready"
      if (!name) return chatHost.item.currentChannel
      if (name === "list") return chatHost.item.channelList.join("\n")
      chatHost.item.switchChannel(name)
      return chatHost.item.currentChannel
    }

    function dropChannel(name: string): string {
      if (!chatHost.item) return "error: not ready"
      if (!name || name === "general") return "error: can't drop that"
      chatHost.item.deleteChannel(name)
      return "dropped"
    }

    function heard(): string {
      return chatHost.item ? chatHost.item.lastHeard : ""
    }

    function sleep(): string {
      return root.goToSleep()
    }

    function wake(): string {
      root.wakeUp()
      return "ok"
    }

    function status(): string {
      const c = chatHost.item
      return JSON.stringify({
        state: root.ctl ? root.ctl.getState() : null,
        shape: root.shapeName,
        bodyColor: root.bodyHex,
        eyeColor: root.eyeHex,
        mouth: root.mouthOn,
        interactive: root.interactive,
        instances: root.instances().length,
        asleep: root.asleep,
        saying: root.sayText,
        channel: c ? c.currentChannel : "",
        channels: c ? c.channelList : [],
        hearing: c ? c.hearing : false,
        pondering: c ? c.pondering : false,
        chatOpen: c ? c.chatOpen : false,
        queuedSends: c ? c.sendQueue.length : 0,
        queuedReplies: c ? c.replyQueue.length : 0,
        heard: c ? c.lastHeard : ""
      })
    }
  }
}
