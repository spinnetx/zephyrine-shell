import QtQuick
import Quickshell
import "../"
import "../services"

// Раскладка клавиатуры: значок и короткая подпись (PL, RU…). Клик — следующая раскладка (hyprctl switchxkblayout).
Pill {
    id: root

    readonly property bool shown: Kbd.layout !== ""

    visible: shown
    clickable: true
    spacing: 6
    tooltip: "Раскладка: " + Kbd.layout + "\nКлик — следующая"
    onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.keyboard
        color: Colors.tertiary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Kbd.abbr
        font.bold: true
    }
}
