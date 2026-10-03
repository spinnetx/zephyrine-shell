import QtQuick
import "../"

// Поле ввода для попапов: рамка в стиле бара, placeholder, для паролей — кнопка-«глаз».
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property bool secret: false         // поле пароля (символы скрыты, есть «глаз»)
    property bool revealed: false       // пароль показан
    property bool fieldEnabled: true
    readonly property bool focused: input.activeFocus
    signal accepted
    signal escaped
    signal tabbed
    signal moved(int delta)             // стрелки вверх/вниз (навигация по списку рядом с полем)

    function focusInput() {
        input.forceActiveFocus();
    }

    implicitHeight: 34
    implicitWidth: 240
    radius: 10
    color: Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
    border.width: 1
    border.color: input.activeFocus ? Qt.alpha(Colors.primary, 0.7) : Qt.alpha(Colors.outline, 0.35)
    opacity: fieldEnabled ? 1 : 0.6

    Behavior on border.color {
        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    TextInput {
        id: input
        anchors {
            left: parent.left
            leftMargin: 10
            right: eye.visible ? eye.left : parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        enabled: root.fieldEnabled
        color: Colors.fg
        selectionColor: Colors.primaryContainer
        selectedTextColor: Colors.fg
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
        clip: true
        echoMode: root.secret && !root.revealed ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        inputMethodHints: root.secret ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText : Qt.ImhNoPredictiveText

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.escaped();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.accepted();
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                root.tabbed();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root.moved(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.moved(-1);
                event.accepted = true;
            }
        }

        Txt {
            anchors.fill: parent
            visible: input.text.length === 0
            text: root.placeholder
            color: Colors.fgVariant
            opacity: 0.7
        }
    }

    Txt {
        id: eye
        visible: root.secret
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.revealed ? Config.icons.eyeOff : Config.icons.eye
        color: root.revealed ? Colors.primary : Colors.fgVariant
        font.pixelSize: Config.iconSize

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.revealed = !root.revealed
        }
    }
}
