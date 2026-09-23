pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services"
import "../../components/PickerKeys.js" as PickerKeys

Item {
    id: panel
    property real selectedSeq: -1
    property string confirmation: ""
    property bool renaming: false
    property real renameSeq: -1
    readonly property var selected: Agents.rows.find(thread => thread.seq === selectedSeq) || null
    onVisibleChanged: {
        if (visible) {
            confirmation = "";
            renaming = false;
            ensureSelection();
            Qt.callLater(() => content.forceActiveFocus());
        }
    }
    Connections {
        target: Agents
        function onRowsChanged() {
            panel.ensureSelection();
        }
    }
    function ensureSelection(): void {
        if (renaming && !Agents.threads.some(thread => thread.seq === renameSeq)) {
            renaming = false;
            renameSeq = -1;
            Agents.message = "Rename cancelled because the thread disappeared.";
            content.forceActiveFocus();
        }
        let index = Agents.rows.findIndex(thread => thread.seq === selectedSeq);
        if (index < 0) {
            index = 0;
            selectedSeq = Agents.rows.length ? Agents.rows[0].seq : -1;
        }
        results.currentIndex = index;
    }
    function select(delta: int): void {
        if (!Agents.rows.length)
            return;
        const index = (results.currentIndex + delta + Agents.rows.length) % Agents.rows.length;
        selectedSeq = Agents.rows[index].seq;
        confirmation = "";
        ensureSelection();
    }
    function reorder(delta: int): void {
        if (!selected || selected.lifecycle !== "active")
            return;
        const active = Agents.rows.filter(thread => thread.lifecycle === "active");
        const index = active.findIndex(thread => thread.seq === selectedSeq);
        const neighbor = active[index + delta];
        if (neighbor)
            Agents.perform({
                action: "reorder",
                seq: selectedSeq,
                neighbor: neighbor.seq
            });
    }
    function saveRename(title: string): void {
        if (!renaming)
            return;
        if (title.trim() && Agents.threads.some(thread => thread.seq === renameSeq))
            Agents.perform({
                action: "rename",
                seq: renameSeq,
                title: title
            });
        renaming = false;
        content.forceActiveFocus();
    }
    function act(verb: string): void {
        if (Agents.busy)
            return;
        if (verb === "new") {
            Agents.close();
            Qt.callLater(() => Agents.perform({
                    action: "new"
                }));
            return;
        }
        if (verb === "delete-all-archived") {
            if (confirmation !== verb) {
                confirmation = verb;
                Agents.message = "Delete ALL archived threads from every area? Press Shift+D again.";
                return;
            }
            Agents.perform({
                action: verb,
                confirmed: true
            });
        } else {
            if (!selected)
                return;
            if (verb === "rename") {
                renameSeq = selectedSeq;
                renaming = true;
                rename.text = "";
                rename.forceActiveFocus();
                return;
            }
            if (verb === "delete" && selected.lifecycle !== "archived") {
                Agents.message = "Only archived threads can be deleted.";
                return;
            }
            const key = verb + ":" + selectedSeq;
            if ((verb === "archive" && selected.lifecycle !== "archived") || verb === "delete") {
                if (confirmation !== key) {
                    confirmation = key;
                    Agents.message = verb === "archive" ? "Archive closes this thread's window. Press A again." : "Permanently hide this archived thread? Press D again.";
                    return;
                }
            }
            const request = {
                action: verb,
                seq: selectedSeq
            };
            if (verb === "archive" || verb === "delete")
                request.confirmed = true;
            if (verb === "summon") {
                Agents.close();
                // Release the layer's keyboard grab before asking the compositor
                // to focus the terminal, as the GTK sidebar did.
                Qt.callLater(() => Agents.perform(request));
            } else {
                Agents.perform(request);
            }
        }
        confirmation = "";
    }

    Rectangle {
        width: 1
        height: parent.height
        color: Theme.border
    }
    FocusScope {
        id: content
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const direction = PickerKeys.direction(event.key, event.modifiers);
            const shift = event.modifiers & Qt.ShiftModifier;
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q)
                Agents.close();
            else if (shift && (event.key === Qt.Key_J || event.key === Qt.Key_K))
                panel.reorder(event.key === Qt.Key_J ? 1 : -1);
            else if (direction)
                panel.select(direction);
            else if (event.key === Qt.Key_J || event.key === Qt.Key_K)
                panel.select(event.key === Qt.Key_J ? 1 : -1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                panel.act("summon");
            else if (event.key === Qt.Key_S)
                panel.act("settle");
            else if (event.key === Qt.Key_A)
                panel.act("archive");
            else if (event.key === Qt.Key_D)
                panel.act(shift ? "delete-all-archived" : "delete");
            else if (event.key === Qt.Key_M)
                panel.act("read");
            else if (event.key === Qt.Key_R)
                panel.act("rename");
            else if (event.key === Qt.Key_N)
                panel.act("new");
            else if (event.key === Qt.Key_G)
                Agents.globalScope = !Agents.globalScope;
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                Agents.settledExpanded = !Agents.settledExpanded;
            else if (event.key === Qt.Key_Z)
                Agents.archivedExpanded = !Agents.archivedExpanded;
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && Agents.rows.length > event.key - Qt.Key_1) {
                panel.selectedSeq = Agents.rows[event.key - Qt.Key_1].seq;
                panel.ensureSelection();
            } else
                return;
            event.accepted = true;
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Agents"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                }
                Item {
                    Layout.fillWidth: true
                }
                AgentButton {
                    text: "+ New"
                    onClicked: panel.act("new")
                }
                AgentButton {
                    text: "×"
                    onClicked: Agents.close()
                }
            }
            AgentButton {
                text: Agents.globalScope || !Agents.focusedArea ? "All areas · G" : Agents.focusedArea + " · G for all areas"
                onClicked: Agents.globalScope = !Agents.globalScope
            }
            RowLayout {
                AgentButton {
                    text: "Settled " + Agents.scopedCounts.settled + (Agents.settledExpanded ? " ▾" : " ▸")
                    onClicked: Agents.settledExpanded = !Agents.settledExpanded
                }
                AgentButton {
                    text: "Archived " + Agents.scopedCounts.archived + (Agents.archivedExpanded ? " ▾" : " ▸")
                    onClicked: Agents.archivedExpanded = !Agents.archivedExpanded
                }
            }
            Text {
                Layout.fillWidth: true
                visible: Agents.stale || Agents.error !== ""
                text: Agents.error || "Agent state is stale. Reconnecting…"
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.warning
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            TextField {
                id: rename
                Layout.fillWidth: true
                visible: panel.renaming
                placeholderText: "New title · Enter save · Esc cancel"
                color: Theme.foreground
                placeholderTextColor: Theme.muted
                font.family: Theme.fontFamily
                background: Rectangle {
                    color: Theme.surface
                    radius: 4
                }
                onAccepted: panel.saveRename(text)
                Keys.onEscapePressed: event => {
                    panel.renaming = false;
                    content.forceActiveFocus();
                    event.accepted = true;
                }
            }
            ListView {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 5
                model: Agents.rows
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: results.width
                    height: 100
                    radius: 4
                    color: panel.selectedSeq === modelData.seq ? Theme.surface : "transparent"
                    border.color: panel.selectedSeq === modelData.seq ? Theme.border : "transparent"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: (row.index < 9 ? (row.index + 1) + "  " : "") + row.modelData.harness
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                text: row.modelData.lifecycle !== "active" ? row.modelData.lifecycle + " · " + Agents.elapsed(row.modelData.settled_at || row.modelData.state_updated) : row.modelData.attention + " · " + Agents.elapsed(row.modelData.state_updated)
                                color: ["input", "approval"].includes(row.modelData.attention) ? Theme.warning : row.modelData.attention === "done" ? Theme.accent : Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                        Text {
                            Layout.fillWidth: true
                            text: [row.modelData.area, row.modelData.repo, row.modelData.branch, row.modelData.cold ? "cold" : row.modelData.parked ? "parked" : ""].filter(Boolean).join(" · ")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            panel.selectedSeq = row.modelData.seq;
                            panel.confirmation = "";
                            panel.ensureSelection();
                            content.forceActiveFocus();
                        }
                        onDoubleClicked: panel.act("summon")
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: results.count === 0
                    text: Agents.available ? "No threads in this area" : "Waiting for agent-switch…"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: ["summon", "settle", "archive", "read", "rename", "delete"]
                    AgentButton {
                        required property string modelData
                        text: modelData
                        enabled: panel.selected !== null && !Agents.busy
                        onClicked: panel.act(modelData)
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: Agents.message
                textFormat: Text.PlainText
                visible: text !== ""
                wrapMode: Text.Wrap
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            Text {
                Layout.fillWidth: true
                text: "Enter summon · S settle · A archive · M read · R rename\nJ/K move · Shift+J/K reorder · 1–9 select\nTab settled · Z archived · D delete · Shift+D delete all"
                wrapMode: Text.Wrap
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
