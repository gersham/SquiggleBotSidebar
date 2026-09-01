import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The conversational side of squigglebot, hosted by the bar widget: the
// agent pipeline (send/reply queues over bin/squigglebot-agent), channels,
// slash commands, the keyboard input bubble, and the breakout chat window.
// Ported from the retired standalone desktop shell.
//
// The host (Widget.qml) provides the mascot: `host` must expose
// say(text, seconds, after, docTitle, docPath), hush(), play(name),
// express(name), rest(), saying, plus geometry via hostScreenRect().
// One ChatHost should exist per shell process (the widget gates on its
// primary instance).
Item {
    id: root

    property var host: null
    // Where the input bubble goes, from the host: { x, y, w, h, side } in
    // screen coordinates; side is which side of the mascot has room.
    property var anchorRect: null

    // ------------------------------------------------------------- channels
    property string currentChannel: "general"
    property var channelList: ["general", "system", "omarchy"]
    property string chatSeeded: ""
    property string pendingChannel: "general"
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/squigglebot"
    readonly property string channelsDir: stateDir + "/channels"

    FileView {
        id: channelsFile
        path: root.stateDir + "/channels.json"
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text())
                if (c.current) root.currentChannel = c.current
                if (Array.isArray(c.list) && c.list.length) root.channelList = c.list
            } catch (err) {}
        }
    }

    function persistChannels() {
        channelsFile.setText(JSON.stringify({ current: currentChannel, list: channelList }) + "\n")
    }

    function switchChannel(name) {
        const n = String(name).toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9_-]/g, "").slice(0, 32)
        if (!n) return
        if (channelList.indexOf(n) === -1) channelList = channelList.concat([n])
        currentChannel = n
        persistChannels()
        chatSeeded = ""
        chatModel.clear()
        chatSeedFile.reload()
    }

    function deleteChannel(name) {
        const n = String(name).toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9_-]/g, "").slice(0, 32)
        if (!n || n === "general") return
        channelList = channelList.filter(c => c !== n)
        if (channelList.indexOf("general") === -1) channelList = ["general"].concat(channelList)
        if (currentChannel === n) switchChannel("general")
        else persistChannels()
        chanDelProc.command = ["rm", "-rf", channelsDir + "/" + n]
        chanDelProc.running = true
    }

    Process {
        id: chanDelProc
    }

    ListModel {
        id: chatModel
    }

    FileView {
        id: chatSeedFile
        path: root.channelsDir + "/" + root.currentChannel + "/history.log"
        printErrors: false
        onLoaded: root.seedChat(text())
    }

    function seedChat(raw) {
        if (chatSeeded === currentChannel) return
        chatSeeded = currentChannel
        chatModel.clear()
        const lines = String(raw).split("\n").slice(-200)
        for (const line of lines) {
            if (line.indexOf("user: ") === 0) {
                chatModel.append({ who: "user", text: line.slice(6), docTitle: "", docPath: "" })
            } else if (line.indexOf("squiggle: ") === 0) {
                const t = line.slice(10)
                if (t !== "(no reply)") chatModel.append({ who: "squiggle", text: t, docTitle: "", docPath: "" })
            }
        }
    }

    // -------------------------------------------------------------- sending
    property string lastHeard: ""
    property string lastDocTitle: ""
    property string lastDocPath: ""
    property bool pondering: false
    property var sendQueue: []
    property var replyQueue: []
    readonly property var ponderPool: ["thinking", "thinking", "thinking", "curious", "listening", "tilt", "peek"]

    // Central send path: "/command" runs locally; a leading "#channel "
    // switches (and sticks to) that channel; "#channel" alone just switches.
    function sendUserText(raw) {
        let text = String(raw).trim()
        if (!text) return false
        if (text[0] === "/") {
            const feedback = handleSlashCommand(text)
            if (feedback) commandFeedback(feedback)
            return false
        }
        const m = text.match(/^#([A-Za-z0-9_-]+)\s*/)
        if (m) {
            switchChannel(m[1])
            text = text.slice(m[0].length).trim()
            if (!text) return false
        }
        lastHeard = text
        askAgent(text)
        return true
    }

    function commandFeedback(msg) {
        chatModel.append({ who: "squiggle", text: msg, docTitle: "", docPath: "" })
        if (!chatOpen && host) host.say(msg, 6, "none", "", "")
    }

    function askAgent(text) {
        chatModel.append({ who: "user", text: String(text).slice(0, 4000), docTitle: "", docPath: "" })
        sendQueue = sendQueue.concat([{ text: text, channel: currentChannel }])
        startNextSend()
    }

    function startNextSend() {
        if (agentProc.running) return
        if (sendQueue.length === 0) {
            pondering = false
            return
        }
        const item = sendQueue[0]
        sendQueue = sendQueue.slice(1)
        pendingChannel = item.channel
        pondering = true
        agentTimeoutTimer.restart()
        agentProc.command = ["squigglebot-agent", "--channel", item.channel, item.text]
        agentProc.running = true
        if (host && !host.saying && !hearing) host.play("thinking")
    }

    Process {
        id: agentProc
        stdout: StdioCollector {
            onStreamFinished: root.handleAgentReply(this.text)
        }
    }

    Timer {
        id: agentTimeoutTimer
        interval: 300000
        onTriggered: agentProc.running = false
    }

    Timer {
        id: ponderTimer
        repeat: true
        running: root.pondering && root.host && !root.host.saying && !root.hearing
        onRunningChanged: if (running) interval = 6000 + Math.random() * 5000
        onTriggered: {
            root.ponderStep()
            interval = 6000 + Math.random() * 5000
        }
    }

    function ponderStep() {
        if (!pondering || !host || host.saying || hearing) return
        let pick = ponderPool[Math.floor(Math.random() * ponderPool.length)]
        host.ponder(pick)
    }

    function handleAgentReply(raw) {
        agentTimeoutTimer.stop()
        let reply = null
        const matches = String(raw).match(/\{[^{}]*\}/g)
        if (matches) {
            try { reply = JSON.parse(matches[matches.length - 1]) } catch (err) {}
        }
        if (!reply || !reply.say) {
            reply = { say: "...my train of thought derailed. Try me again?", after: "sad", seconds: 6 }
        }
        const title = typeof reply.docTitle === "string" ? reply.docTitle.trim().slice(0, 80) : ""
        const path = typeof reply.docPath === "string" ? reply.docPath.trim() : ""
        const okDoc = title.length > 0 && path[0] === "/" && path.slice(-5) === ".html"
        reply.docTitle = okDoc ? title : ""
        reply.docPath = okDoc ? path : ""
        if (pendingChannel === currentChannel) {
            chatModel.append({
                who: "squiggle",
                text: String(reply.say).slice(0, 600),
                docTitle: reply.docTitle,
                docPath: reply.docPath,
            })
        }
        if ((host && host.saying) || hearing) replyQueue = replyQueue.concat([reply])
        else performReply(reply)
        startNextSend()
    }

    function performReply(reply) {
        if (!host) return
        if (reply.docTitle) {
            lastDocTitle = reply.docTitle
            lastDocPath = reply.docPath
        }
        const seconds = Number(reply.seconds) > 0 ? Number(reply.seconds) : 0
        host.say(String(reply.say).slice(0, 600), seconds, reply.after || "happy",
            reply.docTitle || "", reply.docPath || "")
    }

    // The host calls this when its bubble ends; returning true means the
    // queue took over and the host should skip its own after-animation.
    function onHostSayEnded(completed) {
        if (!hearing && replyQueue.length > 0) {
            const next = replyQueue[0]
            replyQueue = replyQueue.slice(1)
            performReply(next)
            return true
        }
        if (pondering) {
            if (host) host.play("thinking")
            return true
        }
        return false
    }

    // -------------------------------------------------------- slash commands
    function handleSlashCommand(text) {
        const parts = text.slice(1).split(/\s+/)
        const cmd = (parts[0] || "").toLowerCase()
        const arg = parts.slice(1).join(" ").trim()
        switch (cmd) {
        case "help":
            return "Commands: /channels, /join <name>, /drop <name>, /amnesia [name|all], "
                + "/model [name|clear], /thinking [minimal|low|medium|high|clear], "
                + "/mode [read|write|full], /agent [codex|claude|...|clear], /tier [fast|flex|clear], /chat [terminal|window], "
                + "/emotion <name>, /play <name>, /sleep, /wake, /doc, /status, /hush. "
                + "Or start a message with #channel."
        case "channels":
            return channelList.map(c => (c === currentChannel ? "▸ #" + c : "#" + c)).join("  ")
        case "join":
            if (!arg) return "usage: /join <name>"
            switchChannel(arg)
            return "now in #" + currentChannel
        case "drop":
            if (!arg) return "usage: /drop <name>"
            if (arg === "general") return "#general can't be dropped"
            deleteChannel(arg)
            return "dropped #" + arg + " (now in #" + currentChannel + ")"
        case "amnesia":
            if (arg === "all") {
                chanDelProc.command = ["rm", "-rf", channelsDir]
                chanDelProc.running = true
                chatSeeded = ""
                chatModel.clear()
                return "all channel memory wiped"
            } else {
                const n = (arg || currentChannel).replace(/[^a-z0-9_-]/g, "")
                chanDelProc.command = ["rm", "-rf", channelsDir + "/" + n]
                chanDelProc.running = true
                if (n === currentChannel) {
                    chatSeeded = ""
                    chatModel.clear()
                }
                return "#" + n + " memory wiped"
            }
        case "model":
        case "thinking":
        case "mode":
        case "agent":
        case "tier":
        case "chat":
            return setAgentConfig(cmd, arg)
        case "emotion":
            if (!arg) return "usage: /emotion <name>"
            if (host) host.express(arg)
            return ""
        case "play":
            if (!arg) return "usage: /play <name>"
            if (host) host.play(arg)
            return ""
        case "sleep":
            if (host) host.goToSleep()
            return ""
        case "wake":
            if (host) host.wakeUp()
            return ""
        case "doc":
            if (!lastDocPath) return "no recent document"
            Qt.openUrlExternally("file://" + lastDocPath)
            return ""
        case "status":
            return statusLine()
        case "hush":
            if (host) host.hush()
            return ""
        default:
            return "unknown command — /help lists them"
        }
    }

    // Agent tuning lives in ~/.config/squigglebot/config.json (the script
    // reads it there); the widget has no full config ownership, so these
    // commands patch just their key via jq.
    property var agentCfg: ({})

    FileView {
        id: agentCfgFile
        path: Quickshell.env("HOME") + "/.config/squigglebot/config.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.agentCfg = JSON.parse(text()) } catch (err) { root.agentCfg = {} }
        }
        onFileChanged: reload()
    }

    function setAgentConfig(cmd, arg) {
        const keys = { model: "agentModel", thinking: "agentThinking", mode: "agentMode", agent: "agentCli", tier: "agentTier", chat: "chatMode" }
        const key = keys[cmd]
        const current = agentCfg[key] || (cmd === "mode" ? "write" : cmd === "chat" ? "terminal" : "")
        if (!arg) return cmd + ": " + (current || "(default)")
        if (cmd === "thinking" && arg !== "clear" && ["minimal", "low", "medium", "high"].indexOf(arg) === -1) {
            return "usage: /thinking minimal|low|medium|high|clear"
        }
        if (cmd === "mode" && ["read", "write", "full"].indexOf(arg) === -1) {
            return "usage: /mode read|write|full"
        }
        if (cmd === "tier" && arg !== "clear" && ["fast", "flex"].indexOf(arg) === -1) {
            return "usage: /tier fast|flex|clear (codex only)"
        }
        if (cmd === "chat" && arg !== "clear" && ["terminal", "window"].indexOf(arg) === -1) {
            return "usage: /chat terminal|window"
        }
        const value = arg === "clear" ? "" : arg
        const cfg = agentCfg
        cfg[key] = value
        agentCfg = cfg
        agentCfgFile.setText(JSON.stringify(cfg, null, 2) + "\n")
        return cmd + ": " + (value || "(default)")
    }

    function statusLine() {
        return "#" + currentChannel
            + " · agent " + (agentCfg.agentCli || "omarchy default")
            + " · model " + (agentCfg.agentModel || "default")
            + " · thinking " + (agentCfg.agentThinking || "default")
            + " · mode " + (agentCfg.agentMode || "write")
            + " · tier " + (agentCfg.agentTier || "default")
            + " · chat " + chatMode
            + (pondering ? " · pondering (" + sendQueue.length + " queued)" : "")
    }

    // Simple markdown + optional doc link, shared by chat entries and the
    // host's speech bubble.
    function markupSay(text, docTitle, docPath) {
        const escapeHtml = value => String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
        let s = escapeHtml(text)
        s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
        s = s.replace(/__([^_]+)__/g, "<u>$1</u>")
        s = s.replace(/\*([^*]+)\*/g, "<i>$1</i>")
        s = s.replace(/_([^_]+)_/g, "<i>$1</i>")
        s = s.replace(/\n/g, "<br>")
        if (docTitle && docPath) {
            const title = escapeHtml(docTitle)
            const anchor = "<a href=\"file://" + escapeHtml(docPath) + "\"><u>" + title + "</u></a>"
            if (s.indexOf("<u>" + title + "</u>") !== -1) s = s.split("<u>" + title + "</u>").join(anchor)
            else if (s.indexOf(title) !== -1) s = s.split(title).join(anchor)
            else s += " — " + anchor
        }
        return s
    }

    // ---------------------------------------------------------- input bubble
    property bool hearing: false

    // ------------------------------------------------------------ voice mode
    // squigglebot-voice drives these through the widget's IPC. The input box
    // doubles as the voice surface: a live waveform while recording, a calm
    // shimmer plus "transcribing…" while voxtype works on the take, then the
    // transcript itself for a few seconds — already sent to the agent — so
    // you can see what you said. Phases: "" | recording | transcribing | echo.
    property string voicePhase: ""
    readonly property bool voiceUp: voicePhase !== ""
    readonly property int voiceBars: 24
    property var voiceLevels: []
    property string voiceText: ""

    function voiceReset() {
        const l = []
        for (let i = 0; i < voiceBars; i++) l.push(0.08)
        voiceLevels = l
    }

    function voiceBegin() {
        echoTimer.stop()
        if (host && host.anchorRectNow) anchorRect = host.anchorRectNow()
        voiceReset()
        voiceText = ""
        inputField.text = ""
        inputWin.expanded = false
        voicePhase = "recording"
    }

    function voicePush(v) {
        const level = Math.min(1, Math.max(0, Number(v) || 0))
        voiceLevels = voiceLevels.slice(1).concat([level])
    }

    function voiceTranscribing() {
        if (voicePhase === "") voiceBegin()
        voicePhase = "transcribing"
    }

    // The transcript: shown in the box, sent right away, dismissed after a
    // reading-length timeout.
    function voiceHeard(text) {
        const t = String(text || "").trim()
        if (!t) {
            voiceEnd()
            return
        }
        if (voicePhase === "") voiceBegin()
        voiceText = t
        inputField.text = t
        voicePhase = "echo"
        echoTimer.interval = Math.min(9000, Math.max(3000, 1800 + 45 * t.length))
        echoTimer.restart()
        sendUserText(t)
    }

    // The script's voiceStop: the take is over (cancelled, or nothing heard).
    // An echo already showing stays until its timer.
    function voiceStopped() {
        if (voicePhase !== "echo") voiceEnd()
    }

    function voiceEnd() {
        echoTimer.stop()
        voicePhase = ""
        voiceText = ""
        if (!hearing) inputField.text = ""
    }

    Timer {
        id: echoTimer
        onTriggered: root.voiceEnd()
    }

    // With no fresh levels (transcribing) the bars decay to a calm shimmer.
    Timer {
        interval: 120
        repeat: true
        running: root.voicePhase === "recording" || root.voicePhase === "transcribing"
        onTriggered: root.voiceLevels = root.voiceLevels.map(l => Math.max(0.06, l * 0.82))
    }

    // The box's ✕ means different things per state.
    function dismissInput() {
        if (hearing) {
            closeInput(false)
            return
        }
        if (voicePhase === "echo") {
            voiceEnd()
            return
        }
        if (voiceUp && host) host.cancelInProgress()
    }

    // TEMP diagnostic: raw key press/release timing seen by the focused
    // input field, for probing what the NuPhy AI key actually emits.
    property var keyEvents: []

    function debugKey(kind, event) {
        keyEvents = keyEvents.concat([{
            t: Date.now(),
            kind: kind,
            key: event.key,
            native: event.nativeScanCode,
            autorepeat: event.isAutoRepeat,
        }])
        if (keyEvents.length > 200) keyEvents = keyEvents.slice(-200)
    }

    function openInput() {
        voiceEnd()
        if (chatOpen) {
            chatInput.forceActiveFocus()
            return
        }
        if (host) {
            if (host.anchorRectNow) anchorRect = host.anchorRectNow()
            host.hush()
            host.wakeIfAsleep()
            host.play("listening")
        }
        hearing = true
        inputField.text = ""
        inputWin.expanded = false
        inputField.forceActiveFocus()
    }

    function closeInput(send) {
        if (!hearing) return
        const text = inputField.text.trim()
        hearing = false
        let sent = false
        if (send && text) sent = sendUserText(text)
        if (host && !sent && !host.saying) host.play(pondering ? "thinking" : "idle")
        if (!hearing && replyQueue.length > 0 && host && !host.saying) {
            const next = replyQueue[0]
            replyQueue = replyQueue.slice(1)
            performReply(next)
        }
    }

    // Voice variant of summon, driven by squigglebot-voice: a plain toggle.
    // A tap on an open input bubble dismisses it and nothing more — it never
    // cycles into a recording (voice is the double-tap/hold gesture, and only
    // from a quiet state; see voiceGate in Widget.qml).
    function voiceSummon() {
        if (chatOpen) {
            closeChat()
            return "closed"
        }
        if (hearing) {
            closeInput(false)
            return "closed"
        }
        openInput()
        return "input"
    }

    // Hotkey entry point: input when nothing is up; dismiss chat first;
    // toggle the input closed; his bubble showing → replace with input.
    function summon() {
        if (chatOpen) {
            closeChat()
            return "chat-closed"
        }
        if (hearing) {
            closeInput(false)
            return "closed"
        }
        openInput()
        return "listening"
    }

    PanelWindow {
        id: inputWin
        visible: (root.hearing || root.voiceUp) && !root.chatOpen
        color: "transparent"
        // Ignore, not a zero zone: margins below are computed in absolute
        // screen coordinates from the mascot's anchorRect, but a zero-zone
        // surface is still pushed right by the bar's own exclusive zone —
        // which landed the box a full bar-width away from the mascot.
        exclusionMode: ExclusionMode.Ignore
        screen: Quickshell.screens[0] || null

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "squigglebot-input"
        // Only typing grabs the keyboard; the voice phases just display.
        WlrLayershell.keyboardFocus: visible && root.hearing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: if (visible && root.hearing) inputField.forceActiveFocus()

        readonly property var a: root.anchorRect || null
        readonly property real refH: a ? a.h : 130
        readonly property real fontPx: Math.max(14, refH * 0.17)
        readonly property real tailW: Math.max(12, refH * 0.09)
        readonly property real padH: fontPx * 0.7
        readonly property real padV: fontPx * 0.55
        readonly property real gap: Math.max(10, refH * 0.12)
        property bool expanded: false
        readonly property real maxViewH: (screen ? screen.height : 1080) * 0.45
        // The channel label sits above the box, outside it — and #general,
        // the default, goes unlabelled entirely.
        readonly property bool channelShown: root.currentChannel !== "general"
        readonly property real labelH: channelShown ? Math.max(16, fontPx * 0.9) : 0
        readonly property real boxH: Math.ceil(Math.max(refH * 0.5,
            Math.min(inputField.implicitHeight, maxViewH) + padV * 2))
        // Sharp (unblurred) black drop shadow behind the box and label, so
        // the accent outline reads on light backgrounds. The window is grown
        // by the offset; the box keeps its position and the shadow fills the
        // extra right/bottom sliver.
        readonly property real shadowOff: 3
        implicitWidth: {
            const sw = screen ? screen.width : 3200
            if (expanded) return Math.round(sw * 0.5) + shadowOff
            return Math.round(Math.min(sw * 0.2, Math.max(380, refH * 2.8))) + shadowOff
        }
        implicitHeight: Math.ceil(boxH + labelH + shadowOff)

        anchors {
            top: true
            left: true
        }
        margins {
            left: {
                if (!inputWin.a) return 40
                return Math.round(Math.max(0, inputWin.a.side === "right"
                    ? inputWin.a.x + inputWin.a.w + inputWin.gap
                    : inputWin.a.x - inputWin.gap - inputWin.implicitWidth))
            }
            top: {
                if (!inputWin.a || !inputWin.screen) return 40
                // Center the box itself on the mascot; the channel label
                // rides above it and doesn't shift the box.
                const gy = inputWin.a.y + inputWin.a.h / 2 - inputWin.boxH / 2 - inputWin.labelH
                return Math.round(Math.min(inputWin.screen.height - inputWin.implicitHeight, Math.max(0, gy)))
            }
        }

        // The channel, outside and above the box; #general stays unlabelled.
        // Its shadow is a black twin offset behind it — sharp, no blur.
        Text {
            visible: channelLabel.visible
            x: channelLabel.x + 2
            y: channelLabel.y + 2
            text: channelLabel.text
            font: channelLabel.font
            color: "#000000"
        }

        Text {
            id: channelLabel
            visible: inputWin.channelShown
            anchors.left: parent.left
            anchors.leftMargin: inputRect.radius
            anchors.bottom: inputRect.top
            anchors.bottomMargin: 2
            text: "#" + root.currentChannel
            font.pixelSize: Math.max(11, inputWin.fontPx * 0.55)
            font.bold: true
            color: inputRect.border.color
        }

        // The box's shadow: same rounded shape, shifted down-right, hard edge.
        Rectangle {
            anchors.fill: inputRect
            anchors.leftMargin: inputWin.shadowOff
            anchors.topMargin: inputWin.shadowOff
            anchors.rightMargin: -inputWin.shadowOff
            anchors.bottomMargin: -inputWin.shadowOff
            radius: inputRect.radius
            color: "#000000"
        }

        Rectangle {
            id: inputRect
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: inputWin.shadowOff
            anchors.bottom: parent.bottom
            anchors.bottomMargin: inputWin.shadowOff
            height: inputWin.boxH
            radius: Math.min(14, height * 0.28)
            color: "#000000"
            border.width: 2
            border.color: root.host ? root.host.accentHex : "#d3a62a"

            // Close: the bubble grabs the keyboard exclusively, so the mouse
            // must always have a way out. A full-bleed accent rail down the
            // box's right edge, black ✕ on it.
            Rectangle {
                id: inputCloseBtn
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(30, inputWin.fontPx * 1.6)
                color: inputCloseMa.containsMouse
                    ? Qt.lighter(inputRect.border.color, 1.15)
                    : inputRect.border.color
                topRightRadius: inputRect.radius
                bottomRightRadius: inputRect.radius
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: Math.max(16, inputWin.fontPx * 0.9)
                    font.bold: true
                    color: "#000000"
                }
                MouseArea {
                    id: inputCloseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissInput()
                }
            }

            Flickable {
                id: inputFlick
                x: inputWin.padH
                y: Math.max(inputWin.padV, (parent.height - height) / 2)
                width: inputCloseBtn.x - x - inputWin.padH * 0.5
                height: Math.min(inputField.implicitHeight, inputWin.maxViewH)
                contentWidth: width
                contentHeight: inputField.implicitHeight
                clip: true
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                function ensureVisible(r) {
                    if (contentY > r.y) contentY = r.y
                    else if (contentY + height < r.y + r.height) contentY = r.y + r.height - height
                }

                TextEdit {
                    id: inputField
                    width: inputFlick.width
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: inputWin.fontPx
                    font.bold: true
                    color: root.host ? root.host.fgHex : "#d2d0c8"
                    selectionColor: inputRect.border.color
                    cursorVisible: root.hearing
                    readOnly: root.voicePhase !== ""
                    focus: true

                    onTextChanged: {
                        if (text.length > 4000) {
                            text = text.slice(0, 4000)
                            cursorPosition = text.length
                        }
                        const m = text.match(/^#([A-Za-z0-9_-]+)\s/)
                        if (m) {
                            root.switchChannel(m[1])
                            const pos = cursorPosition
                            text = text.slice(m[0].length)
                            cursorPosition = Math.max(0, pos - m[0].length)
                        }
                        if (lineCount > 2) inputWin.expanded = true
                        else if (text.length === 0) inputWin.expanded = false
                    }
                    onCursorRectangleChanged: inputFlick.ensureVisible(cursorRectangle)
                    Keys.onPressed: event => root.debugKey("down", event)
                    Keys.onReleased: event => root.debugKey("up", event)
                    Keys.onReturnPressed: event => {
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false
                        } else if (event.modifiers & Qt.ControlModifier) {
                            root.closeInput(true)
                            root.openChat()
                        } else {
                            root.closeInput(true)
                        }
                    }
                    Keys.onEnterPressed: event => root.closeInput(true)
                    Keys.onEscapePressed: event => root.closeInput(false)
                }
            }

            // Voice: the waveform lives here, in the box, not over the mascot.
            Row {
                id: voiceWave
                visible: root.voicePhase === "recording" || root.voicePhase === "transcribing"
                x: inputWin.padH
                anchors.verticalCenter: parent.verticalCenter
                height: Math.round(parent.height * 0.6)
                spacing: 3
                readonly property real barW: Math.max(3, Math.min(10, Math.floor(
                    (inputCloseBtn.x - inputWin.padH * 2 - transcribingLabel.width - spacing * root.voiceBars) / root.voiceBars)))

                Repeater {
                    model: root.voiceBars

                    Rectangle {
                        required property int index
                        readonly property real level: root.voiceLevels[index] || 0
                        width: voiceWave.barW
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.max(3, voiceWave.height * (0.08 + level * 0.92))
                        color: inputRect.border.color

                        Behavior on height {
                            NumberAnimation { duration: 90 }
                        }
                    }
                }
            }

            Text {
                id: transcribingLabel
                visible: root.voicePhase === "transcribing"
                width: visible ? implicitWidth : 0
                anchors.right: inputCloseBtn.left
                anchors.rightMargin: inputWin.padH * 0.6
                anchors.verticalCenter: parent.verticalCenter
                text: "transcribing…"
                font.pixelSize: Math.max(11, inputWin.fontPx * 0.6)
                font.italic: true
                color: inputRect.border.color
                opacity: 0.85
            }
        }
    }

    // ------------------------------------------------------------ chat window
    property bool chatOpen: false
    property bool channelPanelOpen: false

    // Breakout: by default the channel's conversation opens in a floating
    // terminal running the agent's own interactive CLI, resumed on the same
    // thread the bubble uses (squigglebot-chat). chatMode "window" in
    // config.json keeps the built-in chat window instead; agents without
    // resumable sessions fall back to it automatically (launcher exit 3).
    readonly property string chatMode: agentCfg.chatMode === "window" ? "window" : "terminal"

    function openChat() {
        if (hearing) closeInput(false)
        if (chatMode === "terminal") {
            if (chatLaunchProc.running) return
            chatLaunchProc.command = ["squigglebot-chat", currentChannel]
            chatLaunchProc.running = true
            // First open on a channel bootstraps the thread: seconds of agent
            // time. He visibly thinks until the terminal is up.
            if (host && !host.saying) host.play("thinking")
            return
        }
        openChatWindow()
    }

    function openChatWindow() {
        chatOpen = true
        if (hearing) closeInput(false)
        Qt.callLater(() => chatInput.forceActiveFocus())
        if (chatSavedX >= 0) chatMoveTimer.restart()
    }

    Process {
        id: chatLaunchProc
        onExited: (exitCode, exitStatus) => {
            if (root.host && !root.host.saying && !root.hearing && !root.pondering) root.host.rest()
            if (exitCode === 3) root.openChatWindow()
            else if (exitCode !== 0) root.commandFeedback("...couldn't open the terminal chat (exit " + exitCode + ").")
        }
    }

    function closeChat() {
        chatOpen = false
        channelPanelOpen = false
    }

    function chatSend(text) {
        sendUserText(text)
    }

    // Geometry memory (state file; polled while open).
    property int chatSavedW: 520
    property int chatSavedH: 680
    property int chatSavedX: -1
    property int chatSavedY: -1

    FileView {
        id: chatStateFile
        path: root.stateDir + "/chatwin.json"
        printErrors: false
        onLoaded: {
            try {
                const g = JSON.parse(text())
                if (g.w > 0) root.chatSavedW = g.w
                if (g.h > 0) root.chatSavedH = g.h
                if (Number.isFinite(g.x)) root.chatSavedX = g.x
                if (Number.isFinite(g.y)) root.chatSavedY = g.y
            } catch (err) {}
        }
    }

    Timer {
        id: chatMoveTimer
        interval: 350
        onTriggered: {
            if (!root.chatOpen || root.chatSavedX < 0) return
            chatMoveProc.command = ["hyprctl",
                "dispatch hl.dsp.window.move({x = " + root.chatSavedX + ", y = " + root.chatSavedY + "})"]
            chatMoveProc.running = true
        }
    }

    Process {
        id: chatMoveProc
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.chatOpen
        onTriggered: if (!chatGeomProc.running) chatGeomProc.running = true
    }

    Process {
        id: chatGeomProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.captureChatGeom(this.text)
        }
    }

    function captureChatGeom(raw) {
        let clients = null
        try { clients = JSON.parse(raw) } catch (err) { return }
        for (const c of clients) {
            if (c.title !== "Squigglebot Chat") continue
            const w = c.size[0], h = c.size[1], x = c.at[0], y = c.at[1]
            if (w === chatSavedW && h === chatSavedH && x === chatSavedX && y === chatSavedY) return
            chatSavedW = w
            chatSavedH = h
            chatSavedX = x
            chatSavedY = y
            chatStateFile.setText(JSON.stringify({ w: w, h: h, x: x, y: y }) + "\n")
            return
        }
    }

    FloatingWindow {
        id: chatWin
        visible: root.chatOpen
        title: "Squigglebot Chat"
        minimumSize: Qt.size(380, 420)
        color: root.host ? root.host.bgHex : "#181a1c"
        onVisibleChanged: {
            if (visible) {
                implicitWidth = root.chatSavedW
                implicitHeight = root.chatSavedH
                Qt.callLater(() => chatInput.forceActiveFocus())
            }
        }
        Component.onCompleted: {
            implicitWidth = root.chatSavedW
            implicitHeight = root.chatSavedH
        }

        readonly property color fg: root.host ? root.host.fgHex : "#d2d0c8"
        readonly property color accent: root.host ? root.host.accentHex : "#d3a62a"
        readonly property color panel: root.host ? root.host.panelHex : "#25282b"
        readonly property color inkOnAccent: root.host ? root.host.eyeHex : "#181a1c"

        Rectangle {
            anchors.fill: parent
            color: chatWin.color
        }

        FocusScope {
            anchors.fill: parent
            anchors.margins: 14
            focus: true

            Item {
                id: chatHeader
                width: parent.width
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "squigglebot"
                    font.pixelSize: 16
                    font.bold: true
                    color: chatWin.fg
                }
                Text {
                    x: 118
                    anchors.verticalCenter: parent.verticalCenter
                    text: "#" + root.currentChannel
                    font.pixelSize: 14
                    color: chatWin.accent
                }
                Rectangle {
                    width: 26
                    height: 26
                    radius: 6
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: chatCloseMa.containsMouse ? chatWin.panel : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 14
                        color: chatWin.fg
                    }
                    MouseArea {
                        id: chatCloseMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.closeChat()
                    }
                }
            }

            ListView {
                id: chatView
                anchors.top: chatHeader.bottom
                anchors.topMargin: 10
                anchors.bottom: chatInputBox.top
                anchors.bottomMargin: 10
                width: parent.width
                model: chatModel
                spacing: 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onCountChanged: Qt.callLater(positionViewAtEnd)
                Component.onCompleted: positionViewAtEnd()

                delegate: Item {
                    width: chatView.width
                    height: msgBubble.height

                    Rectangle {
                        id: msgBubble
                        readonly property bool mine: model.who === "user"
                        width: Math.min(msgText.implicitWidth + 26, chatView.width * 0.86)
                        height: msgText.implicitHeight + 18
                        radius: 10
                        x: mine ? chatView.width - width : 0
                        color: mine ? chatWin.panel : chatWin.accent

                        Text {
                            id: msgText
                            x: 13
                            y: 9
                            width: Math.min(implicitWidth, chatView.width * 0.86 - 26)
                            text: root.markupSay(model.text, model.docTitle, model.docPath)
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            font.pixelSize: 15
                            color: msgBubble.mine ? chatWin.fg : chatWin.inkOnAccent
                            linkColor: color
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }
                }
            }

            Rectangle {
                id: channelPanel
                visible: root.channelPanelOpen
                anchors.bottom: chatInputBox.top
                anchors.bottomMargin: 8
                width: parent.width
                height: channelFlow.implicitHeight + 20
                radius: 10
                color: chatWin.panel
                z: 2

                Flow {
                    id: channelFlow
                    x: 10
                    y: 10
                    width: parent.width - 20
                    spacing: 6

                    Repeater {
                        model: root.channelList
                        delegate: Rectangle {
                            id: chip
                            required property string modelData
                            readonly property bool active: modelData === root.currentChannel
                            readonly property bool deletable: modelData !== "general" && chipMa.containsMouse
                            width: chipLabel.implicitWidth + 18 + (deletable ? 16 : 0)
                            height: 26
                            radius: 13
                            color: active ? chatWin.accent : chatWin.color
                            Text {
                                id: chipLabel
                                x: 9
                                anchors.verticalCenter: parent.verticalCenter
                                text: "#" + chip.modelData
                                font.pixelSize: 13
                                font.bold: chip.active
                                color: chip.active ? chatWin.inkOnAccent : chatWin.fg
                            }
                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.switchChannel(chip.modelData)
                                    root.channelPanelOpen = false
                                    chatInput.forceActiveFocus()
                                }
                            }
                            Text {
                                visible: chip.deletable
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "×"
                                font.pixelSize: 14
                                font.bold: true
                                color: chip.active ? chatWin.inkOnAccent : chatWin.fg
                                opacity: 0.7
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: root.deleteChannel(chip.modelData)
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: Math.max(90, newChannelInput.implicitWidth + 26)
                        height: 26
                        radius: 13
                        color: chatWin.color
                        border.width: 1
                        border.color: chatWin.accent
                        TextInput {
                            id: newChannelInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: 13
                            color: chatWin.fg
                            clip: true
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !newChannelInput.text && !newChannelInput.activeFocus
                                text: "+ new"
                                font.pixelSize: 13
                                color: chatWin.fg
                                opacity: 0.5
                            }
                            onAccepted: {
                                root.switchChannel(text)
                                text = ""
                                root.channelPanelOpen = false
                                chatInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: chatInputBox
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.min(150, Math.max(46, chatInput.implicitHeight + 20))
                radius: 10
                color: "#000000"
                border.width: 2
                border.color: chatWin.accent

                MouseArea {
                    anchors.fill: parent
                    onClicked: chatInput.forceActiveFocus()
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 6
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: chevronMa.containsMouse || root.channelPanelOpen ? chatWin.panel : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: root.channelPanelOpen ? "⌄" : "⌃"
                        font.pixelSize: 13
                        font.bold: true
                        color: chatWin.accent
                    }
                    MouseArea {
                        id: chevronMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.channelPanelOpen = !root.channelPanelOpen
                    }
                }

                Flickable {
                    id: chatInputFlick
                    x: 40
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 52
                    height: Math.min(chatInput.implicitHeight, 126)
                    contentWidth: width
                    contentHeight: chatInput.implicitHeight
                    clip: true
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    function ensureVisible(r) {
                        if (contentY > r.y) contentY = r.y
                        else if (contentY + height < r.y + r.height) contentY = r.y + r.height - height
                    }

                    TextEdit {
                        id: chatInput
                        width: chatInputFlick.width
                        wrapMode: TextEdit.Wrap
                        font.pixelSize: 15
                        color: chatWin.fg
                        selectionColor: chatWin.accent
                        focus: true
                        onCursorRectangleChanged: chatInputFlick.ensureVisible(cursorRectangle)
                        onTextChanged: {
                            if (text.length > 4000) {
                                text = text.slice(0, 4000)
                                cursorPosition = text.length
                            }
                            const m = text.match(/^#([A-Za-z0-9_-]+)\s/)
                            if (m) {
                                root.switchChannel(m[1])
                                const pos = cursorPosition
                                text = text.slice(m[0].length)
                                cursorPosition = Math.max(0, pos - m[0].length)
                            }
                        }
                        Keys.onReturnPressed: event => {
                            if (event.modifiers & Qt.ShiftModifier) {
                                event.accepted = false
                            } else {
                                root.chatSend(chatInput.text)
                                chatInput.text = ""
                            }
                        }
                        Keys.onEnterPressed: event => {
                            root.chatSend(chatInput.text)
                            chatInput.text = ""
                        }
                        Keys.onEscapePressed: event => root.closeChat()
                    }
                }
            }
        }
    }
}
