pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"

Popup {
    id: root
    required property string providerId
    readonly property var provider: Quota.provider(providerId)
    popupType: Popup.Window
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    focus: true
    padding: 16
    margins: 8
    width: 440
    height: Math.min(content.implicitHeight + 32, 680)
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    function date(value: string): string {
        return value ? Qt.formatDateTime(new Date(value), "ddd d MMM HH:mm") : "Unknown";
    }
    background: Rectangle {
        color: Theme.background
        border.color: Theme.border
        radius: 5
    }
    contentItem: Flickable {
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        ColumnLayout {
            id: content
            width: parent.width
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: ["claude", "codex"]
                    delegate: BarButton {
                        required property string modelData
                        text: modelData === "claude" ? "Claude" : "Codex"
                        selected: root.providerId === modelData
                        onClicked: root.providerId = modelData
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                BarButton {
                    text: "×"
                    hint: "Close quota details"
                    onClicked: root.close()
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !!Quota.error || !!root.provider?.error || !!root.provider?.stale || !root.provider?.available
                text: Quota.error || root.provider?.error || (root.provider?.stale ? "Stale data · waiting for a successful refresh" : "No quota data available")
                color: Theme.warning
                font: root.font
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: [root.provider?.identity?.plan, root.provider?.identity?.email, root.provider?.identity?.organization].filter(Boolean).join(" · ")
                color: Theme.muted
                font: root.font
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Repeater {
                model: root.provider?.windows || []
                delegate: ColumnLayout {
                    id: quotaWindow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: quotaWindow.modelData.title
                            color: Theme.foreground
                            font: root.font
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                        Text {
                            text: quotaWindow.modelData.expired ? "Unknown" : Math.round(quotaWindow.modelData.used_percent) + "% used"
                            color: quotaWindow.modelData.expired ? Theme.muted : Theme.foreground
                            font: root.font
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 5
                        color: Theme.surface
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, quotaWindow.modelData.used_percent / 100))
                            height: parent.height
                            visible: !quotaWindow.modelData.expired
                            color: ["critical", "warning"].includes(quotaWindow.modelData.severity) ? Theme.warning : Theme.accent
                        }
                        Rectangle {
                            visible: quotaWindow.modelData.expected_used_percent !== null && !quotaWindow.modelData.expired
                            x: parent.width * (quotaWindow.modelData.expected_used_percent || 0) / 100
                            width: 1
                            height: parent.height + 4
                            y: -2
                            color: Theme.foreground
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: quotaWindow.modelData.reset_text + (quotaWindow.modelData.resets_at && !quotaWindow.modelData.expired ? " · " + root.date(quotaWindow.modelData.resets_at) : "")
                        color: Theme.muted
                        font: root.font
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!quotaWindow.modelData.pace_text
                        text: quotaWindow.modelData.pace_text || ""
                        color: Theme.muted
                        font: root.font
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !!root.provider?.cost
                text: {
                    const cost = root.provider?.cost;
                    return cost ? "Spend: " + cost.used.toFixed(2) + " / " + cost.limit.toFixed(2) + " " + cost.currency_code + (cost.period ? " · " + cost.period : "") + (cost.resets_at ? "\nResets " + root.date(cost.resets_at) : "") : "";
                }
                color: Theme.foreground
                font: root.font
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Text {
                visible: !!root.provider?.reset_credits
                text: "Limit reset credits · " + (root.provider?.reset_credits?.available_count || 0) + " available"
                color: Theme.foreground
                font: root.font
            }
            Repeater {
                model: root.provider?.reset_credits?.credits || []
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: (modelData.title || modelData.reset_type) + " · " + (modelData.available ? "available" : modelData.status === "available" ? "expired" : modelData.status) + (modelData.expires_at ? "\nExpires " + root.date(modelData.expires_at) : "") + (modelData.description ? "\n" + modelData.description : "") + (modelData.redeemed_at ? "\nRedeemed " + root.date(modelData.redeemed_at) : "")
                    color: modelData.available ? Theme.foreground : Theme.muted
                    font: root.font
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }
            Text {
                Layout.fillWidth: true
                text: "Updated " + root.date(root.provider?.updated_at || "")
                color: Theme.muted
                font: root.font
            }
            RowLayout {
                Layout.fillWidth: true
                BarButton {
                    text: Quota.busy ? "Refreshing…" : "Refresh"
                    enabled: !Quota.busy
                    onClicked: Quota.refresh()
                }
                Item {
                    Layout.fillWidth: true
                }
                BarButton {
                    text: "Open usage"
                    enabled: !!root.provider?.usage_url
                    onClicked: {
                        root.close();
                        Qt.callLater(() => Quota.openUsage(root.providerId));
                    }
                }
            }
        }
    }
}
