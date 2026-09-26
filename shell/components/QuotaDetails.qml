pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"

Popup {
    id: root
    required property string providerId
    property string selectedProvider: providerId
    popupType: Popup.Window
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    focus: true
    padding: 16
    margins: 8
    width: Math.max(320, providerCards.implicitWidth + 32)
    height: Math.min(content.implicitHeight + 32, 900)
    font.family: "Sans Serif"
    font.pixelSize: 12
    onOpened: {
        selectedProvider = providerId;
        viewport.forceActiveFocus();
    }
    readonly property string lastUpdate: {
        const times = Quota.providers.map(provider => Date.parse(provider.updated_at || "")).filter(Number.isFinite);
        return times.length ? Qt.formatDateTime(new Date(Math.max(...times)), "HH:mm") : "Unknown";
    }

    background: Rectangle {
        color: Theme.quotaBackground
        border.color: root.activeFocus ? Theme.quotaAccent : Theme.quotaBorder
        radius: 12
    }
    contentItem: Flickable {
        id: viewport
        contentHeight: content.implicitHeight
        clip: true
        focus: true
        boundsBehavior: Flickable.StopAtBounds
        Keys.onReturnPressed: root.close()
        Keys.onEnterPressed: root.close()
        ScrollBar.vertical: ScrollBar {}
        ColumnLayout {
            id: content
            width: parent.width
            spacing: 0
            ColumnLayout {
                id: providerCards
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: ["claude", "codex"]
                    delegate: QuotaProviderCard {
                        required property string modelData
                        Layout.fillWidth: true
                        providerId: modelData
                        selected: root.selectedProvider === modelData
                        fontFamily: root.font.family
                        onActivated: {
                            if (root.selectedProvider === modelData)
                                root.close();
                            else
                                root.selectedProvider = modelData;
                        }
                        onUsageRequested: {
                            const provider = modelData;
                            root.close();
                            Qt.callLater(() => Quota.openUsage(provider));
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 16
                text: "Updated at " + root.lastUpdate
                color: Theme.quotaMuted
                font.family: root.font.family
                font.pixelSize: 11
            }
        }
    }
}
