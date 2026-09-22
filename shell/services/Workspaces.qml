pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "WorkspaceOrder.js" as Order

Singleton {
    readonly property var items: Order.ordered(Hyprland.workspaces.values)
    readonly property var focused: Hyprland.focusedWorkspace
    readonly property string windowTitle: Hyprland.activeToplevel?.title ?? ""

    function focus(id: int): void {
        // Hyprland 0.56 uses Lua dispatch expressions, not legacy workspace syntax.
        Hyprland.dispatch(Order.focusRequest(id));
    }
}
