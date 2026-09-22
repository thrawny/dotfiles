pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Search.js" as Search

Singleton {
    id: root
    property bool active: false
    property int generation: 0
    property var entries: []
    property string error: ""
    property bool refreshPending: false
    readonly property string databasePath: Quickshell.env("CLIPHIST_DB_PATH") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/cliphist/db"
    readonly property bool busy: history.running || action.running
    signal copied

    onActiveChanged: {
        generation++;
        entries = [];
        error = "";
        if (active)
            refresh();
    }
    function refresh(): void {
        if (!active)
            return;
        if (history.running) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        error = "";
        history.generation = generation;
        history.completed = false;
        history.running = true;
    }
    function copy(id: string): void {
        runAction("decode", id);
    }
    function remove(id: string): void {
        runAction("delete", id);
    }
    function runAction(operation: string, id: string): void {
        if (!active || action.running || !/^\d+$/.test(id) || !entries.some(item => item.id === id))
            return;
        error = "";
        action.generation = generation;
        action.completed = false;
        action.operation = operation;
        action.entryId = id;
        action.command = ["cliphist", "-db-path", databasePath, operation];
        action.stdinEnabled = true;
        action.running = true;
    }

    // Clipboard content stays in memory, never command arguments or shell logs.
    Process {
        id: history
        property int generation: 0
        property bool completed: false
        command: ["cliphist", "-db-path", root.databasePath, "list"]
        stdout: StdioCollector {
            id: historyOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: historyError
            waitForEnd: true
        }
        // QProcess::ExitStatus is absent from the generated Quickshell qmltypes.
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (!root.active)
                return;
            if (generation !== root.generation || root.refreshPending) {
                root.refresh();
                return;
            }
            if (exitCode === 0 && exitStatus === 0) {
                root.entries = Search.clipboardRows(historyOutput.text);
            } else if (exitCode === 1 && exitStatus === 0 && historyError.text.trim() === "opening db: please store something first") {
                // cliphist 0.7 has no database until the first copy.
                root.entries = [];
            } else {
                root.error = "Could not read clipboard history.";
            }
        }
        // FailedToStart does not emit exited in Quickshell 0.3.1.
        onRunningChanged: {
            if (!running && !completed && root.active && generation === root.generation)
                root.error = "Could not start cliphist. Check that it is installed.";
        }
    }
    Process {
        id: action
        property int generation: 0
        property bool completed: false
        property string entryId: ""
        property string operation: ""
        stdout: StdioCollector {
            id: actionOutput
            waitForEnd: true
        }
        stderr: StdioCollector {}
        onStarted: {
            // decode expects the ID without a trailing newline. Closing stdin
            // flushes the write and sends EOF; no shell or pipe is involved.
            write(entryId);
            stdinEnabled = false;
        }
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (!root.active || generation !== root.generation)
                return;
            if (exitCode !== 0 || exitStatus !== 0) {
                root.error = "Clipboard action failed. The entry may no longer exist.";
            } else if (operation === "delete") {
                root.refresh();
            } else if (actionOutput.text.includes("\u0000")) {
                root.error = "Only text clipboard entries are supported.";
            } else {
                // Do not trim: preserve whitespace and trailing newlines.
                // The launcher still has Wayland keyboard focus at this point.
                Quickshell.clipboardText = actionOutput.text;
                root.copied();
            }
        }
        onRunningChanged: {
            if (!running && !completed && root.active && generation === root.generation)
                root.error = "Could not start cliphist. Check that it is installed.";
        }
    }
}
