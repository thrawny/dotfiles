pragma ComponentBehavior: Bound
import QtQuick
import "../../components"
import Quickshell.Services.SystemTray
import "../../services"

Row {
    id: root
    required property var panel
    property bool compact: false
    property bool expanded: false
    spacing: 2
    BarButton {
        visible: root.compact
        text: root.expanded ? "‹" : "⋯"
        hint: root.expanded ? "Hide tray icons" : "Show tray icons"
        onClicked: root.expanded = !root.expanded
    }
    Repeater {
        model: SystemTray.items
        Item {
            id: entry
            required property SystemTrayItem modelData
            property real wheelX: 0
            property real wheelY: 0
            width: (root.compact && (!root.expanded || modelData.status === Status.Passive)) ? 0 : 24
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
                    if (event.button === Qt.RightButton || (event.button === Qt.LeftButton && entry.modelData.onlyMenu)) {
                        if (entry.modelData.hasMenu) {
                            menu.popup();
                        }
                    } else if (event.button === Qt.MiddleButton) {
                        entry.modelData.secondaryActivate();
                    } else {
                        entry.modelData.activate();
                    }
                }
                onWheel: event => {
                    entry.wheelX -= event.angleDelta.x / 120;
                    entry.wheelY -= event.angleDelta.y / 120;
                    const x = Math.trunc(entry.wheelX);
                    const y = Math.trunc(entry.wheelY);
                    if (x)
                        entry.modelData.scroll(x, true);
                    if (y)
                        entry.modelData.scroll(y, false);
                    entry.wheelX -= x;
                    entry.wheelY -= y;
                    event.accepted = true;
                }
            }
            TrayMenu {
                id: menu
                // Quickshell does not export DBusMenuHandle in its qmltypes.
                // qmllint disable unresolved-type
                handle: entry.modelData.menu
                // qmllint enable unresolved-type
                y: entry.height + 6
            }
            BarTooltip {
                targetItem: entry
                hovered: mouse.containsMouse && !menu.visible
                text: (entry.modelData.tooltipTitle || entry.modelData.title || entry.modelData.id) + (entry.modelData.tooltipDescription ? "\n" + entry.modelData.tooltipDescription : "")
            }
        }
    }
}
