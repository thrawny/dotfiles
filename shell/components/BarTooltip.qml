import QtQuick
import Quickshell
import "../services"

Item {
    id: root
    required property Item targetItem
    property string text: ""
    property bool hovered: false
    property bool armed: false

    onHoveredChanged: {
        if (!hovered)
            armed = false;
    }
    Timer {
        interval: 600
        running: root.hovered && root.text !== "" && !root.armed
        onTriggered: root.armed = true
    }
    PopupWindow {
        id: popup
        anchor.item: root.targetItem
        anchor.rect.y: root.targetItem.height + 6
        // Quickshell's qmltypes omit the Edges::Flags property type.
        // qmllint disable missing-type
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        // qmllint enable missing-type
        visible: root.hovered && root.armed && root.text !== "" && Theme.ready
        // Window sizes use whole pixels; never round below the text's width.
        implicitWidth: Math.min(Math.ceil(label.implicitWidth) + 24, 420)
        implicitHeight: Math.ceil(label.implicitHeight) + 16
        color: "transparent"
        // Do not intercept input or steal hover from the bar below the popup.
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.color: Theme.border
            radius: 5
            Text {
                id: label
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                text: root.text
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
