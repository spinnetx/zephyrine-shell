import QtQuick
import "../../"
import "../../components"

// Баннер над содержимым раздела (DESIGN §6.3): краткий текст по-русски, сырое сообщение мелким, необязательная кнопка.
// kind: error | warn.
Rectangle {
    id: root

    property string kind: "error"
    property string text: ""
    property string detail: ""
    property string buttonText: ""
    property string icon: kind === "error" ? Config.icons.alertCircle : Config.icons.alert
    signal clicked

    readonly property color tone: kind === "error" ? Colors.error : Colors.tertiary

    implicitHeight: Math.max(48, texts.implicitHeight + 20)
    radius: Config.popoutRadius
    color: Qt.alpha(tone, 0.14)
    border.width: 1
    border.color: Qt.alpha(tone, 0.5)

    Txt {
        id: ico
        anchors {
            left: parent.left
            leftMargin: 14
            verticalCenter: parent.verticalCenter
        }
        text: root.icon
        color: root.tone
        font.pixelSize: Config.iconSize + 2
    }

    Column {
        id: texts
        anchors {
            left: ico.right
            leftMargin: 10
            right: btn.visible ? btn.left : parent.right
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        spacing: 2
        Txt {
            width: parent.width
            text: root.text
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignTop
        }
        Txt {
            visible: root.detail.length > 0
            width: parent.width
            text: root.detail
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
        }
    }

    SetButton {
        id: btn
        visible: root.buttonText.length > 0
        anchors {
            right: parent.right
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        text: root.buttonText
        onClicked: root.clicked()
    }
}
