import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../../"
import "../../services"
import "../../components"

// Карточка «Питание» (DESIGN §4.3, §6.5):
// - Профиль питания (powerprofilesctl / PowerProfiles).
// - Состояние батареи, время работы, уровень критического заряда.
// - Таймауты простоя (hypridle): затемнение, отключение экрана (DPMS), блокировка, сон.
SetCard {
    id: root

    title: "Питание"
    icon: Config.icons.power

    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat !== null && bat.isPresent
    readonly property bool charging: hasBattery && bat.state === UPowerDeviceState.Charging
    readonly property bool full: hasBattery && bat.state === UPowerDeviceState.FullyCharged
    readonly property bool critical: hasBattery && !charging && !full && bat.percentage < Prefs.batteryCritical

    function fmtTime(sec) {
        if (!sec || sec <= 0)
            return "";
        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " ч " + m + " мин" : m + " мин";
    }

    readonly property string stateText: {
        if (!hasBattery)
            return "Питание от сети";
        switch (bat.state) {
        case UPowerDeviceState.Charging:
            return "Заряжается";
        case UPowerDeviceState.Discharging:
            return "Разряжается";
        case UPowerDeviceState.FullyCharged:
            return "Полностью заряжена";
        case UPowerDeviceState.PendingCharge:
            return "Ожидание зарядки";
        case UPowerDeviceState.PendingDischarge:
            return "Ожидание разрядки";
        case UPowerDeviceState.Empty:
            return "Разряжена";
        default:
            return "Подключено к сети";
        }
    }

    readonly property string timeText: {
        if (!hasBattery)
            return "";
        if (charging)
            return fmtTime(bat.timeToFull) ? "до полной зарядки: " + fmtTime(bat.timeToFull) : "";
        if (bat.state === UPowerDeviceState.Discharging)
            return fmtTime(bat.timeToEmpty) ? "осталось: " + fmtTime(bat.timeToEmpty) : "";
        return "";
    }

    // Профиль питания (string: "power-saver" | "balanced" | "performance")
    readonly property string currentProfile: {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            return "power-saver";
        if (PowerProfiles.profile === PowerProfile.Balanced)
            return "balanced";
        return "performance";
    }

    function setProfile(p) {
        if (p === "power-saver")
            PowerProfiles.profile = PowerProfile.PowerSaver;
        else if (p === "balanced")
            PowerProfiles.profile = PowerProfile.Balanced;
        else
            PowerProfiles.profile = PowerProfile.Performance;
        ppdProcess.command = ["powerprofilesctl", "set", p];
        ppdProcess.running = true;
    }

    Process {
        id: ppdProcess
    }

    function effIdle(key, defVal) {
        const v = Prefs.lookup(Prefs.file, "power.idle." + key);
        return v !== undefined ? v : defVal;
    }

    // --- Профиль питания ---
    SetRow {
        width: parent.width
        label: "Профиль питания"
        hint: "Режим энергопотребления процессора и графики"

        SetSegmented {
            options: [
                { value: "power-saver", label: "Экономия" },
                { value: "balanced", label: "Баланс" },
                { value: "performance", label: "Производительность" }
            ]
            current: root.currentProfile
            onSelected: val => root.setProfile(val)
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // --- Батарея ---
    Item {
        width: parent.width
        height: root.hasBattery ? 64 : 32

        Column {
            anchors.fill: parent
            spacing: 6

            Row {
                spacing: 12

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.charging ? Config.icons.batteryCharging : root.critical ? Config.icons.batteryLow : Config.icons.battery
                    color: root.critical ? Colors.error : (root.charging || root.full) ? Colors.success : Colors.primary
                    font.pixelSize: Config.iconSize + 4
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasBattery ? Math.round(root.bat.percentage * 100) + "%" : "Питание от сети"
                    font.bold: true
                    font.pixelSize: Config.fontSize + 2
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·  " + root.stateText
                    color: Colors.fgVariant
                }

                Txt {
                    visible: root.timeText !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·  " + root.timeText
                    color: Colors.fgVariant
                }

                Txt {
                    visible: root.hasBattery && root.bat.healthSupported
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·  ёмкость " + Math.round(root.bat.healthPercentage) + "%"
                    color: Colors.fgVariant
                }
            }

            // Полоса заряда батареи
            Rectangle {
                visible: root.hasBattery
                width: parent.width
                height: 6
                radius: 3
                color: Colors.surfaceContainerHighest

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.hasBattery ? root.bat.percentage : 1))
                    height: parent.height
                    radius: 3
                    color: root.critical ? Colors.error : (root.charging || root.full) ? Colors.success : Colors.primary
                }
            }
        }
    }

    // Порог критического заряда
    SetRow {
        visible: root.hasBattery
        width: parent.width
        label: "Порог критического заряда"
        hint: "Показывать предупреждение при снижении заряда ниже этого значения"

        SetSlider {
            width: 220
            from: 5
            to: 30
            step: 1
            decimals: 0
            suffix: "%"
            value: Math.round(Prefs.batteryCritical * 100)
            defaultValue: 15
            showReset: true
            accent: Colors.error
            onCommit: v => SettingsCli.set({ "power.batteryCritical": v / 100 })
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // --- Таймауты простоя (hypridle) ---
    Txt {
        text: "Таймауты бездействия (hypridle)"
        font.bold: true
        font.pixelSize: Config.fontSize
        color: Colors.fg
    }

    SetRow {
        width: parent.width
        label: "Затемнять экран через"
        hint: "Снижение яркости подсветки при отсутствии активности"

        SetDropdown {
            width: 180
            options: [
                { value: null, label: "никогда" },
                { value: 60, label: "1 мин" },
                { value: 150, label: "2.5 мин" },
                { value: 300, label: "5 мин" },
                { value: 600, label: "10 мин" }
            ]
            current: root.effIdle("dimSec", 150)
            onSelected: val => SettingsCli.set({ "power.idle.dimSec": val })
        }
    }

    SetRow {
        width: parent.width
        label: "Гасить экран через"
        hint: "Выключение видеосигнала (DPMS) на мониторах"

        SetDropdown {
            width: 180
            options: [
                { value: null, label: "никогда" },
                { value: 120, label: "2 мин" },
                { value: 330, label: "5.5 мин" },
                { value: 600, label: "10 мин" },
                { value: 900, label: "15 мин" },
                { value: 1800, label: "30 мин" }
            ]
            current: root.effIdle("dpmsSec", 330)
            onSelected: val => SettingsCli.set({ "power.idle.dpmsSec": val })
        }
    }

    SetRow {
        width: parent.width
        label: "Блокировать экран через"
        hint: "Автоматический запуск экрана блокировки"

        SetDropdown {
            width: 180
            options: [
                { value: null, label: "никогда" },
                { value: 180, label: "3 мин" },
                { value: 300, label: "5 мин" },
                { value: 600, label: "10 мин" },
                { value: 900, label: "15 мин" },
                { value: 1800, label: "30 мин" }
            ]
            current: root.effIdle("lockSec", null)
            onSelected: val => SettingsCli.set({ "power.idle.lockSec": val })
        }
    }

    SetRow {
        width: parent.width
        label: "Переходить в сон через"
        hint: "Приостановка работы системы (suspend)"

        SetDropdown {
            width: 180
            options: [
                { value: null, label: "никогда" },
                { value: 600, label: "10 мин" },
                { value: 900, label: "15 мин" },
                { value: 1800, label: "30 мин" },
                { value: 3600, label: "1 час" }
            ]
            current: root.effIdle("suspendSec", null)
            onSelected: val => SettingsCli.set({ "power.idle.suspendSec": val })
        }
    }
}
