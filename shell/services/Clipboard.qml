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
    property string imageSession: ""
    property string copyingImage: ""
    property var imageSources: ({})
    property var imageErrors: ({})
    property var imageQueue: []
    property bool imageWorking: false
    readonly property string databasePath: Quickshell.env("CLIPHIST_DB_PATH") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/cliphist/db"
    readonly property bool busy: history.running || action.running || copyingImage !== ""
    readonly property bool imagesPending: imageWorking || imageQueue.length > 0
    signal copied

    onActiveChanged: {
        generation++;
        entries = [];
        error = "";
        copyingImage = "";
        imageSources = {};
        imageErrors = {};
        imageQueue = imageQueue.filter(job => job.operation === "cleanup");
        if (imageSession)
            imageQueue = imageQueue.concat([
                {
                    operation: "cleanup",
                    session: imageSession,
                    generation: generation
                }
            ]);
        if (imageWorker.running && imageWorker.job.operation !== "cleanup")
            imageWorker.running = false;
        imageSession = "";
        if (active) {
            imageSession = "picker_" + Date.now() + "_" + Math.floor(Math.random() * 1000000000);
            refresh();
        }
        Qt.callLater(pumpImages);
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
        const entry = entries.find(item => item.id === id);
        if (!active || busy || !entry)
            return;
        if (entry.imageFormat) {
            error = "";
            copyingImage = id;
            // Always prepare again. A thumbnail may have been evicted, and a
            // selection must work before its preview has finished loading.
            imageQueue = imageQueue.filter(job => job.id !== id || job.session !== imageSession);
            imageQueue = [
                {
                    operation: "prepare",
                    session: imageSession,
                    id: id,
                    generation: generation,
                    forCopy: true
                }
            ].concat(imageQueue);
            pumpImages();
            return;
        }
        runAction("decode", id);
    }
    function remove(id: string): void {
        runAction("delete", id);
    }
    function runAction(operation: string, id: string): void {
        if (!active || action.running || copyingImage || !/^\d+$/.test(id) || !entries.some(item => item.id === id))
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
    function requestPreview(id: string): void {
        if (!active || imageSources[id] || imageErrors[id] || !entries.some(item => item.id === id && item.imageFormat))
            return;
        if ((imageWorker.running && imageWorker.job.session === imageSession && imageWorker.job.id === id) || imageQueue.some(job => job.session === imageSession && job.id === id))
            return;
        imageQueue = imageQueue.concat([
            {
                operation: "prepare",
                session: imageSession,
                id: id,
                generation: generation,
                forCopy: false
            }
        ]);
        pumpImages();
    }
    function previewFailed(id: string): void {
        const failures = Object.assign({}, imageErrors);
        failures[id] = true;
        imageErrors = failures;
    }
    function pumpImages(): void {
        if (imageWorking || !imageQueue.length)
            return;
        const job = imageQueue[0];
        imageQueue = imageQueue.slice(1);
        if (job.operation !== "cleanup" && (!active || job.generation !== generation)) {
            Qt.callLater(pumpImages);
            return;
        }
        imageWorking = true;
        imageWorker.job = job;
        imageWorker.completed = false;
        imageWorker.stdinEnabled = true;
        imageWorker.running = true;
    }
    function imageFailure(job: var, message: string): void {
        if (active && job.generation === generation && job.operation !== "cleanup") {
            const failures = Object.assign({}, imageErrors);
            failures[job.id] = true;
            imageErrors = failures;
            if (job.forCopy || job.operation === "copy") {
                copyingImage = "";
                error = message;
            }
        }
        imageWorking = false;
        Qt.callLater(pumpImages);
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
                root.entries = Search.clipboardRows(historyOutput.text, true);
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
    Process {
        id: imageWorker
        property var job: ({})
        property bool completed: false
        command: ["shell-clipboard-image", "--db-path", root.databasePath]
        stdout: StdioCollector {
            id: imageOutput
            waitForEnd: true
        }
        stderr: StdioCollector {}
        onStarted: {
            if (job.operation === "cleanup" || (root.active && job.generation === root.generation))
                write(JSON.stringify(job));
            stdinEnabled = false;
        }
        onExited: (exitCode, exitStatus) => {
            completed = true;
            if (job.operation === "cleanup" || !root.active || job.generation !== root.generation) {
                root.imageWorking = false;
                Qt.callLater(root.pumpImages);
                return;
            }
            try {
                if (exitCode !== 0 || exitStatus !== 0) {
                    if (imageOutput.text.trim() && JSON.parse(imageOutput.text).error === "image-too-large") {
                        root.imageFailure(job, "Clipboard image exceeds the 64 MiB limit.");
                        return;
                    }
                    throw new Error("image operation failed");
                }
                const response = JSON.parse(imageOutput.text);
                if (job.operation === "copy") {
                    if (response.copied !== true)
                        throw new Error("copy failed");
                    root.copyingImage = "";
                    root.copied();
                } else {
                    if (response.id !== job.id || typeof response.url !== "string" || !response.url.startsWith("file://"))
                        throw new Error("invalid preview");
                    const sources = Object.assign({}, root.imageSources);
                    for (const id of response.evicted || [])
                        delete sources[id];
                    sources[job.id] = response.url;
                    const failures = Object.assign({}, root.imageErrors);
                    delete failures[job.id];
                    root.imageErrors = failures;
                    root.imageSources = sources;
                    if (job.forCopy && root.copyingImage === job.id)
                        root.imageQueue = [
                            {
                                operation: "copy",
                                session: job.session,
                                id: job.id,
                                generation: job.generation
                            }
                        ].concat(root.imageQueue);
                }
            } catch (_) {
                root.imageFailure(job, "Could not load or copy the clipboard image. Try selecting it again.");
            }
            root.imageWorking = false;
            Qt.callLater(root.pumpImages);
        }
        onRunningChanged: {
            if (!running && !completed) {
                const failedJob = job;
                Qt.callLater(() => {
                    if (!completed && job === failedJob)
                        root.imageFailure(failedJob, "Could not start the clipboard image adapter.");
                });
            }
        }
    }
}
