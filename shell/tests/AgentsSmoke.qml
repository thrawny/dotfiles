import QtQuick
import Quickshell
import "../services"
import "../modules/agents"

ShellRoot {
    id: root
    property int stage: 0
    readonly property string scenario: Quickshell.env("AGENTS_TEST_CASE")
    readonly property string fixture: Quickshell.env("AGENTS_FIXTURE")
    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    Component.onCompleted: {
        Agents.polling = false;
        Agents.snapshotCommand = ["cat", fixture];
        Agents.refresh();
    }
    FloatingWindow {
        visible: true
        implicitWidth: 480
        implicitHeight: root.scenario === "layout" ? 940 : 800
        color: Theme.background
        AgentsPanel {
            id: sidebar
            anchors.fill: parent
        }
    }
    Connections {
        target: Agents
        function onRefreshed() {
            if (root.stage === 0) {
                if (!Agents.available || Agents.threads.length !== 1 || Agents.counts.approval !== 1) {
                    root.fail("Valid snapshot did not load");
                    return;
                }
                root.stage = 1;
                if (root.scenario === "layout") {
                    const fixtureThread = Agents.threads[0];
                    Agents.now = 10000;
                    Agents.globalScope = true;
                    Agents.settledExpanded = true;
                    Agents.archivedExpanded = true;
                    Agents.threads = [Object.assign({}, fixtureThread, {
                            seq: 1,
                            order: 9,
                            harness: "claude",
                            title: "Approve the deployment change",
                            repo: "dotfiles",
                            area: "dotfiles",
                            branch: "main",
                            attention: "approval",
                            state_updated: 9900
                        }), Object.assign({}, fixtureThread, {
                            seq: 2,
                            order: 8,
                            harness: "codex",
                            title: "Choose the API response shape",
                            repo: "agent-switch",
                            branch: "sidebar-api",
                            attention: "input",
                            state_updated: 9700
                        }), Object.assign({}, fixtureThread, {
                            seq: 3,
                            order: 7,
                            harness: "pi",
                            title: "All integration checks passed",
                            repo: "quickshell",
                            branch: "visual-parity",
                            attention: "done",
                            state_updated: 9300
                        }), Object.assign({}, fixtureThread, {
                            seq: 4,
                            order: 6,
                            harness: "codex",
                            title: "Building the release package",
                            repo: "quotabar",
                            branch: "main",
                            attention: "working",
                            state_updated: 9515
                        }), Object.assign({}, fixtureThread, {
                            seq: 5,
                            order: 5,
                            harness: "claude",
                            title: "Investigate the startup sequence",
                            repo: "dotfiles",
                            branch: "main",
                            attention: "idle",
                            state_updated: 8200,
                            cold: true
                        }), Object.assign({}, fixtureThread, {
                            seq: 6,
                            order: 4,
                            title: "Clipboard image support",
                            repo: "dotfiles",
                            lifecycle: "settled",
                            attention: "idle",
                            settled_at: 6400
                        }), Object.assign({}, fixtureThread, {
                            seq: 7,
                            order: 3,
                            title: "Previous provider status refresh",
                            repo: "quotabar",
                            lifecycle: "archived",
                            attention: "idle",
                            settled_at: 2000
                        })];
                    sidebar.selectedSeq = 5;
                    sidebar.select(1);
                    if (sidebar.selectedSeq !== 6) {
                        root.fail("Shelf header took a thread navigation slot");
                        return;
                    }
                    sidebar.select(1);
                    if (sidebar.selectedSeq !== 7) {
                        root.fail("Archived shelf navigation skipped the thread");
                        return;
                    }
                    sidebar.select(1);
                    if (sidebar.selectedSeq !== 1) {
                        root.fail("Thread navigation failed to wrap across shelf headers");
                        return;
                    }
                    captureLayout.start();
                    return;
                }
                if (root.scenario === "rename" || root.scenario === "rename-gone") {
                    Agents.threads = [Agents.threads[0], Object.assign({}, Agents.threads[0], {
                            seq: 3
                        })];
                    sidebar.selectedSeq = 2;
                    sidebar.act("rename");
                    sidebar.selectedSeq = 3;
                    sidebar.ensureSelection();
                    if (sidebar.renameSeq !== 2) {
                        root.fail("Rename target followed mutable selection");
                        return;
                    }
                    if (root.scenario === "rename-gone") {
                        Agents.threads = Agents.threads.filter(thread => thread.seq !== 2);
                        sidebar.ensureSelection();
                        if (sidebar.renaming)
                            root.fail("Rename stayed active for a missing thread");
                        else
                            Qt.exit(0);
                        return;
                    }
                    Agents.actionCommand = ["python3", "-c", "import json,pathlib,sys; request=json.load(sys.stdin); assert request['seq']==2 and request['title']=='Saved title'; print(pathlib.Path(sys.argv[1]).read_text())", root.fixture];
                    sidebar.saveRename("Saved title");
                    return;
                }
                if (root.scenario === "late") {
                    Agents.snapshotCommand = ["python3", "-c", "import pathlib,sys,time; time.sleep(0.3); print(pathlib.Path(sys.argv[1]).read_text())", root.fixture];
                    Agents.actionCommand = ["cat", root.fixture + ".new"];
                    Qt.callLater(Agents.refresh);
                    actLater.start();
                    return;
                }
                if (root.scenario === "invalid")
                    Agents.snapshotCommand = ["printf", "{bad json"];
                else if (root.scenario === "version")
                    Agents.snapshotCommand = ["printf", "{\"schema_version\":2,\"threads\":[]}"];
                else if (root.scenario === "missing")
                    Agents.snapshotCommand = ["/nonexistent/dotfiles-agent-test"];
                else if (root.scenario === "timeout") {
                    Agents.timeoutMs = 100;
                    Agents.snapshotCommand = ["sleep", "2"];
                } else if (root.scenario === "action") {
                    Agents.actionCommand = ["false"];
                    Agents.close();
                    Qt.callLater(() => Agents.perform({
                            action: "new"
                        }));
                    return;
                } else
                    Agents.snapshotCommand = ["false"];
                Qt.callLater(Agents.refresh);
            } else if (root.scenario === "rename") {
                if (Agents.error)
                    root.fail(Agents.error);
                else
                    Qt.exit(0);
            } else if (root.scenario === "late") {
                if (Agents.threads[0].title !== "Updated thread")
                    root.fail("Action did not update state");
                else
                    checkLate.start();
            } else if (root.scenario === "action" && root.stage === 1) {
                if (!Agents.error || !Agents.opened) {
                    root.fail("Action failure was hidden");
                    return;
                }
                root.stage = 2;
                Qt.callLater(Agents.refresh);
            } else {
                if (!Agents.error || Agents.threads[0].title !== "Fixture thread")
                    root.fail("Failure discarded last state or hid error");
                else if (root.scenario === "action" && !Agents.opened)
                    root.fail("Action failure did not reopen the sidebar");
                else
                    Qt.exit(0);
            }
        }
    }
    Timer {
        id: captureLayout
        interval: 300
        onTriggered: sidebar.grabToImage(result => {
            const output = Quickshell.env("AGENTS_VISUAL_OUTPUT");
            if (output && !result.saveToFile(output))
                root.fail("Could not save agent visual fixture");
            else
                Qt.exit(0);
        })
    }
    Timer {
        id: actLater
        interval: 40
        onTriggered: Agents.perform({
            action: "rename",
            seq: 2,
            title: "Updated thread"
        })
    }
    Timer {
        id: checkLate
        interval: 500
        onTriggered: {
            if (Agents.threads[0].title !== "Updated thread")
                root.fail("Late poll overwrote the completed action");
            else
                Qt.exit(0);
        }
    }
    Timer {
        running: true
        interval: 5000
        onTriggered: root.fail("Agent service integration timed out")
    }
}
