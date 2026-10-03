import QtQuick
import Quickshell.Services.UPower
import "../"

// Батарея отдельной пилюлей: значок и процент. Скрыта, если батареи нет. Попап — kind "battery" (с режимами питания).
Pill {
    id: root

    readonly property var bat: UPower.displayDevice
    readonly property bool shown: bat.isPresent
    readonly property bool charging: bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged
    readonly property bool critical: !charging && bat.percentage < Config.batteryCritical

    visible: shown
    spacing: 6
    tooltip: charging ? "Заряжается" : "От батареи"

    PopoutTrigger {
        parent: root
        kind: "battery"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: root.charging ? Config.icons.batteryCharging : root.critical ? Config.icons.batteryLow : Config.icons.battery
        color: root.critical ? Colors.error : root.charging ? Colors.success : Colors.primary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.bat.percentage * 100) + "%"
        color: root.critical ? Colors.error : Colors.fg
    }
}
