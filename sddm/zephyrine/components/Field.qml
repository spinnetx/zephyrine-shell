import QtQuick

// Поле ввода: иконка слева, плейсхолдер, для пароля — кнопка-«глаз».
Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property string icon: ""
    property bool password: false
    property bool revealed: false
    property bool locked: false           // блокировка на время входа

    signal accepted()
    signal tabPressed()
    signal escPressed()

    function forceFocus() { input.forceActiveFocus(); }

    implicitHeight: 44
    radius: Theme.pillRadius + 2
    color: Theme.alpha(Theme.surfaceContainerHighest, 0.55)
    opacity: locked ? 0.6 : 1
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? Theme.primary : Theme.alpha(Theme.outlineVariant, 0.5)

    Behavior on border.color {
        ColorAnimation { duration: Theme.animMs; easing.type: Theme.easing }
    }
    Behavior on opacity {
        NumberAnimation { duration: Theme.animMs; easing.type: Theme.easing }
    }

    Txt {
        id: ico
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: input.activeFocus ? Theme.primary : Theme.fgVariant
        font.pixelSize: Theme.fontSize + 2
    }

    TextInput {
        id: input
        anchors.left: ico.right
        anchors.leftMargin: 10
        anchors.right: eye.visible ? eye.left : parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        enabled: !root.locked
        color: Theme.fg
        selectionColor: Theme.primaryContainer
        selectedTextColor: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 1
        echoMode: (root.password && !root.revealed) ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        inputMethodHints: root.password ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText : Qt.ImhNoPredictiveText
        selectByMouse: true

        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()
        Keys.onEscapePressed: root.escPressed()
        // Tab/Backtab перехватываем сами — переключение полей решает карточка
        Keys.onTabPressed: root.tabPressed()
        Keys.onBacktabPressed: root.tabPressed()

        Txt {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: root.placeholder
            color: Theme.alpha(Theme.fgVariant, 0.6)
            font.pixelSize: Theme.fontSize + 1
        }
    }

    // Кнопка «показать/скрыть пароль»
    Item {
        id: eye
        visible: root.password
        width: 36
        height: parent.height
        anchors.right: parent.right
        Txt {
            anchors.centerIn: parent
            text: root.revealed ? "" : ""
            color: eyeMouse.containsMouse ? Theme.primary : Theme.fgVariant
            font.pixelSize: Theme.fontSize + 2
        }
        MouseArea {
            id: eyeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !root.locked
            onClicked: {
                root.revealed = !root.revealed;
                input.forceActiveFocus();
            }
        }
    }
}
