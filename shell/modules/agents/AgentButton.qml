pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../../services"

Button {
    id: control
    leftPadding: 8
    rightPadding: 8
    topPadding: 6
    bottomPadding: 6
    contentItem: Text {
        text: control.text
        textFormat: Text.PlainText
        color: !control.enabled ? Theme.muted : control.hovered ? Theme.accent : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
    background: Rectangle {
        color: control.down ? Theme.border : Theme.surface
        radius: 4
    }
}
