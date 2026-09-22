pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import "../services"

Menu {
    id: root
    required property QsMenuHandle handle
    // Render QML in a separate window, never a native platform menu.
    popupType: Popup.Window
    margins: 6
    padding: 5
    implicitWidth: Math.min(480, Math.max(240, contentItem.implicitWidth + leftPadding + rightPadding))
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    overlap: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
        color: Theme.surface
        border.color: Theme.border
        radius: 5
    }

    QsMenuOpener {
        id: opener
        menu: root.visible ? root.handle : null
    }
    Instantiator {
        model: opener.children
        delegate: Loader {
            id: entry
            required property QsMenuEntry modelData
            sourceComponent: modelData?.hasChildren ? null : action
            Component.onCompleted: {
                if (modelData?.hasChildren)
                    setSource("TrayMenu.qml", {
                        handle: modelData,
                        title: Qt.binding(() => entry.modelData?.text ?? ""),
                        enabled: Qt.binding(() => entry.modelData?.enabled ?? false)
                    });
            }
            Component {
                id: action
                MenuItem {
                    id: actionRow
                    property QsMenuEntry menuEntry: entry.modelData
                    text: menuEntry?.text ?? ""
                    enabled: (menuEntry?.enabled ?? false) && !menuEntry.isSeparator
                    implicitHeight: menuEntry?.isSeparator ? 9 : 30
                    onTriggered: menuEntry?.triggered()
                    contentItem: Text {
                        text: actionRow.text.replace(/&&/g, "\u0000").replace(/&/g, "").replace(/\u0000/g, "&")
                        visible: !(entry.modelData?.isSeparator ?? true)
                        color: actionRow.enabled ? Theme.foreground : Theme.muted
                        font: root.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        leftPadding: 24
                        rightPadding: 12
                    }
                    indicator: Text {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData?.checkState === Qt.Checked ? "✓" : entry.modelData?.checkState === Qt.PartiallyChecked ? "−" : ""
                        color: Theme.accent
                        font: root.font
                    }
                    background: Rectangle {
                        color: actionRow.highlighted ? Theme.background : "transparent"
                        radius: 3
                        Rectangle {
                            visible: entry.modelData?.isSeparator ?? false
                            anchors.centerIn: parent
                            width: parent.width - 16
                            height: 1
                            color: Theme.border
                        }
                    }
                }
            }
        }
        onObjectAdded: (index, object) => {
            const loaded = (object as Loader).item;
            if (loaded instanceof Menu)
                root.insertMenu(index, loaded);
            else
                root.insertItem(index, loaded);
        }
        onObjectRemoved: (index, object) => {
            const loaded = (object as Loader).item;
            if (loaded instanceof Menu)
                root.removeMenu(loaded);
            else
                root.removeItem(loaded);
        }
    }
    // Qt creates submenu rows through the parent's delegate.
    delegate: MenuItem {
        id: submenuRow
        implicitHeight: 30
        contentItem: Text {
            text: submenuRow.text.replace(/&/g, "")
            color: submenuRow.enabled ? Theme.foreground : Theme.muted
            font: root.font
            verticalAlignment: Text.AlignVCenter
            leftPadding: 24
            rightPadding: 24
            elide: Text.ElideRight
        }
        arrow: Text {
            x: submenuRow.width - width - 10
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: Theme.muted
            font: root.font
        }
        background: Rectangle {
            color: submenuRow.highlighted ? Theme.background : "transparent"
            radius: 3
        }
    }
}
