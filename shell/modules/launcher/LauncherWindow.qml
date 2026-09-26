import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// Quickshell selects its platform window implementation at runtime.
// qmllint disable uncreatable-type
PanelWindow {
    screen: Launcher.screen
    visible: Launcher.opened && Theme.ready
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "dotfiles-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: {
        if (visible)
            Qt.callLater(panel.focusSearch);
    }
    LauncherPanel {
        id: panel
        anchors.fill: parent
    }
}
