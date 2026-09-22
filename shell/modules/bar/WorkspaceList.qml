import QtQuick
import "../../components"
import "../../services"
import "../../services/WorkspaceOrder.js" as Order

Flickable {
    id: root
    contentWidth: row.width
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.HorizontalFlick

    function revealFocused(): void {
        for (let i = 0; i < buttons.count; i++) {
            const button = buttons.itemAt(i) as BarButton;
            if (button && button.selected) {
                const desired = Math.max(button.x + button.width - width, Math.min(contentX, button.x));
                contentX = Math.max(0, Math.min(Math.max(0, contentWidth - width), desired));
                break;
            }
        }
    }
    onWidthChanged: Qt.callLater(revealFocused)
    onContentWidthChanged: Qt.callLater(revealFocused)
    Connections {
        target: Workspaces
        function onFocusedChanged() {
            Qt.callLater(root.revealFocused);
        }
    }
    Row {
        id: row
        Repeater {
            id: buttons
            model: Workspaces.items
            BarButton {
                required property var modelData
                required property int index
                readonly property string key: Order.shortcut(index)
                text: (key ? key + "  " : "") + modelData.name
                hint: modelData.name + (key ? " · Alt+" + key : "")
                selected: Workspaces.focused?.id === modelData.id
                attention: modelData.urgent ?? false
                maxTextWidth: 160
                onClicked: Workspaces.focus(modelData.id)
            }
        }
    }
}
