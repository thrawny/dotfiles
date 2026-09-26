pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var palette: ({})
    property var applications: ({})
    readonly property bool ready: Object.keys(palette).length > 0
    readonly property color background: palette.background || "transparent"
    readonly property color surface: palette.surface || "transparent"
    readonly property color foreground: palette.foreground || "transparent"
    readonly property color muted: palette.muted || "transparent"
    readonly property color accent: palette.accent || "transparent"
    readonly property color warning: palette.warning || "transparent"
    readonly property color border: palette.border || "transparent"
    readonly property color quotaBackground: applications.quotabar?.background || background
    readonly property color quotaCard: applications.quotabar?.card || surface
    readonly property color quotaCardHover: applications.quotabar?.cardHover || surface
    readonly property color quotaCardSelected: applications.quotabar?.cardSelected || surface
    readonly property color quotaSubtle: applications.quotabar?.subtle || surface
    readonly property color quotaSurface: applications.quotabar?.surface || surface
    readonly property color quotaElevated: applications.quotabar?.elevated || border
    readonly property color quotaBorder: applications.quotabar?.border || border
    readonly property color quotaText: applications.quotabar?.text || foreground
    readonly property color quotaMuted: applications.quotabar?.muted || muted
    readonly property color quotaAccent: applications.quotabar?.accent || accent
    readonly property color quotaSuccess: applications.quotabar?.success || palette.success || foreground
    readonly property color quotaWarning: applications.quotabar?.warning || warning
    readonly property color claudeIcon: applications.quotabar?.claudeIcon || foreground
    readonly property color codexIcon: applications.quotabar?.codexIcon || muted
    readonly property color agentApproval: palette.warning || foreground
    readonly property color agentInput: palette.accentAlt || foreground
    readonly property color agentWorking: syntax.type || foreground
    readonly property color agentDone: foreground
    readonly property color agentIdle: palette.dim || muted
    readonly property color agentSelection: applications.pi?.selection || surface
    readonly property color agentScope: syntax.function || foreground
    readonly property color agentHarness: palette.accentAlt || foreground
    property var syntax: ({})
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
                const document = JSON.parse(text());
                const next = document.semantic;
                const roles = ["background", "surface", "foreground", "muted", "accent", "warning", "border"];
                if (!next || !roles.every(role => /^#[0-9a-fA-F]{6}$/.test(next[role])))
                    throw new Error("Missing or invalid semantic theme colors");
                root.palette = next;
                root.applications = document.applications || {};
                root.syntax = document.syntax || {};
            } catch (error) {
                console.error("Theme: keeping last valid palette:", error);
            }
        }
    }
}
