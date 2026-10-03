import QtQuick
import "../"
import "../services"

// Память: «12.3G 45%» (цвет при > Config.memWarn / memCrit). Попап — kind "mem".
Pill {
    id: root

    readonly property color tint: SysMon.memFrac >= Config.memCrit ? Colors.error : SysMon.memFrac >= Config.memWarn ? Colors.tertiary : Colors.fg

    PopoutTrigger {
        parent: root
        kind: "mem"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.memory
        color: root.tint === Colors.fg ? Colors.primary : root.tint
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: SysMon.fmtGiB(SysMon.memUsed).padStart(5, " ") + " " + String(Math.round(SysMon.memFrac * 100)).padStart(2, " ") + "%"
        color: root.tint
    }
}
