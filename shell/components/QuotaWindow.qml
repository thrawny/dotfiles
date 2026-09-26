import QtQuick
import QtQuick.Layouts
import "../services"

ColumnLayout {
    id: root
    required property var quota
    property string fontFamily: "Sans Serif"
    spacing: 4
    Layout.topMargin: 4
    Layout.bottomMargin: 4

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 10
        radius: 5
        color: Theme.quotaSurface
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.quota.used_percent / 100))
            height: parent.height
            radius: 5
            visible: !root.quota.expired
            color: root.quota.severity === "critical" ? Theme.quotaAccent : root.quota.severity === "warning" ? Theme.quotaWarning : Theme.quotaSuccess
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            Layout.fillWidth: true
            text: root.quota.title
            color: Theme.quotaMuted
            font.family: root.fontFamily
            font.pixelSize: 12
            textFormat: Text.PlainText
        }
        Text {
            text: root.quota.expired ? "unknown" : Math.round(root.quota.used_percent) + "% used"
            color: root.quota.expired ? Theme.quotaMuted : Theme.quotaText
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.italic: root.quota.expired
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: text !== ""
        text: root.quota.expired ? "Window lapsed · refresh pending" : root.quota.reset_description ? "Resets " + root.quota.reset_description : root.quota.reset_text || ""
        color: Theme.quotaMuted
        font.family: root.fontFamily
        font.pixelSize: 11
        textFormat: Text.PlainText
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: !!root.quota.pace_text
        text: root.quota.pace_text || ""
        color: text.includes("in deficit") ? Theme.quotaAccent : text.includes("in reserve") ? Theme.quotaSuccess : Theme.quotaMuted
        font.family: root.fontFamily
        font.pixelSize: 11
        textFormat: Text.PlainText
    }
}
