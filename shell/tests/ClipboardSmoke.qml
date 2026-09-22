import QtQuick
import Quickshell
import "../services"

// Runs with Qt's offscreen platform and an isolated cliphist database.
// It never connects to the real Wayland clipboard.
ShellRoot {
    id: root
    property int stage: 0
    property int copies: 0
    property string selectedId: ""
    readonly property string scenario: Quickshell.env("CLIPBOARD_TEST_CASE") || "roundtrip"
    readonly property string expected: "  Clipboard fixture 🙂\nsecond line\n\n"

    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    function advance(): void {
        if (Clipboard.busy)
            return;
        if (Clipboard.error) {
            if (scenario === "broken-db" && Clipboard.error === "Could not read clipboard history.")
                Qt.exit(0);
            else
                fail(Clipboard.error);
            return;
        }
        if (stage === 0) {
            if (scenario === "empty") {
                if (Clipboard.entries.length !== 0)
                    fail("Expected an empty history");
                else
                    Qt.exit(0);
                return;
            }
            if (Clipboard.entries.length !== 1) {
                fail("Expected one text entry, got " + Clipboard.entries.length);
                return;
            }
            selectedId = Clipboard.entries[0].id;
            stage = 1;
            Clipboard.copy(selectedId);
            if (scenario === "cancel") {
                stage = 3;
                Clipboard.active = false;
            }
        } else if (stage === 2) {
            if (Clipboard.entries.length !== 0)
                fail("Deleted text entry still appears");
            else
                Qt.exit(0);
        } else if (stage === 3) {
            if (copies !== 0 || Quickshell.clipboardText !== "unchanged")
                fail("A cancelled request changed the clipboard");
            else
                Qt.exit(0);
        }
    }
    Component.onCompleted: {
        Quickshell.clipboardText = "unchanged";
        Clipboard.active = true;
    }
    Connections {
        target: Clipboard
        function onBusyChanged() {
            Qt.callLater(root.advance);
        }
        function onErrorChanged() {
            Qt.callLater(root.advance);
        }
        function onCopied() {
            root.copies++;
            if (Quickshell.clipboardText !== root.expected) {
                root.fail("Clipboard text lost whitespace or Unicode");
                return;
            }
            root.stage = 2;
            Clipboard.remove(root.selectedId);
        }
    }
    Timer {
        running: true
        interval: 5000
        onTriggered: root.fail("Clipboard integration timed out")
    }
}
