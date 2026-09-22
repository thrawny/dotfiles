import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import "../../components"
import "../../services"
import "../../services/BatteryIcon.js" as BatteryIcon

// Quickshell chooses the platform implementation at runtime.
// qmllint disable uncreatable-type
PanelWindow {
    id: panel
    required property var modelData
    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight
    color: Theme.background
    visible: Theme.ready
    WlrLayershell.namespace: "dotfiles-shell"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: Theme.border
        opacity: 0.3
    }
    WorkspaceList {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            leftMargin: 8
        }
        width: Math.max(0, (windowTitle.visible ? windowTitle.x : statusItems.x) - 16)
    }
    Text {
        id: windowTitle
        anchors.centerIn: parent
        // Reserve equal space on both sides so the title stays screen-centered.
        width: Math.max(0, Math.min(panel.width * 0.3, panel.width - 2 * (statusItems.width + 16)))
        visible: width >= 60
        horizontalAlignment: Text.AlignHCenter
        text: Workspaces.windowTitle
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
    RowLayout {
        id: statusItems
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            rightMargin: 8
        }
        spacing: 6
        Tray {
            panel: panel
        }
        BarButton {
            text: "󰖩 " + (panel.width > 1200 ? Network.name : "")
            hint: Network.name + " · Open network settings"
            attention: !Network.connected
            maxTextWidth: 120
            onClicked: Quickshell.execDetached(["nm-connection-editor"])
        }
        BarButton {
            text: !Audio.available ? "󰖁 —" : Audio.muted ? "󰖁 muted" : "󰕾 " + Audio.percent + "%"
            hint: Audio.description + " · Click to mute, scroll for volume"
            enabled: Audio.available
            onClicked: Audio.toggleMute()
            onScrolled: delta => Audio.adjust(delta * 0.05)
        }
        BarButton {
            readonly property var battery: UPower.displayDevice
            visible: battery.isPresent
            text: BatteryIcon.icon(battery.percentage) + (UPower.onBattery ? " " : " 󱐋 ") + Math.round(battery.percentage * 100) + "%"
            hint: UPower.onBattery ? "On battery" : "Connected to power"
            attention: UPower.onBattery && battery.percentage < 0.2
            onClicked: Quickshell.execDetached(["ghostty", "-e", "btop"])
        }
        BarButton {
            text: Qt.formatDateTime(clock.date, panel.width > 1000 ? "ddd d MMM  HH:mm" : "HH:mm")
            hint: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
            onClicked: Quickshell.execDetached(["hyprlock"])
        }
    }
}
