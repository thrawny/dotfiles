import QtQuick
import Quickshell.Io
import "../services"

Item {
    id: root
    required property string providerId
    property color color: Theme.foreground
    property int iconSize: 20
    property string svg: ""
    readonly property string assetName: providerId === "claude" ? "claude" : "openai"
    implicitWidth: iconSize
    implicitHeight: iconSize
    readonly property int status: image.status
    Image {
        id: image
        anchors.fill: parent
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        fillMode: Image.PreserveAspectFit
        source: root.svg ? "data:image/svg+xml," + encodeURIComponent(root.svg.replace(/currentColor/g, root.color.toString())) : ""
    }
    FileView {
        path: Qt.resolvedUrl("../assets/" + root.assetName + ".svg").toString()
        blockLoading: true
        onLoaded: root.svg = text()
    }
}
