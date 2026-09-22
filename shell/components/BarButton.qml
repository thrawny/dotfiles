import QtQuick
import QtQuick.Controls
import "../services"

Button {
    id: root
    property bool selected: false
    property bool attention: false
    property string hint: ""
    property real maxTextWidth: 180
    signal scrolled(real delta)

    implicitHeight: Theme.barHeight
    implicitWidth: Math.min(label.implicitWidth, maxTextWidth) + 16
    padding: 8
    hoverEnabled: true
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    Accessible.name: hint || text
    BarTooltip {
        targetItem: root
        hovered: root.hovered
        text: root.hint
    }

    contentItem: Text {
        id: label
        text: root.text
        textFormat: Text.PlainText
        font: root.font
        color: root.attention ? Theme.warning : root.selected ? Theme.accent : Theme.foreground
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        color: root.hovered || root.down ? Theme.surface : "transparent"
        Rectangle {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: 2
            color: Theme.accent
            visible: root.selected
        }
    }
    WheelHandler {
        onWheel: event => {
            root.scrolled(event.angleDelta.y / 120);
            event.accepted = true;
        }
    }
}
