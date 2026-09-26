pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../services"
import "../../components/PickerKeys.js" as PickerKeys

Item {
    id: panel
    function focusSearch(): void {
        search.forceActiveFocus();
    }
    Connections {
        target: Launcher
        function onQueryChanged() {
            results.currentIndex = 0;
        }
        function onModeChanged() {
            results.currentIndex = 0;
            Qt.callLater(panel.focusSearch);
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: Launcher.close()
    }
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.min(90, panel.height * 0.1)
        width: Math.min(680, panel.width - 32)
        height: Math.min(550, panel.height - y - 32)
        color: Theme.background
        border.color: Theme.border
        radius: 8
        // Consume clicks in panel padding rather than dismissing through it.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Repeater {
                    model: ["apps", "clipboard", "projects"]
                    Button {
                        id: modeButton
                        required property string modelData
                        text: modelData === "apps" ? "Applications" : modelData === "projects" ? "Projects" : "Clipboard"
                        enabled: !Projects.opening
                        onClicked: {
                            Launcher.setMode(modelData);
                            search.forceActiveFocus();
                        }
                        contentItem: Text {
                            text: modeButton.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: Launcher.mode === modeButton.modelData ? Theme.accent : Theme.muted
                        }
                        background: Item {}
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: "Tab to switch"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
            TextField {
                id: search
                Layout.fillWidth: true
                implicitHeight: 46
                text: Launcher.query
                onTextEdited: Launcher.query = text
                placeholderText: Launcher.worktreeProject ? "Branch name…" : Launcher.enteringPath ? "Directory path…" : Launcher.pickingMode ? "Choose a mode" : Launcher.mode === "apps" ? "Search applications…" : Launcher.mode === "projects" ? "Search projects…" : "Search clipboard history…"
                readOnly: Launcher.mode === "projects" && Projects.opening
                placeholderTextColor: Theme.muted
                color: Theme.foreground
                selectionColor: Theme.accent
                selectedTextColor: Theme.background
                font.family: Theme.fontFamily
                font.pixelSize: 16
                leftPadding: 12
                rightPadding: 12
                background: Rectangle {
                    color: Theme.surface
                    radius: 5
                }
                // Claim shared navigation before the text field handles editing shortcuts.
                Keys.priority: Keys.BeforeItem
                Keys.onShortcutOverride: event => {
                    if (PickerKeys.direction(event.key, event.modifiers) || (Launcher.mode === "projects" && event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_O || event.key === Qt.Key_G)))
                        event.accepted = true;
                }
                Keys.onPressed: event => {
                    const direction = PickerKeys.direction(event.key, event.modifiers);
                    if (event.key === Qt.Key_Escape)
                        Launcher.dismiss();
                    else if ((event.key === Qt.Key_Space && event.modifiers & Qt.MetaModifier) || (event.key === Qt.Key_P && event.modifiers & Qt.AltModifier))
                        Launcher.close();
                    else if (event.key === Qt.Key_O && event.modifiers & Qt.ControlModifier)
                        Launcher.manualPath();
                    else if (event.key === Qt.Key_G && event.modifiers & Qt.ControlModifier)
                        Launcher.beginWorktree(results.currentIndex);
                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                        Launcher.cycleMode();
                    else if (direction)
                        panel.select(direction);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        Launcher.activate(results.currentIndex);
                    else if (event.key === Qt.Key_Delete && event.modifiers & Qt.ControlModifier)
                        Launcher.remove(results.currentIndex);
                    else
                        return;
                    event.accepted = true;
                }
            }
            Text {
                visible: Launcher.worktreeProject !== null || Launcher.enteringPath
                Layout.fillWidth: true
                text: Launcher.worktreeProject ? "New worktree for " + Launcher.worktreeProject.name + "\n" + Launcher.worktreeProject.detail : "Open a directory using an absolute path or ~/"
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            Text {
                visible: Launcher.error !== ""
                Layout.fillWidth: true
                text: Launcher.error
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.warning
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            ListView {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Launcher.results
                currentIndex: 0
                spacing: 3
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                onCountChanged: currentIndex = Math.max(0, Math.min(currentIndex, count - 1))
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string imageSource: modelData.imageFormat ? Clipboard.imageSources[modelData.id] || "" : ""
                    Component.onCompleted: {
                        if (modelData.imageFormat)
                            Clipboard.requestPreview(modelData.id);
                    }
                    width: results.width
                    height: 54
                    radius: 5
                    color: results.currentIndex === index ? Theme.surface : "transparent"
                    Rectangle {
                        width: 2
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.accent
                        visible: results.currentIndex === row.index
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12
                        Item {
                            Layout.preferredWidth: row.modelData.imageFormat ? 42 : 28
                            Layout.preferredHeight: row.modelData.imageFormat ? 42 : 28
                            Image {
                                id: entryIcon
                                anchors.fill: parent
                                source: row.imageSource && !Clipboard.imageErrors[row.modelData.id] ? row.imageSource : row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                                sourceSize: Qt.size(84, 84)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: !row.modelData.imageFormat
                                visible: status === Image.Ready
                                onStatusChanged: {
                                    if (status === Image.Error && row.imageSource)
                                        Clipboard.previewFailed(row.modelData.id);
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !row.modelData.icon || (row.modelData.kind === "project" && entryIcon.status !== Image.Ready)
                                text: row.modelData.kind === "project" ? "" : "󰅍"
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 20
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.imageFormat && Clipboard.imageErrors[row.modelData.id] ? "Preview unavailable · Enter to try copying" : row.modelData.detail
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: results.currentIndex = row.index
                        onClicked: Launcher.activate(row.index)
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: results.count === 0
                    text: Projects.opening ? "Opening project…" : Launcher.enteringPath || Launcher.worktreeProject ? "" : Launcher.busy ? "Loading…" : Launcher.mode === "clipboard" && !Launcher.query ? "Clipboard history is empty" : Launcher.mode === "projects" && !Launcher.query ? "No projects found. Ctrl+O to enter a path." : "No matches"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }
            }
            Text {
                text: Projects.opening ? "Esc close   Running operations will finish" : Launcher.worktreeProject ? "Enter create or reuse   Esc back" : Launcher.enteringPath ? "Enter open   Esc back" : Launcher.mode === "projects" && !Launcher.pickingMode ? "Enter open   Ctrl+G new worktree   Ctrl+O path   Esc close" : Launcher.mode === "clipboard" && !Launcher.pickingMode ? "Enter copy   Ctrl+Delete remove   Esc close" : "Enter launch   ? modes   Esc close"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }
    function select(delta: int): void {
        if (results.count)
            results.currentIndex = (results.currentIndex + delta + results.count) % results.count;
    }
}
