import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// Offscreen fixture. Test-owned cliphist and wl-copy tools cannot access Wayland.
ShellRoot {
    id: root
    readonly property string scenario: Quickshell.env("CLIPBOARD_TEST_CASE")
    property int stage: 0
    property int copies: 0
    property string selectedId: ""

    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    function advance(): void {
        if (Clipboard.error) {
            root.fail(Clipboard.error);
            return;
        }
        if (stage === 0 && !Clipboard.busy && Clipboard.entries.length) {
            const images = Clipboard.entries.filter(item => item.imageFormat);
            if (images.length !== 2) {
                fail("Expected PNG and GIF image rows");
                return;
            }
            selectedId = images.find(item => item.imageFormat === "png").id;
            stage = 1;
            if (scenario === "preview") {
                Clipboard.requestPreview(selectedId);
            } else {
                Clipboard.copy(selectedId);
                if (scenario === "cancel" || scenario === "replace")
                    cancelTimer.start();
            }
        } else if (stage === 3 && !Clipboard.busy && !Clipboard.imagesPending) {
            if (copies !== (scenario === "copy" ? 1 : 0) || Quickshell.clipboardText !== "unchanged")
                fail("Image action changed QString clipboard or emitted a stale copy");
            else
                Qt.exit(0);
        } else if (stage === 4 && !Clipboard.busy && Clipboard.entries.length) {
            stage = 5;
            Clipboard.requestPreview(selectedId);
        }
    }
    Image {
        source: Clipboard.imageSources[root.selectedId] || ""
        asynchronous: true
        cache: false
        sourceSize: Qt.size(84, 84)
        onStatusChanged: {
            if (status === Image.Error) {
                root.fail("Qt could not load the image thumbnail");
            } else if (status === Image.Ready && (root.stage === 1 || root.stage === 5) && root.scenario !== "copy") {
                root.stage = 3;
                Clipboard.active = false;
                Qt.callLater(root.advance);
            }
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
        function onImagesPendingChanged() {
            Qt.callLater(root.advance);
        }
        function onEntriesChanged() {
            Qt.callLater(root.advance);
        }
        function onErrorChanged() {
            Qt.callLater(root.advance);
        }
        function onCopied() {
            root.copies++;
            if (root.scenario !== "copy") {
                root.fail("Cancelled image selection reached the clipboard");
                return;
            }
            root.stage = 3;
            Clipboard.active = false;
            Qt.callLater(root.advance);
        }
    }
    FileView {
        id: decodeStarted
        path: Quickshell.env("IMAGE_DECODE_MARKER")
        onLoaded: {
            if (root.stage !== 1 || !cancelTimer.running)
                return;
            cancelTimer.stop();
            root.stage = root.scenario === "replace" ? 4 : 3;
            Clipboard.active = false;
            if (root.scenario === "replace")
                Clipboard.active = true;
            Qt.callLater(root.advance);
        }
    }
    Timer {
        id: cancelTimer
        interval: 50
        repeat: true
        onTriggered: decodeStarted.reload()
    }
    Timer {
        interval: 8000
        running: true
        onTriggered: root.fail("Image clipboard integration timed out")
    }
}
