pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Search.js" as Search

Singleton {
    id: root
    property bool opened: false
    property string mode: "apps"
    property string query: ""
    property string appError: ""
    property bool enteringPath: false
    property var worktreeProject: null
    readonly property string error: mode === "clipboard" ? Clipboard.error : mode === "projects" ? Projects.error : appError
    readonly property bool busy: mode === "clipboard" ? Clipboard.busy : mode === "projects" && Projects.busy
    property var screen: null
    readonly property bool pickingMode: !enteringPath && !worktreeProject && query.startsWith("?")
    readonly property var results: enteringPath || worktreeProject ? [] : pickingMode ? Search.modes(query.slice(1)) : mode === "apps" ? Search.apps(DesktopEntries.applications.values, query) : mode === "projects" ? Search.projects(Projects.entries, query) : Search.clipboard(Clipboard.entries, query)

    function syncServices(): void {
        Clipboard.active = opened && mode === "clipboard";
        Projects.active = opened && mode === "projects";
    }
    onOpenedChanged: syncServices()
    onModeChanged: syncServices()
    Connections {
        target: Clipboard
        function onCopied() {
            root.close();
        }
    }

    Connections {
        target: Projects
        function onOpened() {
            root.close();
        }
    }

    function toggle(): void {
        showMode("apps");
    }
    function toggleProjects(): void {
        showMode("projects");
    }
    function showMode(next: string): void {
        if (opened && mode === next) {
            close();
            return;
        }
        screen = Quickshell.screens.find(item => item.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0];
        setMode(next);
        opened = true;
    }
    function close(): void {
        opened = false;
        query = "";
        appError = "";
        enteringPath = false;
        worktreeProject = null;
    }
    function setMode(next: string): void {
        if (Projects.opening)
            return;
        enteringPath = false;
        worktreeProject = null;
        mode = next;
        query = "";
        appError = "";
    }
    function cycleMode(): void {
        const modes = ["apps", "clipboard", "projects"];
        setMode(modes[(modes.indexOf(mode) + 1) % modes.length]);
    }
    function manualPath(): void {
        if (mode !== "projects" || Projects.opening)
            return;
        worktreeProject = null;
        enteringPath = true;
        query = "~/";
        Projects.error = "";
    }
    function beginWorktree(index: int): void {
        const item = results[index];
        if (mode !== "projects" || Projects.opening || item?.kind !== "project")
            return;
        worktreeProject = item;
        enteringPath = false;
        query = "";
        Projects.error = "";
    }
    function dismiss(): void {
        if ((enteringPath || worktreeProject) && !Projects.opening) {
            enteringPath = false;
            worktreeProject = null;
            query = "";
            Projects.error = "";
        } else {
            close();
        }
    }
    function activate(index: int): void {
        if (worktreeProject) {
            Projects.newWorktree(worktreeProject.path, query);
            return;
        }
        if (enteringPath) {
            Projects.open(query);
            return;
        }
        const item = results[index];
        if (!item)
            return;
        if (item.kind === "mode") {
            setMode(item.mode);
        } else if (item.kind === "app") {
            const command = Search.appCommand(item.entry);
            if (!command.length) {
                appError = "This application has no launch command.";
                return;
            }
            Quickshell.execDetached({
                command: command,
                workingDirectory: item.entry.workingDirectory
            });
            close();
        } else if (item.kind === "clipboard") {
            Clipboard.copy(item.id);
        } else if (item.kind === "project") {
            Projects.open(item.path);
        }
    }
    function remove(index: int): void {
        const item = results[index];
        if (item?.kind === "clipboard")
            Clipboard.remove(item.id);
    }
}
