import QtQuick
import "../"

// Чип статуса: «вживую», «нужен перезапуск», «не установлено», «изменён вручную», «ошибка».
// kind задаёт цвет и текст по умолчанию; text можно переопределить.
Rectangle {
    id: root

    // live | restart | missing | manual | error | neutral
    property string kind: "neutral"
    property string text: ""
    property string tooltip: ""
    readonly property bool hovered: hover.hovered

    readonly property color tone: kind === "live" ? Colors.success
        : kind === "restart" ? Colors.tertiary
        : kind === "manual" ? Colors.secondary
        : kind === "error" ? Colors.error
        : Colors.fgVariant
    readonly property string defaultText: kind === "live" ? "вживую"
        : kind === "restart" ? "нужен перезапуск"
        : kind === "missing" ? "не установлено"
        : kind === "manual" ? "изменён вручную"
        : kind === "error" ? "ошибка"
        : ""
    readonly property string shownText: text.length > 0 ? text : defaultText

    visible: shownText.length > 0
    implicitHeight: 20
    implicitWidth: label.implicitWidth + 16
    radius: height / 2
    color: Qt.alpha(tone, 0.16)
    border.width: 1
    border.color: Qt.alpha(tone, 0.45)

    Behavior on color {
        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }
    Behavior on implicitWidth {
        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    Txt {
        id: label
        anchors.centerIn: parent
        text: root.shownText
        color: root.tone
        font.pixelSize: Config.fontSize - 2
    }

    HoverHandler {
        id: hover
    }

    Tip {
        target: root
        text: root.tooltip
        hovered: root.hovered
    }
}
