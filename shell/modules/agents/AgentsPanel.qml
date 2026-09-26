pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services"
import "../../services/AgentsModel.js" as AgentModel
import "../../components"
import "../../components/PickerKeys.js" as PickerKeys

Item {
    id: panel
    property real selectedSeq: -1
    property string confirmation: ""
    property bool renaming: false
    property real renameSeq: -1
    readonly property var displayRows: AgentModel.displayRows(Agents.rows, Agents.scopedCounts, Agents.settledExpanded, Agents.archivedExpanded)
    onDisplayRowsChanged: Qt.callLater(ensureSelection)
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
        results.currentIndex = displayRows.findIndex(entry => entry.kind === "thread" && entry.thread.seq === selectedSeq);
    }
    function select(delta: int): void {
        if (!Agents.rows.length)
            return;
        const current = Agents.rows.findIndex(thread => thread.seq === selectedSeq);
        const index = (current + delta + Agents.rows.length) % Agents.rows.length;
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
        anchors.fill: parent
        color: Theme.background
    }
    Rectangle {
        anchors.right: parent.right
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
            anchors.margins: 8
            anchors.topMargin: 14
            anchors.bottomMargin: 12
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 6
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: Agents.globalScope || !Agents.focusedArea ? "All areas" : Agents.focusedArea
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.agentScope
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Agents.globalScope = !Agents.globalScope
                    }
                    ToolTip.visible: scopeHover.hovered
                    ToolTip.text: "G · Switch between this area and all areas"
                    HoverHandler {
                        id: scopeHover
                    }
                }
                Text {
                    readonly property int waiting: Agents.counts.approval + Agents.counts.input + Agents.counts.done
                    text: waiting + " waiting · " + Agents.counts.working + " running"
                    color: waiting ? Theme.agentApproval : Theme.agentIdle
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
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
                spacing: 4
                model: panel.displayRows
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool shelf: modelData.kind === "shelf"
                    readonly property var thread: shelf ? null : modelData.thread
                    readonly property bool active: thread !== null && thread.lifecycle === "active"
                    readonly property bool selected: thread !== null && panel.selectedSeq === thread.seq
                    width: results.width
                    height: shelf ? 34 : active ? 88 : 58
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: row.selected ? Theme.agentSelection : rowMouse.containsMouse && !row.shelf ? Theme.surface : "transparent"
                    }
                    RowLayout {
                        visible: row.shelf
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Text {
                            text: row.shelf ? (row.modelData.expanded ? "▾ " : "▸ ") + (row.modelData.lifecycle === "settled" ? "Settled" : "Archived") + " (" + row.modelData.count + ")" : ""
                            color: Theme.agentIdle
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.agentIdle
                            opacity: 0.28
                        }
                    }
                    ColumnLayout {
                        visible: !row.shelf
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: row.active ? 10 : 7
                        anchors.bottomMargin: row.active ? 10 : 7
                        spacing: 2
                        opacity: row.active && !row.selected && ["working", "idle"].includes(row.thread.attention) ? 0.62 : 1
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                visible: !row.shelf && row.modelData.jumpIndex <= 9
                                text: row.shelf ? "" : row.modelData.jumpIndex
                                color: Theme.agentIdle
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.thread ? AgentModel.locationText(row.thread, Agents.globalScope || !Agents.focusedArea) : ""
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                            Text {
                                visible: row.active && row.thread.cold
                                text: "❆"
                                color: Theme.agentIdle
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                            Text {
                                text: row.thread ? AgentModel.statusLabel(row.thread, Agents.now) : ""
                                color: !row.active ? Theme.agentIdle : row.thread.attention === "approval" ? Theme.agentApproval : row.thread.attention === "input" ? Theme.agentInput : row.thread.attention === "working" ? Theme.agentWorking : row.thread.attention === "done" ? Theme.agentDone : Theme.agentIdle
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.bold: row.active && ["approval", "input", "done"].includes(row.thread.attention)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.thread ? row.thread.title : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: row.active ? row.thread.attention === "done" ? Theme.agentDone : Theme.foreground : row.thread && row.thread.lifecycle === "archived" ? Theme.agentIdle : Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: row.active ? 16 : 14
                            font.bold: row.active && row.thread.attention === "done"
                            font.italic: row.thread !== null && row.thread.lifecycle === "archived"
                        }
                        RowLayout {
                            visible: row.active
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: row.thread ? row.thread.branch : ""
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.agentIdle
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                            Text {
                                visible: row.thread !== null && row.thread.parked
                                text: "parked"
                                color: Theme.agentIdle
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                            Item {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                ProviderIcon {
                                    anchors.centerIn: parent
                                    visible: row.thread !== null && ["claude", "codex"].includes(row.thread.harness)
                                    providerId: row.thread ? row.thread.harness : "codex"
                                    color: row.thread && row.thread.harness === "claude" ? Theme.claudeIcon : Theme.agentHarness
                                    iconSize: 14
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.thread !== null && !["claude", "codex"].includes(row.thread.harness)
                                    text: row.thread && row.thread.harness === "pi" ? "π" : "·"
                                    color: Theme.agentHarness
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (row.shelf) {
                                if (row.modelData.lifecycle === "settled")
                                    Agents.settledExpanded = !Agents.settledExpanded;
                                else
                                    Agents.archivedExpanded = !Agents.archivedExpanded;
                                return;
                            }
                            panel.selectedSeq = row.thread.seq;
                            panel.confirmation = "";
                            panel.ensureSelection();
                            content.forceActiveFocus();
                        }
                        onDoubleClicked: {
                            if (!row.shelf)
                                panel.act("summon");
                        }
                    }
                    ToolTip.visible: rowMouse.containsMouse && !row.shelf
                    ToolTip.delay: 700
                    ToolTip.text: row.thread ? [row.thread.title, row.thread.area, row.thread.repo, row.thread.branch, row.thread.harness].filter(Boolean).join("\n") : ""
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
                    model: ["new", "summon", "settle", "archive", "read", "rename", "delete", "close"]
                    AgentButton {
                        required property string modelData
                        text: modelData === "new" ? "+ New" : modelData === "close" ? "× Close" : modelData
                        enabled: ["new", "close"].includes(modelData) || panel.selected !== null && !Agents.busy
                        onClicked: modelData === "close" ? Agents.close() : panel.act(modelData)
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
                text: "Enter summon · S settle · A archive · M read · R rename\nJ/K move · Shift+J/K reorder · 1–9 select\nTab settled · Z archived · D delete · Shift+D delete all\nG scope · N new · Esc close"
                wrapMode: Text.Wrap
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
