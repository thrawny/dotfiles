import QtQuick
import Quickshell
import "../services"
import "../components"

ShellRoot {
    id: root
    property int stage: 0
    readonly property string scenario: Quickshell.env("QUOTA_TEST_CASE")
    readonly property string fixture: Quickshell.env("QUOTA_FIXTURE")

    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    Component.onCompleted: {
        Quota.polling = false;
        // No provider executable or credentials are used by this test.
        Quota.command = ["cat", fixture];
        Quota.refresh();
    }
    Connections {
        target: Quota
        function onRefreshed() {
            if (root.stage === 0) {
                if (Quota.error || !Quota.provider("claude")?.available || Quota.provider("codex")?.available) {
                    root.fail("Valid provider snapshot was not loaded");
                    return;
                }
                root.stage = 1;
                details.open();
                if (root.scenario === "invalid")
                    Quota.command = ["printf", "{bad json"];
                else if (root.scenario === "version")
                    Quota.command = ["printf", "{\"schema_version\":2,\"providers\":[]}"];
                else if (root.scenario === "exit")
                    Quota.command = ["false"];
                else
                    Quota.command = ["/nonexistent/dotfiles-quotabar-test"];
                Qt.callLater(Quota.refresh);
            } else {
                if (!Quota.error || Quota.provider("claude")?.summary !== "72% 33% 5h")
                    root.fail("A failed refresh discarded last known quotas or hid the failure");
                else
                    Qt.exit(0);
            }
        }
    }
    FloatingWindow {
        visible: true
        implicitWidth: 480
        implicitHeight: 700
        QuotaDetails {
            id: details
            providerId: "claude"
        }
    }
    Timer {
        running: true
        interval: 5000
        onTriggered: root.fail("Quota integration timed out")
    }
}
