import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// Renders an open-mascot scene (560x560 viewbox) scaled to fit this item.
Item {
    id: root

    property var scene: null
    property bool shadowVisible: true
    property string backgroundColor: "transparent"

    // Region of the engine's 560x560 viewbox that this item shows; the shell
    // computes it to hug the blob so the window has no dead margins.
    property real contentL: 0
    property real contentT: 0
    property real contentW: 560
    property real contentH: 560
    readonly property real contentScale: width / contentW

    Rectangle {
        anchors.fill: parent
        visible: root.backgroundColor !== "transparent" && root.backgroundColor !== ""
        color: root.backgroundColor === "stage" && root.scene ? root.scene.background : root.backgroundColor
        radius: Math.min(width, height) * 0.08
    }

    Item {
        width: 560
        height: 560
        scale: root.contentScale
        transformOrigin: Item.TopLeft
        x: -root.contentL * root.contentScale
        y: -root.contentT * root.contentScale

        // Soft ground shadow. The scene describes an ellipse blurred by 13px;
        // a blurred capsule is visually identical and cheaper to build.
        Rectangle {
            visible: root.shadowVisible && root.scene !== null
            x: root.scene ? root.scene.shadow.cx - root.scene.shadow.rx : 0
            y: root.scene ? root.scene.shadow.cy - root.scene.shadow.ry : 0
            width: root.scene ? root.scene.shadow.rx * 2 : 0
            height: root.scene ? root.scene.shadow.ry * 2 : 0
            radius: height / 2
            color: root.scene ? root.scene.shadow.fill : "black"
            opacity: root.scene ? root.scene.shadow.opacity : 0
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.9
                blurMax: 26
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: root.scene ? root.scene.blob.fill : "transparent"
                PathSvg { path: root.scene ? root.scene.blob.path : "" }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: root.scene ? root.scene.eyes[0].fill : "transparent"
                PathSvg { path: root.scene ? root.scene.eyes[0].path : "" }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: root.scene ? root.scene.eyes[1].fill : "transparent"
                PathSvg { path: root.scene ? root.scene.eyes[1].path : "" }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: root.scene && root.scene.mouth ? root.scene.mouth.fill : "transparent"
                PathSvg { path: root.scene && root.scene.mouth ? root.scene.mouth.path : "" }
            }
        }
    }
}
