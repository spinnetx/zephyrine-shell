import QtQuick
import Quickshell.Bluetooth
import "../"

// Bluetooth отдельной пилюлей: значок (и число подключённых устройств). Попап — kind "bluetooth"; клик — вкл/выкл адаптер.
Pill {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)
    readonly property bool shown: adapter !== null

    visible: shown
    clickable: true
    spacing: 6
    onClicked: if (adapter) adapter.enabled = !adapter.enabled

    PopoutTrigger {
        parent: root
        kind: "bluetooth"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: !(root.adapter?.enabled) ? Config.icons.btOff : root.connected.length > 0 ? Config.icons.btConnected : Config.icons.bt
        color: root.adapter?.enabled ? Colors.primary : Colors.fgVariant
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.connected.length > 0
        text: String(root.connected.length)
    }
}
