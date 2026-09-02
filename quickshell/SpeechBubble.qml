import QtQuick
import QtQuick.Shapes

// The squigglebot speech bubble: a rounded rect with a pointed tail aimed at
// the mascot, everything scaled from the mascot's height. Extracted from
// shell.qml's bubble window so the desktop mascot and the bar widget draw the
// same bubble; shell.qml still carries its own copy of these visuals and
// should migrate to this component (its PanelWindow anchoring stays where it
// is — this is only the drawable).
//
// The caller resolves colors and picks the tail edge; `refHeight` is the
// mascot's rendered height, the single knob the proportions follow.
Item {
    id: root

    property string text: ""
    // Edge the tail sits on — the edge facing the mascot.
    property string tailEdge: "left"
    // Mascot height the sizes scale from (the desktop passes its window
    // height, the bar widget its drawn mascot height).
    property real refHeight: 130
    // Hard cap on the bubble's total width, tail included.
    property real maxWidth: 640
    // Wider cap used once the text would wrap past two lines at maxWidth —
    // the same widening the chat input does for long messages. Defaults to
    // maxWidth, i.e. no widening.
    property real wideMaxWidth: maxWidth
    property color bubbleColor: "#d3a62a"
    property color textColor: "#000000"
    // Optional long-form document: its title renders underlined and clicking
    // it opens the file; a break-out button offers the full chat window.
    property string docTitle: ""
    property string docPath: ""
    property bool showBreakout: true

    signal dismissed()
    signal breakout()

    // Simple markdown (**bold**, *italic*, __underline__) plus the doc link.
    function markup(raw) {
        const escapeHtml = value => String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
        let s = escapeHtml(raw)
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

    // Same proportions as the desktop bubble: at least half of squiggle's
    // height, text sized so one line fills that height with a bit of margin;
    // long messages wrap to at most 4 lines (then truncate).
    readonly property real fontPx: Math.max(14, refHeight * 0.24)
    readonly property real tailW: Math.max(12, refHeight * 0.09)
    readonly property real padH: fontPx * 0.6
    readonly property real padV: fontPx * 0.35
    readonly property real minH: Math.max(48, refHeight * 0.5)
    readonly property bool sideTail: tailEdge === "left" || tailEdge === "right"
    // Reserved column for the break-out button, so text never runs under it.
    readonly property real btnZone: showBreakout ? fontPx * 1.9 : 0
    readonly property real chromeW: padH * 2 + (sideTail ? tailW : 0) + btnZone
    readonly property real narrowTextW: maxWidth - chromeW
    readonly property bool expanded: wideMaxWidth > maxWidth && probe.lineCount > 2
    readonly property real maxTextW: (expanded ? wideMaxWidth : maxWidth) - chromeW

    // Invisible twin of the label laid out at the narrow width; its line
    // count decides whether the bubble widens.
    Text {
        id: probe

        visible: false
        width: root.narrowTextW
        text: root.markup(root.text)
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        font.pixelSize: root.fontPx
    }

    implicitWidth: Math.ceil(bubbleLabel.width + padH * 2 + (sideTail ? tailW : 0) + btnZone)
    implicitHeight: Math.ceil(Math.max(minH, bubbleLabel.implicitHeight + padV * 2)
        + (sideTail ? 0 : tailW))

    Rectangle {
        id: bubbleRect

        x: root.tailEdge === "left" ? root.tailW : 0
        y: root.tailEdge === "top" ? root.tailW : 0
        width: root.width - (root.sideTail ? root.tailW : 0)
        height: root.height - (root.sideTail ? 0 : root.tailW)
        radius: Math.min(14, height * 0.28)
        color: root.bubbleColor
        border.width: 0

        Text {
            id: bubbleLabel

            x: root.padH
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.maxTextW)
            text: root.markup(root.text)
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.pixelSize: root.fontPx
            color: root.textColor
            linkColor: color
        }

        // Break-out: continue this in the full chat window.
        Rectangle {
            visible: root.showBreakout
            width: root.fontPx * 1.5
            height: width
            radius: 7
            anchors.right: parent.right
            anchors.rightMargin: root.fontPx * 0.3
            anchors.verticalCenter: parent.verticalCenter
            color: breakoutMa.containsMouse ? Qt.rgba(0, 0, 0, 0.2) : Qt.rgba(0, 0, 0, 0.08)

            Text {
                anchors.centerIn: parent
                text: "⧉"
                font.pixelSize: root.fontPx * 1.05
                color: root.textColor
                opacity: 0.85
            }
            MouseArea {
                id: breakoutMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.breakout()
            }
        }
    }

    // Tail pointing at the mascot: a triangle from the rect's facing edge to
    // the bubble's outer edge, centered on the facing side.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: bubbleRect.color

            readonly property real cx: bubbleRect.x + bubbleRect.width / 2
            readonly property real cy: bubbleRect.y + bubbleRect.height / 2
            readonly property real base: root.tailW * 0.66
            readonly property real inset: root.tailW + 1.5

            startX: root.tailEdge === "left" ? inset
                : root.tailEdge === "right" ? root.width - inset
                : cx - base
            startY: root.tailEdge === "top" ? inset
                : root.tailEdge === "bottom" ? root.height - inset
                : cy - base

            PathLine {
                x: root.tailEdge === "left" ? 0
                    : root.tailEdge === "right" ? root.width
                    : root.width / 2
                y: root.tailEdge === "top" ? 0
                    : root.tailEdge === "bottom" ? root.height
                    : root.height / 2
            }
            PathLine {
                x: root.tailEdge === "left" ? root.tailW + 1.5
                    : root.tailEdge === "right" ? root.width - root.tailW - 1.5
                    : root.width / 2 + root.tailW * 0.66
                y: root.tailEdge === "top" ? root.tailW + 1.5
                    : root.tailEdge === "bottom" ? root.height - root.tailW - 1.5
                    : root.height / 2 + root.tailW * 0.66
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        z: -1
        onClicked: mouse => {
            const p = mapToItem(bubbleLabel, mouse.x, mouse.y)
            const link = bubbleLabel.linkAt(p.x, p.y)
            if (link) {
                Qt.openUrlExternally(link)
                return
            }
            root.dismissed()
        }
    }
}
