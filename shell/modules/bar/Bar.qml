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
    id: barWindow
    required property var modelData
    // Quickshell._Window exposes QuickshellScreenInfo as opaque in its qmltypes.
    // qmllint disable missing-property
    readonly property bool compact: screen.name.startsWith("eDP") || width <= 1200
    // qmllint enable missing-property
    property bool alternateClock: false
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
        screen: barWindow.screen
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
        width: Math.max(0, Math.min(barWindow.width * 0.3, barWindow.width - 2 * (statusItems.width + 16)))
        visible: !barWindow.compact && width >= 60
        horizontalAlignment: Text.AlignHCenter
        text: Workspaces.titleFor(barWindow.screen)
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
        spacing: barWindow.compact ? 0 : 6
        BarButton {
            text: Agents.indicator
            hint: Agents.tooltip
            selected: Agents.opened
            attention: Agents.stale || (Agents.counts.done ?? 0) > 0
            onClicked: Agents.toggle(barWindow.screen)
        }
        QuotaButton {
            providerId: "claude"
            compact: barWindow.compact
        }
        QuotaButton {
            providerId: "codex"
            compact: barWindow.compact
        }
        BarButton {
            text: Keyboard.label
            hint: Keyboard.error || Keyboard.name + " · Click to switch layout"
            attention: Keyboard.error !== ""
            enabled: !Keyboard.busy
            onClicked: Keyboard.next()
        }
        Tray {
            panel: barWindow
            compact: barWindow.compact
        }
        BarButton {
            text: Network.icon + (!barWindow.compact ? " " + Network.name : "")
            hint: Network.details + "\nClick to open network settings"
            attention: !Network.connected
            maxTextWidth: 120
            onClicked: Quickshell.execDetached(["nm-connection-editor"])
        }
        BarButton {
            text: !Audio.available ? "󰖁 ?" : Audio.muted ? "󰝟" : (Audio.percent < 34 ? "󰕿" : Audio.percent < 67 ? "󰖀" : "󰕾") + (barWindow.compact ? "" : " " + Audio.percent + "%")
            hint: Audio.description + " · " + Audio.percent + "%" + (Audio.muted ? " · Muted" : "") + "\nClick for audio settings, right-click to mute, scroll for volume"
            onClicked: Quickshell.execDetached(["pavucontrol"])
            onSecondaryClicked: Audio.toggleMute()
            onScrolled: delta => Audio.adjust(delta * 0.05)
        }
        CaffeineButton {}
        BarButton {
            readonly property var battery: UPower.displayDevice
            visible: battery.isPresent
            text: BatteryIcon.icon(battery.percentage) + (UPower.onBattery ? " " : " 󱐋 ") + Math.round(battery.percentage * 100) + "%"
            hint: {
                const charging = battery.state === UPowerDeviceState.Charging;
                const discharging = battery.state === UPowerDeviceState.Discharging;
                const seconds = charging ? battery.timeToFull : battery.timeToEmpty;
                const remaining = seconds > 0 && (charging || discharging) ? "\n" + Math.floor(seconds / 3600) + "h " + Math.floor(seconds % 3600 / 60) + "m " + (charging ? "until full" : "remaining") : "";
                return (charging ? "Charging" : discharging ? "On battery" : "AC connected") + " · " + Math.round(battery.percentage * 100) + "%" + (charging || discharging ? "\n" + Math.abs(battery.changeRate).toFixed(1) + " W " + (charging ? "↑" : "↓") : "") + remaining;
            }
            attention: UPower.onBattery && battery.percentage < 0.2
            onClicked: Quickshell.execDetached(["ghostty", "-e", "btop"])
        }
        BarButton {
            text: Qt.formatDateTime(clock.date, barWindow.alternateClock ? "dddd" : barWindow.compact ? "MM-dd HH:mm" : "yyyy-MM-dd HH:mm")
            hint: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy") + "\nClick to change display, right-click to lock"
            onClicked: barWindow.alternateClock = !barWindow.alternateClock
            onSecondaryClicked: Quickshell.execDetached(["hyprlock"])
        }
    }
}
