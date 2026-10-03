import QtQuick
import "../"

// Строка списка в попапе: подсветка при наведении, клик. Содержимое — в Row внутри.
Rectangle {
    id: root

    default property alias content: row.data
    property bool clickable: true
    property bool centered: false      // содержимое по центру (кнопки-иконки)
    property bool highlighted: false   // например, активная сеть/устройство
    readonly property bool hovered: hover.hovered
    signal clicked

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 16
    radius: 8
    color: hovered && clickable ? Colors.surfaceContainerHighest : highlighted ? Qt.alpha(Colors.primary, 0.14) : "transparent"

    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Config.animEasing }
    }

    HoverHandler {
        id: hover
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: root.clickable
        onTapped: root.clicked()
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: root.centered ? (root.width - width) / 2 : 8
        spacing: 8
    }
}
