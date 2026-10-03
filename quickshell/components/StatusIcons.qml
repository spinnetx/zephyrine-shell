import QtQuick
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "../"
import "../services"

// Статус-иконки одной пилюлей: раскладка, звук, сеть, bluetooth, батарея.
Pill {
    id: root

    spacing: 12

    // --- звук ---
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // --- батарея ---
    readonly property var bat: UPower.displayDevice
    readonly property bool batCharging: bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged
    readonly property bool batCritical: !batCharging && bat.percentage < Config.batteryCritical

    // --- bluetooth ---
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    StatusItem {
        anchors.verticalCenter: parent.verticalCenter
        visible: Kbd.layout !== ""
        icon: Config.icons.keyboard
        iconTint: Colors.tertiary
        label: Kbd.abbr
        tooltip: "Раскладка: " + Kbd.layout
    }

    StatusItem {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.sink !== null
        icon: root.muted ? Config.icons.volMute : root.vol > 0.66 ? Config.icons.volHigh : root.vol > 0.33 ? Config.icons.volMed : root.vol > 0 ? Config.icons.volLow : Config.icons.volOff
        label: Math.round(root.vol * 100) + "%"
        tint: root.muted ? Colors.fgVariant : Colors.fg
        iconTint: root.muted ? Colors.fgVariant : Colors.primary
        popout: "audio"
        tooltip: (root.sink?.description ?? "") + (root.muted ? "\nЗвук выключен" : "")
        onClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
        onScrolled: delta => {
            if (!root.sink?.audio)
                return;
            const v = root.sink.audio.volume + (delta > 0 ? Config.volumeStep : -Config.volumeStep);
            root.sink.audio.volume = Math.max(0, Math.min(Config.volumeMax, v));
        }
    }

    StatusItem {
        anchors.verticalCenter: parent.verticalCenter
        icon: Net.kind === "ethernet" ? Config.icons.ethernet
            : Net.kind === "wifi" ? (Net.signal > 75 ? Config.icons.wifi4 : Net.signal > 50 ? Config.icons.wifi3 : Net.signal > 25 ? Config.icons.wifi2 : Config.icons.wifi1)
            : Config.icons.wifiOff
        iconTint: Net.kind === "none" ? Colors.fgVariant : Colors.tertiary
        popout: "wifi"
        tooltip: Net.kind === "wifi" ? "Wi-Fi: " + Net.ssid + " (" + Net.signal + "%)"
            : Net.kind === "ethernet" ? "Ethernet" : "Нет сети"
    }

    StatusItem {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.btAdapter !== null
        icon: !(root.btAdapter?.enabled) ? Config.icons.btOff : root.btConnected.length > 0 ? Config.icons.btConnected : Config.icons.bt
        iconTint: root.btAdapter?.enabled ? Colors.primary : Colors.fgVariant
        popout: "bluetooth"
        tooltip: !(root.btAdapter?.enabled) ? "Bluetooth выключен"
            : root.btConnected.length > 0 ? root.btConnected.map(d => d.name).join("\n") : "Bluetooth включён"
        onClicked: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
    }

    StatusItem {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.bat.isPresent
        icon: root.batCharging ? Config.icons.batteryCharging : root.batCritical ? Config.icons.batteryLow : Config.icons.battery
        label: Math.round(root.bat.percentage * 100) + "%"
        tint: root.batCritical ? Colors.error : Colors.fg
        iconTint: root.batCritical ? Colors.error : root.batCharging ? Colors.success : Colors.primary
        popout: "battery"
        tooltip: root.batCharging ? "Заряжается" : "От батареи"
    }
}
