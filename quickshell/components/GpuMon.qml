import QtQuick
import "../"
import "../services"

// Видеокарта NVIDIA: «NN% NN°» (active) | «сон» (runtime suspend) | «ВМ» (vfio-pci) | «?» (ошибка).
// Нет карты/драйвера/nvidia-smi — пилюля скрыта (в Row бара не занимает места). Попап — kind "gpu".
Pill {
    id: root

    readonly property string st: Gpu.state
    readonly property bool live: st === "active" && Gpu.loaded
    readonly property color accent: st === "active" ? Gpu.loadColor(Gpu.util) : st === "error" ? Colors.error : st === "vfio" ? Colors.tertiary : Colors.fgVariant

    readonly property bool shown: st !== "none"
    visible: shown
    spacing: 8

    PopoutTrigger {
        parent: root
        kind: "gpu"
    }

    // Ширина под самое длинное состояние «100% 99°» — пилюля не «дёргается» при смене состояния.
    TextMetrics {
        id: metrics
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
        text: "100% 99°"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.gpu
        color: root.accent
        font.pixelSize: Config.iconSize
    }

    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.ceil(metrics.advanceWidth)
        height: parent.height

        // Числа — только когда карта активна и пришёл ответ nvidia-smi.
        Row {
            visible: root.live
            anchors.verticalCenter: parent.verticalCenter
            Txt {
                text: String(Math.round(Gpu.util * 100)).padStart(3, " ") + "%"
                color: Gpu.loadColor(Gpu.util) === Colors.primary ? Colors.fg : Gpu.loadColor(Gpu.util)
            }
            Txt {
                text: " " + (Gpu.tempC >= 0 ? String(Math.round(Gpu.tempC)).padStart(2, " ") + "°" : " —")
                color: Gpu.tempColor(Gpu.tempC)
            }
        }
        Txt {
            visible: !root.live
            anchors.verticalCenter: parent.verticalCenter
            text: root.st === "sleep" ? "сон" : root.st === "vfio" ? "ВМ" : root.st === "error" ? "?" : "…"
            color: root.st === "error" ? Colors.error : root.st === "active" || root.st === "vfio" ? Colors.fg : Colors.fgVariant
        }
    }
}
