pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "WorkspaceOrder.js" as Order

Singleton {
    readonly property var items: Order.ordered(Hyprland.workspaces.values)
    readonly property var focused: Hyprland.focusedWorkspace
    function monitorFor(screen: var): var {
        return screen ? Hyprland.monitorFor(screen) : null;
    }
    function onScreen(screen: var): var {
        const monitor = monitorFor(screen);
        return items.filter(workspace => !monitor || workspace.monitor?.id === monitor.id);
    }
    function titleFor(screen: var): string {
        const workspace = monitorFor(screen)?.activeWorkspace;
        if (workspace?.focused)
            return describe(Hyprland.activeToplevel);
        const window = workspace?.toplevels.values.find(item => item.lastIpcObject.address === workspace.lastIpcObject.lastwindow);
        return describe(window);
    }
    function describe(window: var): string {
        if (!window)
            return "";
        const app = window.lastIpcObject.class || "";
        const names = {
            "com.mitchellh.ghostty": "Ghostty",
            "firefox": "Firefox",
            "slack": "Slack",
            "1password": "1Password"
        };
        const label = names[app] || app.replace(/^org\.gnome\./, "");
        return (label ? label + " - " : "") + window.title;
    }

    function focus(id: int): void {
        // Hyprland 0.56 uses Lua dispatch expressions, not legacy workspace syntax.
        Hyprland.dispatch(Order.focusRequest(id));
    }
}
