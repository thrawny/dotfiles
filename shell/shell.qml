import Quickshell
import Quickshell.Io
import "modules/bar"
import "services"

ShellRoot {
    Variants {
        model: Quickshell.screens
        Bar {}
    }
    IpcHandler {
        target: "shell"
        function ping(): string {
            return Theme.ready ? "ready" : "theme-unavailable";
        }
        function focusWorkspace(position: int): void {
            const workspace = Workspaces.items[position - 1];
            if (workspace)
                Workspaces.focus(workspace.id);
        }
        function workspaces(): string {
            return JSON.stringify(Workspaces.items.map((ws, index) => ({
                        position: index + 1,
                        id: ws.id,
                        name: ws.name
                    })));
        }
    }
}
