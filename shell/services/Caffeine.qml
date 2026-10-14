pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var snapshot: ({})
    readonly property bool active: snapshot.active === true
    readonly property bool paused: snapshot.paused === true
    readonly property var sessions: snapshot.sessions || []
    readonly property var rules: snapshot.rules || []
    property bool available: false
    property string error: ""
    property string actionError: ""
    property string executable: "keepawake"
    property var snapshotCommand: [executable, "status"]
    readonly property bool busy: action.running
    readonly property string configPath: snapshot.config_path || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/keepawake/config.toml"
    readonly property string tooltip: {
        if (!available)
            return error || "Keep-awake service unavailable";
        const reasons = (snapshot.reasons || []).join(", ");
        const timers = sessions.filter(session => session.remaining_seconds !== null).map(session => session.name + ": " + Math.ceil(session.remaining_seconds / 60) + "m remaining");
        return [error || actionError, paused ? "Keep awake paused" : active ? "Keep awake: " + reasons : "Normal sleep enabled", ...timers, "Screen sleep " + (snapshot.keep_display_awake ? "prevented" : "allowed") + " · Battery limit " + (snapshot.battery_floor ?? 20) + "%", "Click for sessions · Right-click to toggle manual session"].filter(Boolean).join("\n");
    }
    function refresh(): void {
        if (!state.running && !action.running)
            state.running = true;
    }
    function invoke(args: var): void {
        if (!available || busy)
            return;
        actionError = "";
        action.command = [executable, ...args];
        action.running = true;
    }
    function toggle(): void {
        invoke(["toggle"]);
    }
    function togglePause(): void {
        invoke(["toggle-pause"]);
    }
    function start(kind: string, value: string, displayAwake: bool, lidClosed: bool): void {
        const args = ["start"];
        if (kind !== "indefinite")
            args.push("--" + kind, value);
        args.push(displayAwake ? "--keep-display-awake" : "--no-keep-display-awake");
        args.push(lidClosed ? "--allow-lid-closed" : "--no-allow-lid-closed");
        invoke(args);
    }
    function stop(id: string): void {
        invoke(id ? ["stop", "--id", id] : ["stop"]);
    }
    function editConfig(): void {
        Quickshell.execDetached(["ghostty", "-e", "nvim", configPath]);
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Process {
        id: state
        property bool completed: false
        command: root.snapshotCommand
        onRunningChanged: {
            if (running)
                completed = false;
            else if (!completed)
                failure();
        }
        stdout: StdioCollector {
            id: stateOutput
            waitForEnd: true
        }
        stderr: StdioCollector {}
        function failure(): void {
            root.available = false;
            root.snapshot = ({});
            root.error = "Keep-awake service unavailable";
        }
        // QProcess::ExitStatus is missing from Quickshell's generated qmltypes.
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (exitCode !== 0 || exitStatus !== 0) {
                failure();
                return;
            }
            try {
                const next = JSON.parse(stateOutput.text);
                if (next.version !== 1 || typeof next.active !== "boolean")
                    throw new Error("Invalid keep-awake snapshot");
                root.snapshot = next;
                root.available = true;
                root.error = next.error || "";
            } catch (_) {
                failure();
            }
        }
    }
    Process {
        id: action
        property bool completed: false
        onRunningChanged: {
            if (running)
                completed = false;
            else if (!completed)
                root.actionError = "Could not start keep-awake command";
        }
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: actionOutput
            waitForEnd: true
        }
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (exitCode !== 0 || exitStatus !== 0)
                root.actionError = actionOutput.text.trim() || "Could not change keep-awake session";
            Qt.callLater(root.refresh);
        }
    }
}
