import QtQuick
import QtQuick.Controls
import "../services"

Button {
    id: root
    required property string providerId
    property bool compact: false
    readonly property var provider: Quota.provider(providerId)
    readonly property string label: provider?.name || (providerId === "claude" ? "Claude" : "Codex")
    // Snapshot summaries use the same session / weekly preference and reset
    // rounding as the original Waybar output. Only trailing text is dimmed.
    readonly property var summaryParts: provider?.available && provider.summary !== "—" ? provider.summary.split(" ") : ["--"]
    readonly property color statusColor: provider?.severity === "critical" ? Theme.quotaAccent : provider?.severity === "warning" ? Theme.quotaWarning : Theme.codexIcon
    readonly property string hint: [label, Quota.error || provider?.error || (provider?.stale ? "Stale quota data" : !provider?.available ? "No data available" : ""), ...(provider?.windows || []).map(window => window.title + ": " + (window.expired ? "unknown" : Math.round(window.used_percent) + "%") + " · " + window.reset_text)].filter(Boolean).join("\n")
    implicitHeight: Theme.barHeight
    implicitWidth: content.implicitWidth + leftPadding + rightPadding
    leftPadding: compact ? 5 : 8
    rightPadding: compact ? 5 : 8
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    font.family: Theme.fontFamily
    font.pixelSize: compact ? 12 : 13
    font.bold: true
    Accessible.name: hint
    contentItem: Row {
        id: content
        spacing: root.compact ? 2 : 6
        ProviderIcon {
            providerId: root.providerId
            iconSize: root.compact ? 11 : 14
            color: root.providerId === "claude" ? Theme.claudeIcon : Theme.codexIcon
            anchors.verticalCenter: parent.verticalCenter
        }
        Row {
            spacing: lead.font.pixelSize * 0.6
            anchors.verticalCenter: parent.verticalCenter
            Text {
                id: lead
                text: root.summaryParts[0]
                font: root.font
                color: root.statusColor
                textFormat: Text.PlainText
            }
            Text {
                text: root.summaryParts.slice(1).join(" ")
                visible: text !== ""
                font: root.font
                color: root.statusColor
                opacity: 0.55
                textFormat: Text.PlainText
            }
        }
    }
    background: Item {}
    BarTooltip {
        targetItem: root
        hovered: root.hovered && !details.visible
        text: root.hint
    }
    onClicked: {
        if (details.visible)
            details.close();
        else {
            details.open();
            Quota.refresh();
        }
    }
    QuotaDetails {
        id: details
        providerId: root.providerId
        x: root.width - width
        y: root.height + 10
    }
}
