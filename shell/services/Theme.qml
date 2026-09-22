pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var palette: ({})
    readonly property bool ready: Object.keys(palette).length > 0
    readonly property color background: palette.background || "transparent"
    readonly property color surface: palette.surface || "transparent"
    readonly property color foreground: palette.foreground || "transparent"
    readonly property color muted: palette.muted || "transparent"
    readonly property color accent: palette.accent || "transparent"
    readonly property color warning: palette.warning || "transparent"
    readonly property color border: palette.border || "transparent"
    readonly property string fontFamily: "CaskaydiaMono Nerd Font"
    readonly property int fontSize: 12
    readonly property int barHeight: 30

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/dotfiles/theme.json"
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const next = JSON.parse(text()).semantic;
                const roles = ["background", "surface", "foreground", "muted", "accent", "warning", "border"];
                if (!next || !roles.every(role => /^#[0-9a-fA-F]{6}$/.test(next[role])))
                    throw new Error("Missing or invalid semantic theme colors");
                root.palette = next;
            } catch (error) {
                console.error("Theme: keeping last valid palette:", error);
            }
        }
    }
}
