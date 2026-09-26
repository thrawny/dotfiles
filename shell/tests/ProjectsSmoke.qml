import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: root
    readonly property string scenario: Quickshell.env("PROJECTS_TEST_CASE")
    readonly property string repo: Quickshell.env("HOME") + "/code/project with spaces"
    property int stage: 0
    property int opens: 0

    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    function advance(): void {
        if (Projects.busy)
            return;
        if (scenario === "cancel" && stage === 1) {
            if (Projects.entries.length || Projects.error || opens)
                fail("Closed picker accepted stale results");
            else
                Qt.exit(0);
            return;
        }
        if (stage === 3) {
            if (opens || Projects.error || !Projects.entries.length)
                fail("A stale project action affected the reopened picker");
            else
                Qt.exit(0);
            return;
        }
        if (stage === 0) {
            if (Projects.error) {
                fail(Projects.error);
                return;
            }
            const paths = Projects.entries.map(item => item.path);
            if (paths.length !== 3 || paths[0] !== repo || !paths.includes(Quickshell.env("HOME") + "/work/acme/code/nested/project")) {
                fail("Project discovery did not normalize, deduplicate or filter roots: " + JSON.stringify(paths));
                return;
            }
            stage = 2;
            if (scenario === "timeout")
                Projects.operationTimeout = 100;
            if (scenario === "missing-directory")
                Projects.open("~/does-not-exist");
            else if (scenario === "worktree")
                Projects.newWorktree(repo, "feature/nested");
            else
                Projects.open("~/code/project with spaces");
            if (scenario === "cancel-action")
                cancelAction.start();
        } else if (stage === 2 && !Projects.opening) {
            if (["missing-directory", "launch-failure", "missing-launcher", "timeout"].includes(scenario)) {
                if (!Projects.error || opens)
                    fail("Failure was not retained in the picker");
                else
                    Qt.exit(0);
            } else if (!opens) {
                fail(Projects.error || "Project did not open");
            }
        }
    }
    Component.onCompleted: Projects.active = true
    Connections {
        target: Projects
        function onBusyChanged() {
            Qt.callLater(root.advance);
        }
        function onErrorChanged() {
            Qt.callLater(root.advance);
        }
        function onOpened() {
            root.opens++;
            if (root.stage !== 2)
                root.fail("Unexpected project launch");
            else {
                Projects.active = false;
                Qt.exit(0);
            }
        }
    }
    Timer {
        id: cancelAction
        interval: 80
        onTriggered: {
            root.stage = 3;
            Projects.active = false;
            Projects.active = true;
        }
    }
    Timer {
        running: root.scenario === "cancel" || root.scenario === "reopen"
        interval: 40
        onTriggered: {
            Projects.active = false;
            if (root.scenario === "reopen")
                Projects.active = true;
            else
                root.stage = 1;
            Qt.callLater(root.advance);
        }
    }
    Timer {
        running: true
        interval: 8000
        onTriggered: root.fail("Project integration timed out")
    }
}
