pragma ComponentBehavior: Bound
import QtQuick
import "../../components"
import Quickshell.Services.SystemTray
import "../../services"

Row {
    id: root
    required property var panel
    spacing: 2
    Repeater {
        model: SystemTray.items
        Item {
            id: entry
            required property SystemTrayItem modelData
            width: modelData.status === Status.Passive ? 0 : 24
            height: Theme.barHeight
            visible: width > 0
            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: entry.modelData.icon
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(24, 24)
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: event => {
                    if (event.button === Qt.RightButton || entry.modelData.onlyMenu) {
                        if (entry.modelData.hasMenu) {
                            const point = entry.mapToItem(root.panel.contentItem, 0, entry.height);
                            entry.modelData.display(root.panel, point.x, point.y);
                        }
                    } else if (event.button === Qt.MiddleButton) {
                        entry.modelData.secondaryActivate();
                    } else {
                        entry.modelData.activate();
                    }
                }
                onWheel: event => entry.modelData.scroll(event.angleDelta.y, false)
            }
            BarTooltip {
                targetItem: entry
                hovered: mouse.containsMouse
                text: entry.modelData.tooltipTitle || entry.modelData.title || entry.modelData.id
            }
        }
    }
}
