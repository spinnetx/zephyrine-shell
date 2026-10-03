pragma ComponentBehavior: Bound

import QtQuick
import "../"
import "../components"
import "../services"

// CPU: сводка (частота, температура, load average) и загрузка каждого потока с полосками.
Item {
    id: root

    readonly property color tempTint: SysMon.cpuTempC >= Config.tempCritC ? Colors.error : SysMon.cpuTempC >= Config.tempWarnC ? Colors.tertiary : Colors.fg

    implicitWidth: 320
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 10

        Row {
            spacing: 10
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.chip
                color: Colors.primary
                font.pixelSize: Config.iconSize + 6
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(SysMon.cpuTotal * 100) + "%"
                font.bold: true
                font.pixelSize: Config.fontSize + 5
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Процессор"
                color: Colors.fgVariant
            }
        }

        PopBar {
            width: parent.width
            value: SysMon.cpuTotal
            accent: SysMon.loadColor(SysMon.cpuTotal)
        }

        Column {
            spacing: 2
            Txt {
                text: "Частота: " + (SysMon.cpuFreqMHz > 0 ? (SysMon.cpuFreqMHz / 1000).toFixed(2) + " ГГц" : "—")
                color: Colors.fgVariant
            }
            Txt {
                text: "Температура: " + (SysMon.cpuTempC >= 0 ? Math.round(SysMon.cpuTempC) + " °C" : "—")
                color: root.tempTint
            }
            Txt {
                text: "Load average: " + SysMon.loadAvg.map(v => v.toFixed(2)).join("  ")
                color: Colors.fgVariant
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outlineVariant, 0.6)
        }

        // Ядра — два столбца
        Grid {
            columns: 2
            columnSpacing: 16
            rowSpacing: 4
            flow: Grid.TopToBottom
            // Число строк = половина ядер: заполняем сверху вниз по столбцам.
            rows: Math.ceil(SysMon.cores.length / 2)

            Repeater {
                model: SysMon.cores

                Row {
                    id: rowItem
                    required property real modelData
                    required property int index
                    spacing: 6

                    Txt {
                        width: 22
                        text: rowItem.index
                        horizontalAlignment: Text.AlignRight
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 2
                    }
                    PopBar {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 78
                        value: rowItem.modelData
                        accent: SysMon.loadColor(rowItem.modelData)
                    }
                    Txt {
                        width: 34
                        text: Math.round(rowItem.modelData * 100) + "%"
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: Config.fontSize - 2
                    }
                }
            }
        }
    }
}
