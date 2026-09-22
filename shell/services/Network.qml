pragma Singleton
import Quickshell
import Quickshell.Networking

Singleton {
    readonly property var connectedDevices: Networking.devices.values.filter(device => device.connected)
    readonly property var connections: connectedDevices.reduce((all, device) => all.concat(device.networks.values.filter(network => network.connected)), [])
    readonly property bool connected: connectedDevices.length > 0
    readonly property string name: connections.length ? connections[0].name : connected ? connectedDevices[0].name : "Offline"
}
