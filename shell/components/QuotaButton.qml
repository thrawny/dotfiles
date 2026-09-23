import QtQuick
import "../services"

BarButton {
    id: root
    required property string providerId
    property bool compact: false
    readonly property var provider: Quota.provider(providerId)
    readonly property string label: provider?.name || (providerId === "claude" ? "Claude" : "Codex")
    text: (compact ? (providerId === "claude" ? "C " : "O ") : label + " ") + (provider ? (compact ? provider.compact_summary : provider.summary) : "—") + ((provider?.stale || Quota.error) ? " !" : "")
    attention: !provider?.available || provider?.stale || !!Quota.error || provider?.severity === "warning" || provider?.severity === "critical"
    selected: details.visible
    maxTextWidth: compact ? 80 : 190
    hint: label + " · " + (Quota.error || provider?.error || (!provider?.available ? "No data available" : provider?.stale ? "Stale quota data" : provider.summary)) + "\nClick for quota details"
    onClicked: {
        if (details.visible)
            details.close();
        else {
            details.providerId = root.providerId;
            details.open();
            Quota.refresh();
        }
    }
    QuotaDetails {
        id: details
        providerId: root.providerId
        x: root.width - width
        y: root.height + 6
    }
}
