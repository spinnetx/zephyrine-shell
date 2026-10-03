import QtQuick
import "../"

// Карточка раздела окна настроек: заголовок, необязательные иконка и чип статуса, содержимое — в Column внутри.
Rectangle {
    id: root

    default property alias content: body.data
    property string title: ""
    property string icon: ""
    property string chipKind: "neutral"
    property string chipText: ""
    property alias headerRight: headerExtra.data   // доп. элементы справа в шапке (например, общий переключатель)

    implicitWidth: 480
    implicitHeight: col.implicitHeight + Config.popoutPadding * 2
    radius: Config.popoutRadius
    color: Qt.alpha(Colors.surfaceContainer, Config.pillAlpha)
    border.width: 1
    border.color: Qt.alpha(Colors.outline, 0.28)

    Behavior on implicitHeight {
        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    Column {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Config.popoutPadding
        }
        spacing: 8

        Item {
            id: header
            visible: root.title.length > 0 || root.icon.length > 0
            width: parent.width
            height: visible ? 24 : 0

            Row {
                id: titleRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Txt {
                    visible: root.icon.length > 0
                    text: root.icon
                    color: Colors.primary
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    text: root.title
                    font.bold: true
                }
                StatusChip {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: root.chipKind
                    text: root.chipText
                }
            }
            Row {
                id: headerExtra
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
            }
        }

        Rectangle {
            visible: header.visible
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.35)
        }

        Column {
            id: body
            width: parent.width
            spacing: 4
        }
    }
}
