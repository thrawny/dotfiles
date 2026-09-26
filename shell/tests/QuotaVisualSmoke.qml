import QtQuick
import Quickshell
import "../services"
import "../components"

ShellRoot {
    id: root
    property bool loaded: false
    property bool captured: false

    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    function find(item: Item, name: string): Item {
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = root.find(child, name);
            if (found)
                return found;
        }
        return null;
    }
    function hasTail(item: Item, expected: string): bool {
        if (item instanceof Text && item.visible && (item as Text).text === expected)
            return true;
        return item.children.some(child => root.hasTail(child, expected));
    }
    function logosReady(item: Item): bool {
        if (item instanceof ProviderIcon && (item as ProviderIcon).status !== Image.Ready)
            return false;
        return item.children.every(child => root.logosReady(child));
    }
    function checkText(item: Item): bool {
        if (item instanceof Text && item.visible) {
            const label = item as Text;
            if (label.contentWidth > label.width + 1) {
                fail("Clipped quota label: " + label.text);
                return false;
            }
        }
        for (const child of item.children) {
            if (!root.checkText(child))
                return false;
        }
        return true;
    }
    Component.onCompleted: {
        Quota.polling = false;
        Quota.command = ["cat", Quickshell.env("QUOTA_FIXTURE")];
        Quota.refresh();
    }
    Connections {
        target: Quota
        function onRefreshed() {
            if (Quota.error) {
                root.fail(Quota.error);
                return;
            }
            root.loaded = true;
            details.open();
        }
    }
    FloatingWindow {
        visible: true
        implicitWidth: 600
        implicitHeight: 950
        Row {
            anchors.bottom: parent.bottom
            QuotaButton {
                id: claudeButton
                providerId: "claude"
                compact: true
            }
            QuotaButton {
                id: codexButton
                providerId: "codex"
                compact: true
            }
        }
        QuotaDetails {
            id: details
            providerId: "claude"
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: root.loaded && !root.captured
        onTriggered: {
            const claude = root.find(details.contentItem, "quota-card-claude") as QuotaProviderCard;
            const codex = root.find(details.contentItem, "quota-card-codex") as QuotaProviderCard;
            const claudeLogo = root.find(details.contentItem, "quota-logo-claude") as ProviderIcon;
            const codexLogo = root.find(details.contentItem, "quota-logo-codex") as ProviderIcon;
            if (!claude || !codex || !claudeLogo || !codexLogo || claudeLogo.status !== Image.Ready || codexLogo.status !== Image.Ready)
                return;
            if (codex.y < claude.y + claude.height || !claude.selected || codex.selected || details.width < 320 || details.width > 380) {
                root.fail("Quota cards do not preserve stacked layout/selection or natural popup width: " + details.width);
                return;
            }
            if (!root.logosReady(claudeButton.contentItem) || !root.logosReady(codexButton.contentItem))
                return;
            if (!root.hasTail(claudeButton.contentItem, "33% 3h") || !root.hasTail(codexButton.contentItem, "94% 1h")) {
                root.fail("Compact quota indicator dropped weekly/reset details");
                return;
            }
            if (!root.checkText(details.contentItem) || !root.checkText(claudeButton.contentItem) || !root.checkText(codexButton.contentItem))
                return;
            root.captured = true;
            details.contentItem.parent.grabToImage(result => {
                if (!result.saveToFile(Quickshell.env("QUOTA_SCREENSHOT"))) {
                    root.fail("Could not capture quota popup");
                    return;
                }
                codex.activated();
                if (details.selectedProvider !== "codex" || !details.visible || !codex.selected || claude.selected) {
                    root.fail("First card click did not select the provider");
                    return;
                }
                codex.activated();
                if (details.visible) {
                    root.fail("Second card click did not close the popup");
                    return;
                }
                console.log("Quota popup verified at " + details.width + " × " + details.height);
                Qt.exit(0);
            });
        }
    }
    Timer {
        running: true
        interval: 5000
        onTriggered: root.fail("Quota popup did not load both SVG icons")
    }
}
