import QtQuick
import "../"
import "../services"

// Кнопка «Меню приложений»: клик открывает у кнопки закреплённый попап (popouts/AppsPopout.qml) — поиск, категории и
// список приложений; повторный клик, Esc или клик вне попапа закрывают.
Pill {
    id: root

    clickable: true
    horizontalPadding: 8
    implicitWidth: Config.pillHeight
    tooltip: "Приложения"
    onClicked: PopoutState.togglePinnedAt("apps", root)

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.apps
        color: Colors.primary
        font.pixelSize: Config.iconSize
    }
}
