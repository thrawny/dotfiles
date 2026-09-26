pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"

Rectangle {
    id: root
    required property string providerId
    objectName: "quota-card-" + providerId
    property bool selected: false
    property string fontFamily: "Sans Serif"
    readonly property var provider: Quota.provider(providerId)
    readonly property var availableCredits: (provider?.reset_credits?.credits || []).filter(credit => credit.available).sort((a, b) => {
        if (!a.expires_at)
            return b.expires_at ? 1 : 0;
        if (!b.expires_at)
            return -1;
        return Date.parse(a.expires_at) - Date.parse(b.expires_at);
    })
    signal activated
    signal usageRequested
    implicitWidth: Math.max(264, heading.implicitWidth, quotaRows.implicitWidth) + 24
    implicitHeight: content.implicitHeight + 24
    color: selected ? Theme.quotaCardSelected : hover.hovered ? Theme.quotaCardHover : Theme.quotaCard
    radius: 8
    opacity: provider?.available ? 1 : 0.7

    function creditExpiry(value: string): string {
        if (!value)
            return "No expiry";
        const reference = Quota.generatedAt ? Date.parse(Quota.generatedAt) : Date.now();
        const minutes = Math.floor((Date.parse(value) - reference) / 60000);
        if (minutes <= 0)
            return "now";
        if (minutes < 60)
            return minutes + " min";
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return hours + "h" + (minutes % 60 ? " " + (minutes % 60) + "m" : "");
        const days = Math.floor(hours / 24);
        return days + (days === 1 ? " day" : " days");
    }
    readonly property string creditExpiries: {
        const parts = availableCredits.slice(0, 4).map(credit => creditExpiry(credit.expires_at || ""));
        if (availableCredits.length > 4)
            parts.push("+" + (availableCredits.length - 4));
        return "󰥔 " + parts.join(" · ");
    }

    HoverHandler {
        id: hover
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
    Rectangle {
        visible: root.selected
        width: 3
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        radius: 1.5
        color: Theme.quotaAccent
    }
    ColumnLayout {
        id: content
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 8
        RowLayout {
            id: heading
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 8
            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                ProviderIcon {
                    anchors.centerIn: parent
                    objectName: "quota-logo-" + root.providerId
                    providerId: root.providerId
                    color: root.providerId === "claude" ? Theme.claudeIcon : Theme.quotaText
                    iconSize: 16
                }
            }
            Text {
                text: root.provider?.name || (root.providerId === "claude" ? "Claude" : "Codex")
                color: Theme.quotaText
                font.family: root.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Item {
                Layout.fillWidth: true
            }
            RowLayout {
                spacing: 6
                Button {
                    id: usage
                    visible: !!root.provider?.available && !!root.provider?.usage_url
                    text: "Usage"
                    leftPadding: 6
                    rightPadding: 6
                    topPadding: 2
                    bottomPadding: 2
                    onClicked: root.usageRequested()
                    contentItem: Text {
                        text: usage.text
                        color: Theme.quotaText
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.underline: true
                    }
                    background: Rectangle {
                        radius: 4
                        color: usage.hovered ? Theme.quotaElevated : Theme.quotaSubtle
                        border.color: usage.activeFocus ? Theme.quotaAccent : "transparent"
                    }
                }
                Rectangle {
                    visible: !!root.provider?.identity?.plan
                    implicitWidth: plan.implicitWidth + 16
                    implicitHeight: plan.implicitHeight + 4
                    radius: 4
                    color: Theme.quotaElevated
                    Text {
                        id: plan
                        anchors.centerIn: parent
                        text: root.provider?.identity?.plan || ""
                        color: Theme.quotaSuccess
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        textFormat: Text.PlainText
                    }
                }
            }
        }
        ColumnLayout {
            id: quotaRows
            Layout.fillWidth: true
            spacing: 8
            visible: (root.provider?.windows || []).length > 0
            Repeater {
                model: root.provider?.windows || []
                delegate: QuotaWindow {
                    required property var modelData
                    Layout.fillWidth: true
                    quota: modelData
                    fontFamily: root.fontFamily
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: !!root.provider?.cost
            implicitHeight: costText.implicitHeight + 16
            radius: 6
            color: Theme.quotaSurface
            Text {
                id: costText
                anchors.fill: parent
                anchors.margins: 8
                text: {
                    const cost = root.provider?.cost;
                    return cost ? "$" + cost.used.toFixed(2) + " / $" + cost.limit.toFixed(2) + (cost.period ? " " + cost.period : "") : "";
                }
                color: Theme.quotaText
                font.family: root.fontFamily
                font.pixelSize: 12
                textFormat: Text.PlainText
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: root.availableCredits.length > 0
            implicitHeight: creditContent.implicitHeight + 16
            radius: 6
            color: Theme.quotaSurface
            ColumnLayout {
                id: creditContent
                x: 8
                y: 8
                width: parent.width - 16
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Limit Reset Credits"
                        color: Theme.quotaText
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: root.availableCredits.length + " available"
                        color: Theme.quotaMuted
                        font.family: root.fontFamily
                        font.pixelSize: 12
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.creditExpiries
                    horizontalAlignment: Text.AlignRight
                    color: Theme.quotaMuted
                    font.family: root.fontFamily
                    font.pixelSize: 11
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: Quota.error || root.provider?.error || (!root.provider?.available ? "No quota data available" : root.provider?.stale ? "Stale data · refresh pending" : "")
            color: Theme.quotaAccent
            font.family: root.fontFamily
            font.pixelSize: 11
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }
}
