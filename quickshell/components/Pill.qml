import QtQuick
import "../"

// Скруглённая «пилюля» с фоном surfaceContainerHigh (светлее фона бара) и тонкой рамкой. Содержимое — в Row внутри.
Rectangle {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing
    property string tooltip: ""
    property bool clickable: false
    property real horizontalPadding: Config.pillPadding
    readonly property bool hovered: hover.hovered

    signal clicked(var mouse)
    signal scrolled(int delta)

    implicitHeight: Config.pillHeight
    implicitWidth: row.implicitWidth + horizontalPadding * 2
    radius: Config.pillRadius
    color: hovered && clickable ? Colors.surfaceContainerHighest : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
    // Тонкий светлый контур — чтобы пилюли отделялись и над светлыми участками обоев.
    border.width: 1
    border.color: Qt.alpha(Colors.outline, 0.28)

    Behavior on color {
        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }
    // Ширина меняется плавно, когда меняется текст/появляются значения.
    Behavior on implicitWidth {
        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }
    // Плавное появление при создании.
    NumberAnimation on opacity {
        from: 0
        to: 1
        duration: Config.animMs * 1.5
        easing.type: Config.animEasing
    }

    HoverHandler {
        id: hover
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    // Объявлен раньше Row, поэтому дочерние MouseArea (трей, статусы) лежат выше.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: root.clickable ? Qt.LeftButton | Qt.RightButton | Qt.MiddleButton : Qt.NoButton
        onClicked: mouse => root.clicked(mouse)
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Config.spacing
        height: parent.height
    }

    Tip {
        target: root
        text: root.tooltip
        hovered: root.hovered
    }
}
