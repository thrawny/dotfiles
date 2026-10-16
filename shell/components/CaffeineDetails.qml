pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../services"

Popup {
    id: root
    popupType: Popup.Window
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    focus: true
    padding: 16
    margins: 8
    width: 360
    height: Math.min(content.implicitHeight + 32, 720)
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    palette.window: Theme.surface
    palette.base: Theme.background
    palette.text: Theme.foreground
    palette.windowText: Theme.foreground
    palette.button: Theme.background
    palette.buttonText: Theme.foreground
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.background
    onOpened: {
        displayAwake.checked = false;
        lidClosed.checked = false;
    }
    function startSession(): void {
        Caffeine.start(mode.currentValue, value.text.trim(), displayAwake.checked, lidClosed.checked);
    }
    background: Rectangle {
        color: Theme.surface
        border.color: Theme.border
        radius: 5
    }
    contentItem: Flickable {
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        ColumnLayout {
            id: content
            width: parent.width
            spacing: 10
            Text {
                text: "Keep awake"
                color: Theme.foreground
                font.family: root.font.family
                font.pixelSize: root.font.pixelSize
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                text: Caffeine.error || Caffeine.actionError || (Caffeine.paused ? "Paused" : Caffeine.active ? (Caffeine.snapshot.reasons || []).join(", ") : "Normal sleep enabled")
                textFormat: Text.PlainText
                color: Caffeine.error || Caffeine.actionError ? Theme.warning : Theme.muted
                font: root.font
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                text: "Stops at " + (Caffeine.snapshot.battery_floor ?? 20) + "% on battery. AC has no battery limit."
                color: Theme.muted
                font: root.font
                wrapMode: Text.Wrap
            }
            ComboBox {
                id: mode
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "kind"
                model: [
                    {
                        label: "Indefinitely",
                        kind: "indefinite"
                    },
                    {
                        label: "For a duration",
                        kind: "duration"
                    },
                    {
                        label: "Until a time",
                        kind: "until"
                    },
                    {
                        label: "While an app runs",
                        kind: "process"
                    },
                    {
                        label: "While a PID runs",
                        kind: "pid"
                    },
                    {
                        label: "While a file downloads",
                        kind: "file"
                    }
                ]
            }
            TextField {
                id: value
                Layout.fillWidth: true
                visible: mode.currentValue !== "indefinite"
                placeholderText: mode.currentValue === "duration" ? "30m or 1h30m" : mode.currentValue === "until" ? "17:00" : mode.currentValue === "process" ? "Process name, e.g. obs" : mode.currentValue === "pid" ? "Process ID" : "Path to existing download file"
                onAccepted: root.startSession()
            }
            Text {
                Layout.fillWidth: true
                visible: mode.currentValue === "file"
                text: "Ends after 60 seconds without file changes, or if the file disappears."
                color: Theme.muted
                font: root.font
                wrapMode: Text.Wrap
            }
            CheckBox {
                id: displayAwake
                text: "Keep screen awake"
            }
            CheckBox {
                id: lidClosed
                text: "Allow closed-lid operation"
            }
            Button {
                text: "Start session"
                enabled: Caffeine.available && !Caffeine.busy && !Caffeine.paused && Caffeine.snapshot.power_allowed === true && (mode.currentValue === "indefinite" || value.text.trim() !== "")
                onClicked: root.startSession()
            }
            RowLayout {
                Repeater {
                    model: ["15m", "30m", "1h", "2h"]
                    delegate: Button {
                        required property string modelData
                        text: modelData
                        enabled: Caffeine.available && !Caffeine.busy && !Caffeine.paused && Caffeine.snapshot.power_allowed === true
                        onClicked: Caffeine.start("duration", modelData, displayAwake.checked, lidClosed.checked)
                    }
                }
            }
            Repeater {
                model: Caffeine.sessions
                delegate: RowLayout {
                    id: sessionRow
                    required property var modelData
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: sessionRow.modelData.name + (sessionRow.modelData.remaining_seconds !== null ? " · " + Math.ceil(sessionRow.modelData.remaining_seconds / 60) + "m" : "")
                        textFormat: Text.PlainText
                        color: Theme.foreground
                        font: root.font
                        elide: Text.ElideRight
                    }
                    Button {
                        text: "End"
                        enabled: !Caffeine.busy
                        onClicked: Caffeine.stop(sessionRow.modelData.id)
                    }
                }
            }
            Repeater {
                model: Caffeine.rules
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: (modelData.active ? "Active: " : "Inactive: ") + modelData.name
                    textFormat: Text.PlainText
                    color: modelData.active ? Theme.accent : Theme.muted
                    font: root.font
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                Button {
                    text: Caffeine.paused ? "Resume" : "Pause all"
                    enabled: Caffeine.available && !Caffeine.busy
                    onClicked: Caffeine.togglePause()
                }
                Button {
                    text: "End manual sessions"
                    enabled: Caffeine.available && !Caffeine.busy && Caffeine.sessions.length > 0
                    onClicked: Caffeine.stop("")
                }
            }
            Button {
                text: "Edit rules"
                enabled: Caffeine.available
                onClicked: Caffeine.editConfig()
            }
        }
    }
}
