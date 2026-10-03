import "../"
import "../services"

// Кнопка питания: открывает меню питания (powermenu/PowerMenu.qml).
Pill {
    clickable: true
    horizontalPadding: 8
    implicitWidth: Config.pillHeight
    tooltip: "Меню питания"
    onClicked: Overlays.togglePower()

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.power
        color: Colors.primary
        font.pixelSize: Config.iconSize
    }
}
