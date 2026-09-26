pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ProjectWorktree.js" as Worktree

Singleton {
    id: root
    property bool active: false
    property var entries: []
    property string error: ""
    property bool opening: false
    property int generation: 0
    property var queue: []
    property var candidates: []
    readonly property string home: Quickshell.env("HOME")
    property bool inFlight: false
    property int operationTimeout: 60000
    readonly property bool busy: inFlight || queue.length > 0
    signal opened

    onActiveChanged: {
        generation++;
        queue = [];
        entries = [];
        candidates = [];
        error = "";
        opening = false;
        if (active) {
            queue = [
                {
                    kind: "zoxide",
                    command: ["zoxide", "query", "-l"]
                },
                {
                    kind: "probe",
                    path: home + "/code",
                    depth: 3,
                    command: ["test", "-d", home + "/code"]
                },
                {
                    kind: "probe",
                    path: home + "/work",
                    depth: 5,
                    command: ["test", "-d", home + "/work"]
                }
            ];
            Qt.callLater(pump);
        }
    }

    function enqueue(job: var): void {
        queue = queue.concat([job]);
        Qt.callLater(pump);
    }
    function pump(): void {
        if (!active || inFlight || !queue.length)
            return;
        inFlight = true;
        worker.job = queue[0];
        queue = queue.slice(1);
        worker.generation = generation;
        worker.completed = false;
        worker.timedOut = false;
        worker.command = worker.job.command;
        worker.running = true;
    }
    function candidate(path: string): void {
        if (!path.startsWith("/") || candidates.includes(path))
            return;
        candidates = candidates.concat([path]);
        enqueue({
            kind: "canonical",
            command: ["realpath", "-e", "-z", "--", path]
        });
    }
    function entry(path: string): void {
        if (!path || entries.some(item => item.path === path))
            return;
        entries = entries.concat([
            {
                kind: "project",
                path: path,
                name: path.slice(path.lastIndexOf("/") + 1) || "/",
                detail: path.startsWith(home + "/") ? "~" + path.slice(home.length) : path,
                icon: "folder-symbolic"
            }
        ]);
    }
    function beginAction(): void {
        generation++;
        queue = [];
        opening = true;
        error = "";
    }
    function open(path: string): void {
        if (!active || opening)
            return;
        if (path === "~")
            path = home;
        else if (path.startsWith("~/"))
            path = home + path.slice(1);
        if (!path.startsWith("/")) {
            error = "Enter an absolute directory path or a path starting with ~/.";
            return;
        }
        beginAction();
        checkDirectory(path, "");
    }
    function checkDirectory(path: string, workspace: string): void {
        enqueue({
            kind: "open-probe",
            path: path,
            workspace: workspace,
            command: ["test", "-d", path]
        });
    }
    function newWorktree(path: string, branch: string): void {
        if (!active || opening)
            return;
        const state = Worktree.begin(path, branch);
        if (state.error) {
            error = state.error;
            return;
        }
        beginAction();
        enqueue({
            kind: "worktree",
            state: state,
            command: state.command
        });
    }
    function failed(message: string): void {
        error = message;
        opening = false;
    }
    function finish(job: var, code: int, output: string, detail: string): void {
        switch (job.kind) {
        case "zoxide":
            if (code === 0) {
                const jobs = output.split("\n").filter(path => path.startsWith("/")).map(path => ({
                            kind: "git-root",
                            command: ["git", "-C", path, "rev-parse", "--show-toplevel"]
                        }));
                queue = jobs.concat(queue);
            } else {
                error = "Could not read zoxide history. Showing scanned projects.";
            }
            break;
        case "git-root":
            if (code === 0)
                candidate(output.replace(/\n$/, ""));
            break;
        case "probe":
            if (code === 0)
                enqueue({
                    kind: "scan",
                    path: job.path,
                    command: ["fd", "--hidden", "--no-ignore", "--max-depth", String(job.depth), "--print0", "--glob", ".git", job.path]
                });
            break;
        case "scan":
            if (code !== 0)
                error = "Could not scan project directories.";
            for (let marker of output.split("\0")) {
                marker = marker.replace(/\/$/, "");
                if (!marker.endsWith("/.git"))
                    continue;
                // Only ~/work/*/code is a project root, not arbitrary work folders.
                if (job.path === home + "/work" && !/^[^/]+\/code(?:\/.*)?\/\.git$/.test(marker.slice(job.path.length + 1)))
                    continue;
                candidate(marker.slice(0, -5));
            }
            break;
        case "canonical":
            if (code === 0)
                entry(output.split("\0")[0]);
            break;
        case "open-probe":
            if (code !== 0)
                failed("Not a directory: " + job.path);
            else
                enqueue({
                    kind: "open-canonical",
                    workspace: job.workspace,
                    command: ["realpath", "-e", "-z", "--", job.path]
                });
            break;
        case "open-canonical":
            if (code !== 0) {
                failed("Could not resolve the project directory.");
            } else {
                const path = output.split("\0")[0];
                const args = ["hyprland-project", "--terminals", "1"];
                if (job.workspace)
                    args.push("--name", job.workspace);
                args.push("--", path);
                enqueue({
                    kind: "launch",
                    command: args
                });
            }
            break;
        case "launch":
            opening = false;
            if (code === 0)
                opened();
            else
                failed(detail.trim() || output.trim() || "Could not open the project workspace.");
            break;
        case "worktree":
            {
                const state = Worktree.advance(job.state, code, output, detail);
                if (state.stage === "error")
                    failed(state.error);
                else if (state.stage === "done")
                    checkDirectory(state.path, state.workspace);
                else
                    enqueue({
                        kind: "worktree",
                        state: state,
                        command: state.command
                    });
                break;
            }
        }
        Qt.callLater(pump);
    }

    Timer {
        interval: root.operationTimeout
        running: root.inFlight
        onTriggered: {
            worker.timedOut = true;
            worker.running = false;
        }
    }
    Process {
        id: worker
        property var job: ({})
        property int generation: 0
        property bool completed: true
        property bool timedOut: false
        // Quickshell declares QVariantHash; QML object literals are QVariantMap.
        // qmllint disable incompatible-type
        environment: ({
                GIT_TERMINAL_PROMPT: "0"
            })
        // qmllint enable incompatible-type
        stdout: StdioCollector {
            id: output
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: errors
            waitForEnd: true
        }
        // QProcess::ExitStatus is absent from the generated Quickshell qmltypes.
        // qmllint disable signal-handler-parameters
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (root.active && generation === root.generation)
                root.finish(job, timedOut ? -1 : exitStatus === 0 ? exitCode : -1, output.text, timedOut ? "Project operation timed out." : errors.text);
            else
                Qt.callLater(root.pump);
            root.inFlight = false;
        }
        onRunningChanged: {
            if (!running && !completed) {
                const request = job;
                const token = generation;
                // FailedToStart has no exited signal. Let a normal exit finish first.
                Qt.callLater(() => {
                    if (worker.job !== request || worker.completed)
                        return;
                    worker.completed = true;
                    if (root.active && token === root.generation)
                        root.finish(request, -1, "", worker.timedOut ? "Project operation timed out." : "Could not start " + request.command[0] + ". Check that it is installed.");
                    root.inFlight = false;
                    Qt.callLater(root.pump);
                });
            }
        }
    }
}
