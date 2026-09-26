import QtQuick
import Quickshell
import "../services"
import "../modules/launcher"

ShellRoot {
    id: root
    property bool checked: false
    Window {
        id: panel
        width: 800
        height: 700
        visible: true
        color: Theme.background
        LauncherPanel {
            anchors.fill: parent
        }
    }
    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    function check(): void {
        if (checked || !Theme.ready || Projects.busy)
            return;
        checked = true;
        if (!Launcher.opened || Launcher.mode !== "projects" || !Launcher.results.length) {
            fail("Alt+P entrypoint did not open projects");
            return;
        }
        Launcher.query = "widgets";
        if (Launcher.results.length !== 1) {
            fail("Project search did not filter");
            return;
        }
        Launcher.beginWorktree(0);
        if (!Launcher.worktreeProject || Launcher.results.length || Launcher.query) {
            fail("Worktree entry did not capture the selected project");
            return;
        }
        Launcher.query = "feature/example";
        Launcher.dismiss();
        if (Launcher.worktreeProject || !Launcher.opened) {
            fail("Escape from branch entry did not return to projects");
            return;
        }
        Launcher.manualPath();
        if (!Launcher.enteringPath || Launcher.query !== "~/") {
            fail("Manual path entry did not open");
            return;
        }
        Launcher.dismiss();
        Launcher.setMode("apps");
        Launcher.cycleMode();
        Launcher.cycleMode();
        if (Launcher.mode !== "projects") {
            fail("Tab cycle does not include projects");
            return;
        }
        // Snapshot uses fixtures, never the user's repositories or clipboard.
        capture.start();
    }
    Component.onCompleted: Launcher.toggleProjects()
    Connections {
        target: Theme
        function onReadyChanged() {
            Qt.callLater(root.check);
        }
    }
    Connections {
        target: Projects
        function onBusyChanged() {
            Qt.callLater(root.check);
        }
    }
    Timer {
        id: capture
        interval: 250
        onTriggered: {
            if (Projects.busy) {
                restart();
                return;
            }
            panel.contentItem.grabToImage(result => {
                if (!result.saveToFile(Quickshell.env("PROJECTS_SCREENSHOT"))) {
                    root.fail("Could not save project picker screenshot");
                    return;
                }
                Launcher.toggleProjects();
                if (Launcher.opened || Projects.active)
                    root.fail("Second Alt+P did not close the picker");
                else {
                    console.log("Project launcher verified");
                    Qt.exit(0);
                }
            });
        }
    }
    Timer {
        running: true
        interval: 6000
        onTriggered: root.fail("Project launcher test timed out")
    }
}
