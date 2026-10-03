import QtQuick
import "../"
import "../services"

// Компактный тост-сообщение шелла (Toaster): цветная иконка по типу, заголовок, необязательный текст, ×.
// Клик по карточке или × — закрыть (сигнал closeRequested).
Rectangle {
    id: root

    // {key, title, message, icon, type, t} из Toaster.list
    required property var msg

    readonly property bool hovered: hover.hovered
    readonly property color accent: msg.type === "success" ? Colors.success
        : msg.type === "warning" ? Colors.tertiary
        : msg.type === "error" ? Colors.error : Colors.primary
    readonly property string glyph: msg.icon !== "" ? msg.icon
        : msg.type === "success" ? Config.icons.checkCircle
        : msg.type === "warning" ? Config.icons.alert
        : msg.type === "error" ? Config.icons.alertCircle : Config.icons.info

    signal closeRequested

    implicitHeight: Math.max(body.implicitHeight, 26) + 16
    radius: 10
    color: hover.hovered ? Colors.surfaceContainerHighest : Qt.alpha(Colors.surfaceContainerHigh, 0.97)
    border.width: 1
    border.color: Qt.alpha(root.accent, 0.6)

    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Config.animEasing }
    }

    HoverHandler {
        id: hover
    }
    TapHandler {
        onTapped: root.closeRequested()
    }

    Row {
        id: body
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 20
        spacing: 10

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            color: root.accent
            font.pixelSize: Config.iconSize + 6
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 26 - 10 - 22 - 10
            spacing: 2

            Txt {
                width: parent.width
                text: root.msg.title
                font.bold: true
                elide: Text.ElideRight
            }
            Txt {
                visible: text !== ""
                width: parent.width
                text: root.msg.message
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 1
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: 11
            color: closeHover.hovered ? Colors.surfaceContainer : "transparent"

            HoverHandler {
                id: closeHover
                cursorShape: Qt.PointingHandCursor
            }
            Txt {
                anchors.centerIn: parent
                text: Config.icons.close
                color: closeHover.hovered ? Colors.error : Colors.fgVariant
                font.pixelSize: Config.iconSize - 2
            }
        }
    }
}
