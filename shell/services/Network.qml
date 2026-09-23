pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "NetworkStats.js" as Stats

Singleton {
    id: root
    readonly property var connectedDevices: Networking.devices.values.filter(device => device.connected)
    readonly property var connections: connectedDevices.reduce((all, device) => all.concat(device.networks.values.filter(network => network.connected)), [])
    readonly property bool connected: connectedDevices.length > 0
    readonly property string name: connections.length ? connections[0].name : connected ? connectedDevices[0].name : "Offline"
    readonly property var wifi: connections.find(network => network instanceof WifiNetwork) ?? null
    readonly property string icon: !connected ? "󰤮" : !wifi ? "󰀂" : ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.min(4, Math.floor(wifi.signalStrength * 5))]
    property string frequency: ""
    property string throughput: ""
    property var previous: ({})
    property double sampledAt: 0
    readonly property string details: !connected ? "Disconnected" : name + (frequency ? " · " + frequency : "") + (throughput ? "\n" + throughput : "")
    FileView {
        id: counters
        path: "/proc/net/dev"
        onLoaded: {
            const now = Date.now();
            const next = Stats.counters(text(), root.connectedDevices.map(device => device.name));
            const rates = Stats.rates(root.previous, next, (now - root.sampledAt) / 1000);
            root.throughput = "↓ " + Stats.bytes(rates.rx) + "  ↑ " + Stats.bytes(rates.tx);
            root.previous = next;
            root.sampledAt = now;
        }
    }
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: counters.reload()
    }
    Timer {
        interval: 15000
        running: root.wifi !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!radio.running)
                radio.running = true;
        }
    }
    onWifiChanged: {
        if (!wifi)
            frequency = "";
    }
    Process {
        id: radio
        property bool completed: false
        onRunningChanged: {
            if (running)
                completed = false;
            else if (!completed)
                failure();
        }
        command: ["nmcli", "--terse", "--fields", "IN-USE,FREQ", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            id: radioOutput
            waitForEnd: true
        }
        stderr: StdioCollector {}
        function failure(): void {
            root.frequency = "";
        }
        // qmllint disable signal-handler-parameters
        onExited: (code, status) => {
            completed = true;
            const active = radioOutput.text.split("\n").find(line => line.startsWith("*:"));
            root.frequency = root.wifi && code === 0 && status === 0 && active ? (parseFloat(active.slice(2)) / 1000).toFixed(3) + " GHz" : "";
        }
    }
}
