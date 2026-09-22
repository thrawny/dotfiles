pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Search.js" as Search

Singleton {
    id: root
    property bool opened: false
    property int generation: 0
    property string mode: "apps"
    property string query: ""
    property string error: ""
    property var screen: null
    property var clipboardEntries: []
    readonly property bool pickingMode: query.startsWith("?")
    readonly property bool busy: historyProcess.running || actionProcess.running
    readonly property var results: pickingMode ? Search.modes(query.slice(1)) : mode === "apps" ? Search.apps(DesktopEntries.applications.values, query) : Search.clipboard(clipboardEntries, query)

    function toggle(): void {
        if (opened) {
            close();
            return;
        }
        screen = Quickshell.screens.find(item => item.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0];
        mode = "apps";
        query = "";
        error = "";
        opened = true;
    }
    function close(): void {
        generation++;
        opened = false;
        query = "";
        clipboardEntries = [];
        error = "";
    }
    function setMode(next: string): void {
        generation++;
        mode = next;
        query = "";
        error = "";
        if (next === "clipboard")
            refreshClipboard();
    }
    function cycleMode(): void {
        setMode(mode === "apps" ? "clipboard" : "apps");
    }
    function refreshClipboard(): void {
        if (!historyProcess.running) {
            historyProcess.generation = generation;
            historyProcess.running = true;
        }
    }
    function activate(index: int): void {
        const item = results[index];
        if (!item || actionProcess.running)
            return;
        if (item.kind === "mode") {
            setMode(item.mode);
        } else if (item.kind === "app") {
            const command = Search.appCommand(item.entry);
            if (!command.length) {
                error = "This application has no launch command.";
                return;
            }
            Quickshell.execDetached({
                command: command,
                workingDirectory: item.entry.workingDirectory
            });
            close();
        } else {
            actionProcess.generation = generation;
            actionProcess.command = ["shell-clipboard", "copy", item.id];
            actionProcess.running = true;
        }
    }
    function remove(index: int): void {
        const item = results[index];
        if (!item || item.kind !== "clipboard" || actionProcess.running)
            return;
        actionProcess.generation = generation;
        actionProcess.command = ["shell-clipboard", "delete", item.id];
        actionProcess.running = true;
    }
    Process {
        id: historyProcess
        property int generation: 0
        command: ["shell-clipboard", "list"]
        stdout: StdioCollector {
            id: historyOutput
            waitForEnd: true
        }
        // Do not echo clipboard contents or backend errors into persistent shell logs.
        stderr: StdioCollector {}
        // QProcess::ExitStatus is missing from Quickshell's generated qmltypes.
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            if (!root.opened || root.mode !== "clipboard")
                return;
            if (generation !== root.generation) {
                root.refreshClipboard();
                return;
            }
            if (exitCode === 0 && exitStatus === 0) {
                root.clipboardEntries = Search.clipboardRows(historyOutput.text);
            } else {
                root.error = "Could not read clipboard history. Check the clipboard service.";
            }
        }
    }
    Process {
        id: actionProcess
        property int generation: 0
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            if (!root.opened || generation !== root.generation)
                return;
            if (exitCode !== 0 || exitStatus !== 0) {
                root.error = "Clipboard action failed. The entry may no longer exist.";
            } else if (command[1] === "copy") {
                root.close();
            } else {
                root.refreshClipboard();
            }
        }
    }
}
