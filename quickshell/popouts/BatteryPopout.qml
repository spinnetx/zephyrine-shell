import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "../"
import "../components"
import "../services"

// Батарея: процент, состояние, время до разряда/зарядки, мощность (UPower) и режим питания (power-profiles-daemon).
Item {
    id: root

    readonly property var bat: UPower.displayDevice
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
    readonly property bool full: bat.state === UPowerDeviceState.FullyCharged
    readonly property bool critical: !charging && !full && bat.percentage < Config.batteryCritical

    implicitWidth: 240
    implicitHeight: col.implicitHeight

    function fmtTime(sec) {
        if (!sec || sec <= 0)
            return "";
        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " ч " + m + " мин" : m + " мин";
    }

    readonly property string stateText: {
        switch (bat.state) {
        case UPowerDeviceState.Charging:
            return "Заряжается";
        case UPowerDeviceState.Discharging:
            return "Разряжается";
        case UPowerDeviceState.FullyCharged:
            return "Заряжена";
        case UPowerDeviceState.PendingCharge:
            return "Ожидание зарядки";
        case UPowerDeviceState.PendingDischarge:
            return "Ожидание разрядки";
        case UPowerDeviceState.Empty:
            return "Разряжена";
        default:
            return "Неизвестно";
        }
    }
    readonly property string timeText: charging ? (fmtTime(bat.timeToFull) ? "до полной: " + fmtTime(bat.timeToFull) : "") : (bat.state === UPowerDeviceState.Discharging && fmtTime(bat.timeToEmpty) ? "осталось: " + fmtTime(bat.timeToEmpty) : "")

    // Режим питания: как в настройках (PowerCard) — свойство PowerProfiles и powerprofilesctl на случай, когда запись
    // в свойство не доходит до демона.
    readonly property string currentProfile: PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver"
        : PowerProfiles.profile === PowerProfile.Balanced ? "balanced" : "performance"
    readonly property var profiles: {
        const l = [{ id: "power-saver", label: "Экономия", icon: Config.icons.battery },
                   { id: "balanced", label: "Баланс", icon: Config.icons.power }];
        if (PowerProfiles.hasPerformanceProfile)
            l.push({ id: "performance", label: "Производительность", icon: Config.icons.power });
        return l;
    }
    function setProfile(p) {
        PowerProfiles.profile = p === "power-saver" ? PowerProfile.PowerSaver
            : p === "balanced" ? PowerProfile.Balanced : PowerProfile.Performance;
        ppd.command = ["powerprofilesctl", "set", p];
        ppd.running = true;
    }
    Process {
        id: ppd
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Row {
            spacing: 10
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: root.charging ? Config.icons.batteryCharging : root.critical ? Config.icons.batteryLow : Config.icons.battery
                color: root.critical ? Colors.error : root.charging || root.full ? Colors.success : Colors.primary
                font.pixelSize: Config.iconSize + 6
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(root.bat.percentage * 100) + "%"
                font.bold: true
                font.pixelSize: Config.fontSize + 5
            }
        }

        Rectangle {
            width: parent.width
            height: 6
            radius: 3
            color: Colors.surfaceContainerHighest
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.bat.percentage))
                height: parent.height
                radius: 3
                color: root.critical ? Colors.error : root.charging || root.full ? Colors.success : Colors.primary
            }
        }

        Txt {
            text: root.stateText
        }
        Txt {
            visible: root.timeText !== ""
            text: root.timeText
            color: Colors.fgVariant
        }
        Txt {
            visible: root.bat.changeRate !== 0 && root.bat.changeRate !== undefined
            text: "Мощность: " + Math.abs(root.bat.changeRate).toFixed(1) + " Вт"
            color: Colors.fgVariant
        }
        Txt {
            visible: root.bat.healthSupported
            text: "Состояние ёмкости: " + Math.round(root.bat.healthPercentage) + "%"
            color: Colors.fgVariant
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.35)
        }

        Txt {
            text: "Режим питания"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }

        Repeater {
            model: root.profiles

            PopItem {
                id: profItem

                required property var modelData

                width: col.width
                highlighted: root.currentProfile === modelData.id
                onClicked: root.setProfile(modelData.id)

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: profItem.highlighted ? Config.icons.check : profItem.modelData.icon
                    color: profItem.highlighted ? Colors.success : Colors.fgVariant
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: profItem.modelData.label
                    font.bold: profItem.highlighted
                }
            }
        }

        // Глубокая ссылка в окно настроек (профиль питания, простой, экраны).
        PopItem {
            width: 130
            onClicked: Overlays.openSettings("devices/power")
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
