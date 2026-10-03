import QtQuick
import "../"
import "../services"

// CPU: по столбику на логический поток (цвет по нагрузке) + суммарный процент. Попап — kind "cpu".
Pill {
    id: root

    readonly property int pct: Math.round(SysMon.cpuTotal * 100)

    spacing: 8

    PopoutTrigger {
        parent: root
        kind: "cpu"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.chip
        color: Colors.primary
        font.pixelSize: Config.iconSize
    }

    Row {
        id: bars
        anchors.verticalCenter: parent.verticalCenter
        height: 16
        spacing: 1

        Repeater {
            model: SysMon.cores

            Item {
                required property real modelData
                width: 3
                height: bars.height

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    radius: 1
                    height: Math.max(2, parent.height * parent.modelData)
                    color: SysMon.loadColor(parent.modelData)
                    Behavior on height {
                        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                    }
                }
            }
        }
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        // Моноширинный шрифт + дополнение пробелами: ширина постоянна, пилюля не «дёргается».
        text: String(root.pct).padStart(3, " ") + "%"
        color: SysMon.loadColor(SysMon.cpuTotal) === Colors.primary ? Colors.fg : SysMon.loadColor(SysMon.cpuTotal)
    }
}
