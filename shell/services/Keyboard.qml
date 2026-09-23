pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    property string name: ""
    property string label: "?"
    property string error: ""
    property bool refreshPending: false
    readonly property bool busy: change.running

    function refresh(): void {
        if (!query.running) {
            refreshPending = false;
            query.running = true;
        } else
            refreshPending = true;
    }
    function next(): void {
        if (!change.running)
            change.running = true;
    }
    Component.onCompleted: refresh()
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["activelayout", "configreloaded"].includes(event.name))
                root.refresh();
        }
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Process {
        id: query
        property bool completed: false
        onRunningChanged: {
            if (running)
                completed = false;
            else if (!completed)
                failure();
        }
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            id: output
            waitForEnd: true
        }
        stderr: StdioCollector {}
        function failure(): void {
            root.error = "Keyboard layout unavailable";
        }
        // qmllint disable signal-handler-parameters
        onExited: (code, status) => {
            completed = true;
            try {
                if (code !== 0 || status !== 0)
                    throw new Error("query failed");
                const keyboards = JSON.parse(output.text).keyboards;
                const keyboard = keyboards.find(item => item.main) || keyboards[0];
                root.name = keyboard.active_keymap;
                root.label = keyboard.layout.split(",")[keyboard.active_layout_index].toUpperCase();
                root.error = "";
            } catch (_) {
                root.error = "Keyboard layout unavailable";
            }
            if (root.refreshPending)
                Qt.callLater(root.refresh);
        }
    }
    Process {
        id: change
        property bool completed: false
        onRunningChanged: {
            if (running)
                completed = false;
            else if (!completed)
                failure();
        }
        command: ["hyprctl", "switchxkblayout", "all", "next"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        function failure(): void {
            root.error = "Could not switch keyboard layout";
        }
        onExited: (code, status) => {
            completed = true;
            root.error = code === 0 && status === 0 ? "" : "Could not switch keyboard layout";
            root.refresh();
        }
    }
}
