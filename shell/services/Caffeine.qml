pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool active: false
    property bool available: false
    property string error: ""
    readonly property bool busy: action.running

    function refresh(): void {
        if (!state.running && !action.running)
            state.running = true;
    }
    function toggle(): void {
        if (!available || busy)
            return;
        error = "";
        action.command = ["systemctl", "--user", active ? "stop" : "start", "dotfiles-caffeine.service"];
        action.running = true;
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
        command: ["systemctl", "--user", "show", "dotfiles-caffeine.service", "--property=ActiveState", "--value"]
        stdout: StdioCollector {
            id: stateOutput
            waitForEnd: true
        }
        stderr: StdioCollector {}
        // QProcess::ExitStatus is missing from Quickshell's generated qmltypes.
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0 && exitStatus === 0;
            root.active = root.available && ["active", "activating", "reloading"].includes(stateOutput.text.trim());
        }
    }
    Process {
        id: action
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0)
                root.error = "Could not change caffeine. Check dotfiles-caffeine.service.";
            root.refresh();
        }
    }
}
