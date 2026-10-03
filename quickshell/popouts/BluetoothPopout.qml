pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import "../"
import "../components"
import "../services"

// Bluetooth: вкл/выкл адаптера, список устройств (подключённые → сопряжённые), клик — connect/disconnect,
// кнопка сканирования (discovering). Новые устройства видны, пока идёт сканирование.
Item {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool active: PopoutState.kind === "bluetooth"
    // Сами запустили сканирование → по закрытию попапа останавливаем.
    property bool startedScan: false

    readonly property var devices: {
        const all = Bluetooth.devices.values;
        const scanning = adapter?.discovering ?? false;
        return all.filter(d => d.connected || d.paired || d.bonded || scanning).sort((a, b) => (b.connected - a.connected) || ((b.paired || b.bonded) - (a.paired || a.bonded)) || a.name.localeCompare(b.name));
    }

    implicitWidth: 300
    implicitHeight: col.implicitHeight

    onActiveChanged: {
        if (!active && startedScan && adapter) {
            adapter.discovering = false;
            startedScan = false;
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Item {
            width: parent.width
            height: 26

            Txt {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                text: !(root.adapter?.enabled) ? Config.icons.btOff : Config.icons.bt
                color: Colors.primary
                font.pixelSize: Config.iconSize + 2
            }
            Txt {
                anchors.left: title.right
                anchors.leftMargin: 8
                anchors.right: sw.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                font.bold: true
                text: !root.adapter ? "Нет адаптера" : !root.adapter.enabled ? "Bluetooth выключен" : "Bluetooth"
            }
            PopSwitch {
                id: sw
                visible: root.adapter !== null
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.adapter?.enabled ?? false
                onToggled: value => {
                    if (root.adapter)
                        root.adapter.enabled = value;
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.35)
        }

        Txt {
            visible: root.adapter?.enabled && root.devices.length === 0
            text: root.adapter?.discovering ? "Поиск устройств…" : "Нет сопряжённых устройств"
            color: Colors.fgVariant
        }

        ListView {
            id: list
            visible: (root.adapter?.enabled ?? false) && root.devices.length > 0
            width: parent.width
            height: visible ? Math.min(contentHeight, 224) : 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices

            delegate: PopItem {
                id: dev

                required property var modelData
                readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting

                width: list.width
                highlighted: modelData.connected
                onClicked: {
                    if (busy)
                        return;
                    if (modelData.connected)
                        modelData.disconnect();
                    else
                        modelData.connect();
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dev.modelData.connected ? Config.icons.btConnected : Config.icons.bt
                    color: dev.modelData.connected ? Colors.primary : Colors.fgVariant
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 150
                    elide: Text.ElideRight
                    text: dev.modelData.name !== "" ? dev.modelData.name : dev.modelData.address
                    font.bold: dev.modelData.connected
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66
                    horizontalAlignment: Text.AlignRight
                    color: dev.modelData.connected ? Colors.success : Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                    text: dev.busy ? (dev.modelData.state === BluetoothDeviceState.Connecting ? "подкл…" : "откл…")
                        : dev.modelData.batteryAvailable ? Config.icons.battery + " " + Math.round(dev.modelData.battery * 100) + "%"
                        : dev.modelData.connected ? "подключено" : ""
                }
            }
        }

        PopItem {
            visible: root.adapter?.enabled ?? false
            width: 140
            onClicked: {
                if (!root.adapter)
                    return;
                root.adapter.discovering = !root.adapter.discovering;
                root.startedScan = root.adapter.discovering;
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.refresh
                color: Colors.tertiary
                font.pixelSize: Config.iconSize
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: root.adapter?.discovering ? "Остановить" : "Сканировать"
            }
        }

        PopItem {
            width: 140
            onClicked: Overlays.openSettings("network/bluetooth")
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.settings
                color: Colors.tertiary
                font.pixelSize: Config.iconSize
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Настройки…"
            }
        }
    }
}
