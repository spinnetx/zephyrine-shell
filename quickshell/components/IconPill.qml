import QtQuick
import "../"

// Компактная пилюля вертикальной панели: только иконка (значения — в подсказке, детали — в hover-попапе `kind`).
Pill {
    id: root

    property string icon: ""
    property color iconColor: Colors.primary
    property string kind: ""            // вид hover-попапа ("" — без попапа)
    property bool shown: true
    property string label: ""           // короткий текст вместо иконки (раскладка, остаток таймера, эмодзи погоды)

    visible: shown
    horizontalPadding: 0
    implicitWidth: Config.pillHeight + 8

    PopoutTrigger {
        parent: root
        kind: root.kind
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.label === ""
        text: root.icon
        color: root.iconColor
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.label !== ""
        text: root.label
        color: root.iconColor
        font.bold: true
        font.pixelSize: Config.fontSize - 1
    }
}
