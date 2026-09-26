pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../../components"
import "../../services"
import "../../services/WorkspaceOrder.js" as Order

Flickable {
    id: root
    required property var screen
    readonly property bool compact: (screen?.name || "").startsWith("eDP") || (screen?.width || 1920) <= 1200
    readonly property real outerPadding: compact ? 2 : 5
    readonly property real verticalPadding: compact ? 1 : 3
    readonly property real buttonMargin: compact ? 0 : 1
    readonly property var workspaceColors: Theme.applications.waybar || ({})
    readonly property color foreground: workspaceColors.fg || Theme.foreground
    readonly property color muted: workspaceColors.muted || Theme.muted
    readonly property color surface: workspaceColors.surface || Theme.surface
    readonly property color accent: workspaceColors.accent || Theme.accent
    readonly property color accentAlt: workspaceColors.accentAlt || Theme.accent
    readonly property color onAccent: workspaceColors.onAccent || Theme.background
    readonly property color urgentForeground: workspaceColors.urgentFg || Theme.foreground
    readonly property color urgentBackground: workspaceColors.urgentBg || Theme.warning
    contentWidth: row.width + 2 * (outerPadding + buttonMargin)
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.HorizontalFlick

    function translucent(value: color, opacity: real): color {
        return Qt.rgba(value.r, value.g, value.b, opacity);
    }
    function revealFocused(): void {
        for (let i = 0; i < buttons.count; i++) {
            const button = buttons.itemAt(i) as BarButton;
            if (button && button.selected) {
                const left = row.x + button.x;
                const desired = Math.max(left + button.width - width, Math.min(contentX, left));
                contentX = Math.max(0, Math.min(Math.max(0, contentWidth - width), desired));
                break;
            }
        }
    }
    onWidthChanged: Qt.callLater(revealFocused)
    onContentWidthChanged: Qt.callLater(revealFocused)
    Connections {
        target: Workspaces
        function onFocusedChanged() {
            Qt.callLater(root.revealFocused);
        }
    }
    Row {
        id: row
        x: root.outerPadding + root.buttonMargin
        y: root.verticalPadding
        spacing: root.buttonMargin * 2
        Repeater {
            id: buttons
            model: Workspaces.onScreen(root.screen)
            BarButton {
                id: workspaceButton
                required property var modelData
                required property int index
                readonly property string key: Order.shortcut(Workspaces.items.findIndex(workspace => workspace.id === modelData.id))
                text: (key ? key + " " : "") + modelData.name
                hint: modelData.name + (key ? " · Alt+" + key : "")
                selected: modelData.active
                readonly property bool focusedWorkspace: modelData.focused ?? selected
                readonly property bool visibleWorkspace: selected && !focusedWorkspace
                implicitHeight: Math.max(0, root.height - root.verticalPadding * 2)
                implicitWidth: Math.min(label.implicitWidth, maxTextWidth) + leftPadding + rightPadding
                leftPadding: root.compact ? 4 : 8
                rightPadding: leftPadding
                topPadding: 2
                bottomPadding: 2
                font.pixelSize: root.compact ? 12 : 13
                font.bold: true
                onSelectedChanged: Qt.callLater(root.revealFocused)
                attention: modelData.urgent ?? false
                maxTextWidth: 160
                onClicked: Workspaces.focus(modelData.id)
                contentItem: Text {
                    id: label
                    text: workspaceButton.text
                    textFormat: Text.PlainText
                    font: workspaceButton.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: workspaceButton.attention ? root.urgentForeground : workspaceButton.visibleWorkspace ? root.accentAlt : workspaceButton.selected ? root.onAccent : workspaceButton.hovered ? root.foreground : root.muted
                }
                background: Rectangle {
                    id: pill
                    radius: 6
                    color: workspaceButton.attention ? root.urgentBackground : workspaceButton.visibleWorkspace ? root.translucent(root.accentAlt, 0.14) : workspaceButton.hovered ? root.translucent(root.surface, 0.62) : "transparent"
                    border.color: workspaceButton.attention ? "transparent" : workspaceButton.visibleWorkspace ? root.translucent(root.accentAlt, 0.24) : workspaceButton.selected ? root.translucent(root.accent, 0.34) : workspaceButton.hovered ? root.translucent(root.foreground, 0.12) : "transparent"
                    Shape {
                        id: gradientFill
                        anchors.fill: parent
                        visible: workspaceButton.selected && workspaceButton.focusedWorkspace && !workspaceButton.attention
                        preferredRendererType: Shape.CurveRenderer
                        // CSS linear-gradient(110deg): project the pill onto a
                        // down/right vector, with the original 42% pink stop.
                        readonly property real directionX: Math.cos(Math.PI / 9)
                        readonly property real directionY: Math.sin(Math.PI / 9)
                        readonly property real extent: width * directionX + height * directionY
                        ShapePath {
                            strokeWidth: 1
                            strokeColor: root.translucent(root.accent, 0.34)
                            fillGradient: LinearGradient {
                                x1: pill.width / 2 - gradientFill.extent * gradientFill.directionX / 2
                                y1: pill.height / 2 - gradientFill.extent * gradientFill.directionY / 2
                                x2: pill.width - x1
                                y2: pill.height - y1
                                GradientStop {
                                    position: 0
                                    color: root.accent
                                }
                                GradientStop {
                                    position: 0.42
                                    color: root.accent
                                }
                                GradientStop {
                                    position: 1
                                    color: root.accentAlt
                                }
                            }
                            PathRectangle {
                                x: 0.5
                                y: 0.5
                                width: Math.max(0, pill.width - 1)
                                height: Math.max(0, pill.height - 1)
                                radius: pill.radius - 0.5
                            }
                        }
                    }
                }
            }
        }
    }
}
