//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import "modules/bar"
import "modules/launcher"
import "services"

ShellRoot {
    LauncherWindow {}
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            Launcher.toggle();
        }
        function projects(): void {
            Launcher.toggleProjects();
        }
        function close(): void {
            Launcher.close();
        }
        // Inspect launcher state without exposing search queries.
        function state(): string {
            return JSON.stringify({
                opened: Launcher.opened,
                mode: Launcher.mode,
                pickingMode: Launcher.pickingMode,
                count: Launcher.results.length,
                busy: Launcher.busy,
                error: Launcher.error
            });
        }
    }
    Variants {
        model: Quickshell.screens
        Bar {}
    }
    IpcHandler {
        target: "shell"
        function ping(): string {
            return Theme.ready ? "ready" : "theme-unavailable";
        }
        function status(): string {
            return JSON.stringify({
                keyboard: Keyboard.label,
                keyboardError: Keyboard.error,
                networkConnected: Network.connected,
                networkFrequency: Network.frequency,
                networkThroughput: Network.throughput,
                audioAvailable: Audio.available,
                caffeineActive: Caffeine.active,
                quotaError: Quota.error,
                quotaProviders: Quota.providers.map(provider => ({
                            id: provider.id,
                            available: provider.available,
                            stale: provider.stale
                        }))
            });
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
