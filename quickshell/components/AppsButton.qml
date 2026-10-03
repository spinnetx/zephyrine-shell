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

    Component.onCompleted: PopoutState.registerApps(root)
    Component.onDestruction: PopoutState.unregisterApps(root)

    Image {
        id: logoImg
        anchors.centerIn: parent
        width: Config.iconSize + 2
        height: Config.iconSize + 2
        source: Qt.resolvedUrl("../assets/zephyrine-symbol.png")
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        visible: status === Image.Ready

        // Тонкий эффект при наведении / клике
        opacity: root.hovered ? 1.0 : 0.88
        scale: root.hovered ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: !logoImg.visible
        text: Config.icons.apps
        color: Colors.primary
        font.pixelSize: Config.iconSize
    }
}
