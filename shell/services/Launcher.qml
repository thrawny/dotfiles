pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Search.js" as Search

Singleton {
    id: root
    property bool opened: false
    property string mode: "apps"
    property string query: ""
    property string appError: ""
    readonly property string error: mode === "clipboard" ? Clipboard.error : appError
    readonly property bool busy: mode === "clipboard" && Clipboard.busy
    property var screen: null
    readonly property bool pickingMode: query.startsWith("?")
    readonly property var results: pickingMode ? Search.modes(query.slice(1)) : mode === "apps" ? Search.apps(DesktopEntries.applications.values, query) : Search.clipboard(Clipboard.entries, query)

    onOpenedChanged: Clipboard.active = opened && mode === "clipboard"
    onModeChanged: Clipboard.active = opened && mode === "clipboard"
    Connections {
        target: Clipboard
        function onCopied() {
            root.close();
        }
    }

    function toggle(): void {
        if (opened) {
            close();
            return;
        }
        screen = Quickshell.screens.find(item => item.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0];
        mode = "apps";
        query = "";
        appError = "";
        opened = true;
    }
    function close(): void {
        opened = false;
        query = "";
        appError = "";
    }
    function setMode(next: string): void {
        mode = next;
        query = "";
        appError = "";
    }
    function cycleMode(): void {
        setMode(mode === "apps" ? "clipboard" : "apps");
    }
    function activate(index: int): void {
        const item = results[index];
        if (!item)
            return;
        if (item.kind === "mode") {
            setMode(item.mode);
        } else if (item.kind === "app") {
            const command = Search.appCommand(item.entry);
            if (!command.length) {
                appError = "This application has no launch command.";
                return;
            }
            Quickshell.execDetached({
                command: command,
                workingDirectory: item.entry.workingDirectory
            });
            close();
        } else if (item.kind === "clipboard") {
            Clipboard.copy(item.id);
        }
    }
    function remove(index: int): void {
        const item = results[index];
        if (item?.kind === "clipboard")
            Clipboard.remove(item.id);
    }
}
