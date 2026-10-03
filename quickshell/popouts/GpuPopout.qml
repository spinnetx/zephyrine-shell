pragma ComponentBehavior: Bound

import QtQuick
import "../"
import "../components"
import "../services"

// Видеокарта NVIDIA. Во сне/в ВМ показывает только статус из sysfs (карту не будит).
// Данные nvidia-smi есть, только пока карта active (см. services/Gpu.qml).
Item {
    id: root

    readonly property bool active: Gpu.state === "active" || Gpu.state === "error"
    readonly property string powerRu: Gpu.powerStatus === "active" ? "активна" : Gpu.powerStatus === "suspended" ? "спит (runtime suspend)" : Gpu.powerStatus === "suspending" ? "засыпает" : Gpu.powerStatus === "resuming" ? "просыпается" : Gpu.powerStatus

    implicitWidth: 360
    implicitHeight: col.implicitHeight

    component Line: Txt {
        color: Colors.fgVariant
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // Заголовок
        Row {
            spacing: 10
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.gpu
                color: Gpu.state === "active" ? Gpu.loadColor(Gpu.util) : Colors.fgVariant
                font.pixelSize: Config.iconSize + 6
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                visible: Gpu.state === "active" && Gpu.loaded
                text: Math.round(Gpu.util * 100) + "%"
                font.bold: true
                font.pixelSize: Config.fontSize + 5
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Видеокарта"
                color: Colors.fgVariant
            }
        }

        Txt {
            width: parent.width
            text: Gpu.name !== "" ? Gpu.name : "NVIDIA"
            elide: Text.ElideRight
            font.bold: true
        }

        Txt {
            text: "Питание: " + root.powerRu + (Gpu.driver !== "" ? " · драйвер " + Gpu.driver : "") + (Gpu.addr !== "" ? " · " + Gpu.addr : "")
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
            width: parent.width
            wrapMode: Text.Wrap
        }

        // --- Сон ---
        Column {
            visible: Gpu.state === "sleep"
            width: parent.width
            spacing: 4
            Txt {
                text: "Видеокарта спит (runtime suspend)"
                font.bold: true
                font.pixelSize: Config.fontSize + 3
            }
            Txt {
                width: parent.width
                text: "Запросы к драйверу не выполняются, чтобы не будить карту."
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
                wrapMode: Text.Wrap
            }
            Txt {
                width: parent.width
                text: "Разбудит запуск приложения на NVIDIA, например: prime-run <команда>."
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
                wrapMode: Text.Wrap
            }
        }

        // --- Проброс в ВМ ---
        Column {
            visible: Gpu.state === "vfio"
            width: parent.width
            spacing: 4
            Txt {
                text: "Видеокарта отдана виртуальной машине"
                font.bold: true
                font.pixelSize: Config.fontSize + 3
            }
            Txt {
                width: parent.width
                text: "Драйвер vfio-pci (проброс в ВМ). Хост карту не опрашивает."
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
                wrapMode: Text.Wrap
            }
        }

        // --- Ошибка nvidia-smi ---
        Txt {
            visible: Gpu.state === "error"
            width: parent.width
            text: "nvidia-smi не ответил. Повтор через " + Math.round(Config.gpuErrorBackoffMs / 1000) + " с."
            color: Colors.error
            wrapMode: Text.Wrap
        }

        // --- Активна ---
        Column {
            visible: Gpu.state === "active" && Gpu.loaded
            width: parent.width
            spacing: 10

            PopBar {
                width: parent.width
                value: Gpu.util
                accent: Gpu.loadColor(Gpu.util)
            }

            Column {
                width: parent.width
                spacing: 3
                Txt {
                    text: "VRAM: " + Gpu.fmtMiB(Gpu.memUsedMiB) + " / " + Gpu.fmtMiB(Gpu.memTotalMiB) + "  (" + Math.round(Gpu.memFrac * 100) + "%)"
                }
                PopBar {
                    width: parent.width
                    value: Gpu.memFrac
                    accent: Gpu.loadColor(Gpu.memFrac)
                }
            }

            Column {
                spacing: 2
                Txt {
                    text: "Температура: " + (Gpu.tempC >= 0 ? Math.round(Gpu.tempC) + " °C" : "—")
                    color: Gpu.tempC >= Config.gpuTempWarnC ? Gpu.tempColor(Gpu.tempC) : Colors.fgVariant
                }
                Line { text: "Мощность: " + (Gpu.powerW >= 0 ? Gpu.powerW.toFixed(1) + " Вт" : "—") }
                Line { text: "Частота ядра: " + (Gpu.clockMHz >= 0 ? Math.round(Gpu.clockMHz) : "—") + (Gpu.clockMaxMHz >= 0 ? " / " + Math.round(Gpu.clockMaxMHz) : "") + " МГц" }
                Line { text: "Вентилятор: " + (Gpu.fanPct >= 0 ? Math.round(Gpu.fanPct) + "%" : "—") }
                Line { text: "P-state: " + (Gpu.pstate !== "" ? Gpu.pstate : "—") }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.alpha(Colors.outlineVariant, 0.6)
            }

            Txt {
                visible: Gpu.apps.length === 0
                text: "Нет вычислительных процессов (графические не показываются)"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: Gpu.apps.slice(0, 8)
                    Item {
                        id: appRow
                        required property var modelData
                        width: parent.width
                        height: nameTxt.implicitHeight
                        Txt {
                            width: 56
                            text: appRow.modelData.pid
                            color: Colors.fgVariant
                            font.pixelSize: Config.fontSize - 2
                        }
                        Txt {
                            id: nameTxt
                            x: 62
                            width: parent.width - 62 - 80
                            text: appRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Config.fontSize - 2
                        }
                        Txt {
                            anchors.right: parent.right
                            text: Gpu.fmtMiB(appRow.modelData.memMiB)
                            font.pixelSize: Config.fontSize - 2
                        }
                    }
                }
            }
        }

        Txt {
            visible: Gpu.state === "active" && !Gpu.loaded
            text: "Ожидание данных nvidia-smi…"
            color: Colors.fgVariant
        }
    }
}
