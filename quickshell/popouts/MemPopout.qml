pragma ComponentBehavior: Bound

import QtQuick
import "../"
import "../components"
import "../services"

// Память: занято / кэш / свободно / подкачка — полоски и значения.
Item {
    id: root

    readonly property color tint: SysMon.memFrac >= Config.memCrit ? Colors.error : SysMon.memFrac >= Config.memWarn ? Colors.tertiary : Colors.primary
    readonly property var rows: [
        { name: "Занято", v: SysMon.memUsed, total: SysMon.memTotal, color: root.tint },
        { name: "Кэш", v: SysMon.memCached, total: SysMon.memTotal, color: Colors.secondary },
        { name: "Свободно", v: SysMon.memFree, total: SysMon.memTotal, color: Colors.success },
        { name: "Подкачка", v: SysMon.swapUsed, total: SysMon.swapTotal, color: Colors.tertiary }
    ]

    implicitWidth: 280
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 10

        Row {
            spacing: 10
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.memory
                color: root.tint
                font.pixelSize: Config.iconSize + 6
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(SysMon.memFrac * 100) + "%"
                font.bold: true
                font.pixelSize: Config.fontSize + 5
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: SysMon.fmtGiB(SysMon.memUsed) + " из " + SysMon.fmtGiB(SysMon.memTotal)
                color: Colors.fgVariant
            }
        }

        Repeater {
            model: root.rows

            Column {
                id: item
                required property var modelData
                width: col.width
                spacing: 3

                Item {
                    width: parent.width
                    height: nameTxt.implicitHeight
                    Txt {
                        id: nameTxt
                        text: item.modelData.name
                        color: Colors.fgVariant
                    }
                    Txt {
                        anchors.right: parent.right
                        text: item.modelData.total > 0 ? SysMon.fmtGiB(item.modelData.v) + " / " + SysMon.fmtGiB(item.modelData.total) : "нет"
                    }
                }
                PopBar {
                    width: parent.width
                    value: item.modelData.total > 0 ? item.modelData.v / item.modelData.total : 0
                    accent: item.modelData.color
                }
            }
        }
    }
}
