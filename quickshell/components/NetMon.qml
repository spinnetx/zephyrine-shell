import QtQuick
import "../"
import "../services"

// Сеть: «↓1.2M ↑ 40K» — скорость приёма/отдачи; при нуле приглушено. Попап — kind "net".
Pill {
    id: root

    spacing: 4

    PopoutTrigger {
        parent: root
        kind: "net"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.arrowDown
        color: SysMon.rxRate >= 1 ? Colors.tertiary : Colors.fgVariant
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: SysMon.fmtRate(SysMon.rxRate).padStart(4, " ")
        color: SysMon.rxRate >= 1 ? Colors.fg : Colors.fgVariant
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.arrowUp
        color: SysMon.txRate >= 1 ? Colors.primary : Colors.fgVariant
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: SysMon.fmtRate(SysMon.txRate).padStart(4, " ")
        color: SysMon.txRate >= 1 ? Colors.fg : Colors.fgVariant
    }
}
