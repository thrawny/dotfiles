pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // The backend owns credentials, caching, quota policy and notifications.
    property var command: ["quotabar", "snapshot"]
    property var providers: []
    property string error: ""
    property string generatedAt: ""
    property bool polling: true
    property bool timedOut: false
    readonly property bool busy: snapshot.running
    signal refreshed

    Component.onCompleted: Qt.callLater(() => {
        if (polling)
            refresh();
    })

    function provider(id: string): var {
        return providers.find(item => item.id === id) || null;
    }
    function openUsage(id: string): void {
        const url = provider(id)?.usage_url;
        if (url)
            Quickshell.execDetached(["xdg-open", url]);
    }
    function refresh(): void {
        if (busy)
            return;
        timedOut = false;
        snapshot.completed = false;
        snapshot.running = true;
    }
    Timer {
        interval: 30000
        running: root.polling
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: 90000
        running: root.busy
        onTriggered: {
            root.timedOut = true;
            root.error = "Quota refresh timed out. Showing the last snapshot.";
            snapshot.running = false;
        }
    }
    Process {
        id: snapshot
        property bool completed: false
        command: root.command
        stdout: StdioCollector {
            id: output
            waitForEnd: true
        }
        stderr: StdioCollector {}
        // QProcess::ExitStatus is absent from Quickshell's generated qmltypes.
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (root.timedOut)
                return;
            if (exitCode !== 0 || exitStatus !== 0) {
                root.error = "Quota refresh failed. Showing the last snapshot.";
                root.refreshed();
                return;
            }
            try {
                const next = JSON.parse(output.text);
                if (next.schema_version !== 1 || !Array.isArray(next.providers) || !["claude", "codex"].every(id => next.providers.some(item => item.id === id && Array.isArray(item.windows))))
                    throw new Error("Unsupported snapshot");
                root.providers = next.providers;
                root.generatedAt = next.generated_at || "";
                root.error = "";
            } catch (_) {
                root.error = "Invalid quota snapshot. Showing the last snapshot.";
            }
            root.refreshed();
        }
        onRunningChanged: {
            if (!running && !completed && !root.timedOut) {
                root.error = "Could not start quotabar. Check that it is installed.";
                root.refreshed();
            }
        }
    }
}
