pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "AgentsModel.js" as Model

Singleton {
    id: root
    property bool opened: false
    property bool polling: true
    property list<string> snapshotCommand: ["agent-switch", "sidebar-snapshot"]
    property list<string> actionCommand: ["agent-switch", "sidebar-action"]
    property int timeoutMs: 8000
    signal refreshed
    property ShellScreen screen: null
    property var threads: []
    property string focusedArea: ""
    property bool globalScope: false
    property bool settledExpanded: false
    property bool archivedExpanded: false
    property int revision: 0
    property bool available: false
    property string snapshotError: ""
    property string actionError: ""
    readonly property string error: actionError || snapshotError
    property string message: ""
    property real updatedAt: 0
    property real now: Date.now() / 1000
    readonly property bool stale: !available || now - updatedAt > 10
    readonly property bool busy: action.running
    readonly property var counts: Model.counts(threads)
    readonly property var scopedCounts: Model.counts(threads.filter(thread => globalScope || !focusedArea || thread.area === focusedArea))
    readonly property var rows: Model.rows(threads, focusedArea, globalScope, settledExpanded, archivedExpanded)
    readonly property string indicator: stale ? "󰚩 ?" : counts.approval ? "! " + counts.approval : counts.input ? "? " + counts.input : counts.done ? "✓ " + counts.done : counts.working ? "⚙ " + counts.working : "󰚩 " + counts.active
    readonly property string tooltip: error ? "Agents: " + error : stale ? "Agents unavailable: " + error : counts.active + " active · " + counts.working + " working · " + counts.done + " done\n" + counts.approval + " approvals · " + counts.input + " questions\nClick to open agents"

    function toggle(target: ShellScreen): void {
        const monitor = Hyprland.focusedMonitor;
        screen = target || Quickshell.screens.find(item => monitor && item.name === monitor.name) || Quickshell.screens[0] || null;
        opened = !opened;
        if (!opened)
            actionError = "";
        if (opened) {
            message = "";
            refresh();
        }
    }
    function close(): void {
        opened = false;
        actionError = "";
    }
    function refresh(): void {
        if (poll.running || action.running)
            return;
        poll.timedOut = false;
        poll.revision = revision;
        poll.completed = false;
        poll.running = true;
    }
    function accept(text: string, actionResult: bool): void {
        try {
            const snapshot = Model.validate(JSON.parse(text));
            threads = snapshot.threads;
            focusedArea = snapshot.focused_area || "";
            updatedAt = snapshot.updated_at;
            available = true;
            snapshotError = "";
            if (snapshot.message)
                message = snapshot.message;
        } catch (failure) {
            if (actionResult) {
                actionError = String(failure);
                opened = true;
            } else {
                available = false;
                snapshotError = String(failure);
            }
        }
    }
    function perform(request: var): void {
        if (action.running)
            return;
        actionError = "";
        revision++;
        action.payload = JSON.stringify(request);
        action.completed = false;
        action.timedOut = false;
        action.stdinEnabled = true;
        action.running = true;
    }
    function elapsed(timestamp: real): string {
        return Model.age(timestamp, now);
    }

    Timer {
        interval: 1000
        running: root.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now() / 1000;
            root.refresh();
        }
    }
    Timer {
        interval: root.timeoutMs
        running: poll.running
        onTriggered: {
            poll.timedOut = true;
            poll.completed = true;
            root.available = false;
            root.snapshotError = "Agent snapshot timed out. Retrying…";
            poll.signal(9);
            root.refreshed();
        }
    }
    Timer {
        interval: root.timeoutMs
        running: action.running
        onTriggered: {
            action.timedOut = true;
            action.completed = true;
            root.actionError = "Agent action timed out. Check its state before retrying.";
            root.opened = true;
            action.signal(9);
            root.refreshed();
        }
    }
    Process {
        id: poll
        property int revision: 0
        property bool completed: false
        property bool timedOut: false
        command: root.snapshotCommand
        stdout: StdioCollector {
            id: pollOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: pollError
            waitForEnd: true
        }
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (revision !== root.revision || timedOut)
                return;
            if (exitCode === 0 && exitStatus === 0)
                root.accept(pollOutput.text, false);
            else {
                root.available = false;
                root.snapshotError = pollError.text.trim() || "Could not read agent-switch state.";
            }
            root.refreshed();
        }
        onRunningChanged: {
            if (!running && !completed) {
                root.available = false;
                root.snapshotError = "Could not start agent-switch.";
                root.refreshed();
            }
        }
    }
    Process {
        id: action
        property string payload: ""
        property bool completed: false
        property bool timedOut: false
        command: root.actionCommand
        stdout: StdioCollector {
            id: actionOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: actionStderr
            waitForEnd: true
        }
        onStarted: {
            write(payload);
            stdinEnabled = false;
            payload = "";
        }
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (timedOut)
                return;
            if (exitCode === 0 && exitStatus === 0)
                root.accept(actionOutput.text, true);
            else {
                root.actionError = actionStderr.text.trim() || "Agent action failed.";
                root.opened = true;
            }
            root.refreshed();
        }
        onRunningChanged: {
            if (!running && !completed) {
                root.actionError = "Could not start agent-switch.";
                root.opened = true;
                root.refreshed();
            }
        }
    }
}
