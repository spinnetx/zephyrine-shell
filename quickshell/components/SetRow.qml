import QtQuick
import "../"

// Строка настройки: подпись + пояснение мелким слева, контрол справа (в Row внутри), место под ошибку.
Item {
    id: root

    default property alias content: ctl.data
    property string label: ""
    property string hint: ""
    property string error: ""          // ошибка валидации — красным под пояснением
    property bool dimmed: false        // строка неактивна (бэкенд отсутствует и т.п.)
    property int controlSpacing: 8

    implicitWidth: 440
    implicitHeight: Math.max(36, texts.implicitHeight + 10, ctl.implicitHeight + 8)
    opacity: dimmed ? 0.5 : 1

    Behavior on opacity {
        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    Column {
        id: texts
        anchors {
            left: parent.left
            right: ctl.left
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Txt {
            width: parent.width
            visible: root.label.length > 0
            text: root.label
            elide: Text.ElideRight
        }
        Txt {
            width: parent.width
            visible: root.hint.length > 0
            text: root.hint
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignTop
        }
        Txt {
            width: parent.width
            visible: root.error.length > 0
            text: root.error
            color: Colors.error
            font.pixelSize: Config.fontSize - 1
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignTop
        }
    }

    Row {
        id: ctl
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.controlSpacing
        enabled: !root.dimmed
    }
}
