import QtQuick
import "../"

// Иконка (+ необязательный текст) внутри общей пилюли статусов.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string tooltip: ""
    property color tint: Colors.fg             // цвет подписи
    property color iconTint: Colors.primary    // иконки — акцентом
    // Вид попапа при наведении ("" — обычная Tip-подсказка).
    property string popout: ""

    signal clicked
    signal scrolled(int delta)

    implicitWidth: content.implicitWidth
    implicitHeight: Config.pillHeight

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Txt {
            text: root.icon
            color: root.iconTint
            font.pixelSize: Config.iconSize
        }
        Txt {
            visible: root.label !== ""
            text: root.label
            color: root.tint
        }
    }

    HoverHandler {
        id: hover
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }
    PopoutTrigger {
        kind: root.popout
    }
    Tip {
        target: root
        text: root.popout === "" ? root.tooltip : ""
        hovered: hover.hovered
    }
}
