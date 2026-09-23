pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// qmllint disable uncreatable-type
PanelWindow {
    screen: Agents.screen
    visible: Agents.opened && Theme.ready
    anchors {
        top: true
        bottom: true
        left: true
    }
    implicitWidth: 470
    color: Theme.background
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dotfiles-agents"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    AgentsPanel {
        anchors.fill: parent
    }
}
