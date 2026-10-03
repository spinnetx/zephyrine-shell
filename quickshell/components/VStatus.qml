import QtQuick
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "../"
import "../services"

// Статус-иконки для вертикальной панели: те же StatusItem, что в StatusIcons, но в колонку и без подписей (значения —
// в подсказках и hover-попапах). Данные/условия видимости дублируют StatusIcons - при правках менять оба файла.
Pill {
    id: root

    horizontalPadding: 0
    implicitWidth: Config.pillHeight + 8
    implicitHeight: col.implicitHeight + 8

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    readonly property var bat: UPower.displayDevice
    readonly property bool batCharging: bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged
    readonly property bool batCritical: !batCharging && bat.percentage < Config.batteryCritical

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    Column {
        id: col
        anchors.centerIn: parent
        spacing: 2

        StatusItem {
            visible: Kbd.layout !== ""
            icon: Config.icons.keyboard
            iconTint: Colors.tertiary
            tooltip: "Раскладка: " + Kbd.layout
        }

        StatusItem {
            visible: root.sink !== null
            icon: root.muted ? Config.icons.volMute : root.vol > 0.66 ? Config.icons.volHigh : root.vol > 0.33 ? Config.icons.volMed : root.vol > 0 ? Config.icons.volLow : Config.icons.volOff
            iconTint: root.muted ? Colors.fgVariant : Colors.primary
            popout: "audio"
            tooltip: (root.sink?.description ?? "") + " " + Math.round(root.vol * 100) + "%" + (root.muted ? "\nЗвук выключен" : "")
            onClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
            onScrolled: delta => {
                if (!root.sink?.audio)
                    return;
                const v = root.sink.audio.volume + (delta > 0 ? Config.volumeStep : -Config.volumeStep);
                root.sink.audio.volume = Math.max(0, Math.min(Config.volumeMax, v));
            }
        }

        StatusItem {
            icon: Net.kind === "ethernet" ? Config.icons.ethernet
                : Net.kind === "wifi" ? (Net.signal > 75 ? Config.icons.wifi4 : Net.signal > 50 ? Config.icons.wifi3 : Net.signal > 25 ? Config.icons.wifi2 : Config.icons.wifi1)
                : Config.icons.wifiOff
            iconTint: Net.kind === "none" ? Colors.fgVariant : Colors.tertiary
            popout: "wifi"
            tooltip: Net.kind === "wifi" ? "Wi-Fi: " + Net.ssid + " (" + Net.signal + "%)"
                : Net.kind === "ethernet" ? "Ethernet" : "Нет сети"
        }

        StatusItem {
            visible: root.btAdapter !== null
            icon: !(root.btAdapter?.enabled) ? Config.icons.btOff : root.btConnected.length > 0 ? Config.icons.btConnected : Config.icons.bt
            iconTint: root.btAdapter?.enabled ? Colors.primary : Colors.fgVariant
            popout: "bluetooth"
            tooltip: !(root.btAdapter?.enabled) ? "Bluetooth выключен"
                : root.btConnected.length > 0 ? root.btConnected.map(d => d.name).join("\n") : "Bluetooth включён"
            onClicked: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
        }

        StatusItem {
            visible: root.bat.isPresent
            icon: root.batCharging ? Config.icons.batteryCharging : root.batCritical ? Config.icons.batteryLow : Config.icons.battery
            iconTint: root.batCritical ? Colors.error : root.batCharging ? Colors.success : Colors.primary
            popout: "battery"
            tooltip: (root.batCharging ? "Заряжается " : "От батареи ") + Math.round(root.bat.percentage * 100) + "%"
        }
    }
}
