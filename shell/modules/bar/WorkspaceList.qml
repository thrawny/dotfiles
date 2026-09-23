pragma ComponentBehavior: Bound
import QtQuick
import "../../components"
import "../../services"
import "../../services/WorkspaceOrder.js" as Order

Flickable {
    id: root
    required property var screen
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
            model: Workspaces.onScreen(root.screen)
            BarButton {
                required property var modelData
                required property int index
                readonly property string key: Order.shortcut(Workspaces.items.findIndex(workspace => workspace.id === modelData.id))
                text: (key ? key + "  " : "") + modelData.name
                hint: modelData.name + (key ? " · Alt+" + key : "")
                selected: modelData.active
                onSelectedChanged: Qt.callLater(root.revealFocused)
                attention: modelData.urgent ?? false
                maxTextWidth: 160
                onClicked: Workspaces.focus(modelData.id)
            }
        }
    }
}
