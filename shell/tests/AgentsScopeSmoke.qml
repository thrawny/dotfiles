import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: root
    property bool handled: false
    function fail(message: string): void {
        console.error(message);
        Qt.exit(1);
    }
    function check(): void {
        if (handled || !Agents.scopeLoaded)
            return;
        handled = true;
        const expected = Quickshell.env("AGENTS_EXPECT_SCOPE") === "true";
        if (Agents.globalScope !== expected) {
            fail("Scope preference was not restored before use");
            return;
        }
        if (Quickshell.env("AGENTS_SET_SCOPE"))
            Agents.globalScope = Quickshell.env("AGENTS_SET_SCOPE") === "true";
        const choice = Agents.globalScope;
        Agents.close();
        Agents.opened = true;
        if (Agents.globalScope !== choice) {
            fail("Closing the sidebar discarded scope");
            return;
        }
        finish.start();
    }
    Component.onCompleted: {
        Agents.polling = false;
        Agents.snapshotCommand = ["false"];
        check();
    }
    Connections {
        target: Agents
        function onScopeLoadedChanged() {
            root.check();
        }
    }
    Timer {
        id: finish
        interval: 100
        onTriggered: {
            if (Agents.preferenceError)
                root.fail(Agents.preferenceError);
            else
                Qt.exit(0);
        }
    }
    Timer {
        running: true
        interval: 3000
        onTriggered: root.fail("Scope preferences timed out")
    }
}
