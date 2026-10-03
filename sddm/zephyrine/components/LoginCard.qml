import QtQuick

// Карточка входа: аватар, имя, поля «Логин» и «Пароль», кнопка «Войти»,
// сообщение об ошибке, индикатор Caps Lock. Под карточкой — чипы пользователей.
Item {
    id: root

    // Индекс сессии (из SessionPicker через Main)
    property int sessionIndex: 0
    property bool busy: false
    property string errorMessage: ""
    property real shakeX: 0

    readonly property var um: (typeof userModel !== "undefined") ? userModel : null
    readonly property bool caps: (typeof keyboard !== "undefined" && keyboard) ? keyboard.capsLock : false
    // Данные текущего пользователя (по введённому логину)
    readonly property var current: {
        users.count;   // пересчёт, когда модель пользователей наполнилась
        return userFor(loginField.text);
    }
    readonly property string displayName: current && current.realName.length > 0 ? current.realName
                                         : loginField.text

    width: 440
    implicitHeight: card.height + (chips.visible ? chips.height + 14 : 0)

    function userFor(login) {
        for (let i = 0; i < users.count; ++i) {
            const it = users.itemAt(i);
            if (it && it.uname === login)
                return it;
        }
        return null;
    }
    function focusPassword() { passwordField.forceFocus(); }
    function doLogin() {
        if (busy || loginField.text.length === 0)
            return;
        errorMessage = "";
        busy = true;
        sddm.login(loginField.text, passwordField.text, sessionIndex);
    }
    function shake() { shakeAnim.restart(); }

    // Невидимый читатель модели пользователей
    Repeater {
        id: users
        model: root.um
        delegate: Item {
            required property string name
            required property string realName
            required property string icon
            readonly property string uname: name
        }
    }

    Component.onCompleted: {
        if (um) {
            if (um.lastUser && um.lastUser.length > 0)
                loginField.text = um.lastUser;
        }
    }
    // Если lastUser пуст, а пользователи уже загрузились — берём первого
    Connections {
        target: users
        function onItemAdded(index, item) {
            if (index === 0 && loginField.text.length === 0)
                loginField.text = item.uname;
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            root.errorMessage = "Неверный логин или пароль";
            passwordField.text = "";
            root.shake();
            root.focusPassword();
        }
        function onLoginSucceeded() {
            // Сессия стартует; поля остаются заблокированными до выхода greeter-а
            root.errorMessage = "";
        }
        function onInformationMessage(message) {
            root.errorMessage = message;
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -14; duration: 50; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "shakeX"; to: 14; duration: 90; easing.type: Easing.InOutCubic }
        NumberAnimation { target: root; property: "shakeX"; to: -9; duration: 80; easing.type: Easing.InOutCubic }
        NumberAnimation { target: root; property: "shakeX"; to: 5; duration: 70; easing.type: Easing.InOutCubic }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 60; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: card
        width: parent.width
        height: col.implicitHeight + 40
        x: root.shakeX
        radius: Theme.cardRadius
        color: Theme.alpha(Theme.surfaceContainer, Theme.cardAlpha)
        border.width: 1
        border.color: Theme.alpha(Theme.outlineVariant, 0.5)

        // Плавное появление при старте
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: Theme.animMs * 1.5; easing.type: Theme.easing }
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 12

            Avatar {
                anchors.horizontalCenter: parent.horizontalCenter
                size: 84
                source: root.current && root.current.icon.length > 0 ? root.current.icon : ""
                name: root.displayName
            }

            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.displayName.length > 0 ? root.displayName : "Вход в систему"
                font.pixelSize: Theme.fontSize + 6
                font.bold: true
            }

            Field {
                id: loginField
                width: parent.width
                visible: Theme.showLoginField
                icon: ""
                placeholder: "Логин"
                locked: root.busy
                onAccepted: root.focusPassword()
                onTabPressed: root.focusPassword()
                onEscPressed: { passwordField.text = ""; root.focusPassword(); }
            }

            Field {
                id: passwordField
                width: parent.width
                icon: ""
                placeholder: "Пароль"
                password: true
                locked: root.busy
                onAccepted: root.doLogin()
                onTabPressed: {
                    if (loginField.visible)
                        loginField.forceFocus();
                }
                onEscPressed: passwordField.text = ""
            }

            // Строка статуса: ошибка слева, Caps Lock справа
            Item {
                width: parent.width
                height: 22

                Txt {
                    anchors.left: parent.left
                    anchors.right: capsChip.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.errorMessage
                    color: Theme.error
                    font.pixelSize: Theme.fontSize - 1
                    opacity: root.errorMessage.length > 0 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.animMs; easing.type: Theme.easing }
                    }
                }

                Rectangle {
                    id: capsChip
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: capsText.implicitWidth + 16
                    height: 22
                    radius: 11
                    color: Theme.alpha(Theme.tertiary, 0.18)
                    border.width: 1
                    border.color: Theme.alpha(Theme.tertiary, 0.6)
                    opacity: root.caps ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.animMs; easing.type: Theme.easing }
                    }
                    Txt {
                        id: capsText
                        anchors.centerIn: parent
                        text: " Caps Lock"
                        color: Theme.tertiary
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }

            // Кнопка «Войти»
            Rectangle {
                id: loginBtn
                width: parent.width
                height: 46
                radius: Theme.pillRadius + 2
                readonly property bool enabledNow: !root.busy && loginField.text.length > 0
                color: !enabledNow ? Theme.alpha(Theme.primary, 0.45)
                     : btnMouse.pressed ? Theme.alpha(Theme.primary, 0.8)
                     : btnMouse.containsMouse ? Qt.lighter(Theme.primary, 1.12)
                     : Theme.primary
                Behavior on color {
                    ColorAnimation { duration: Theme.animMs; easing.type: Theme.easing }
                }
                Txt {
                    anchors.centerIn: parent
                    text: root.busy ? "Вход…" : "Войти"
                    color: Theme.primaryText
                    font.bold: true
                    font.pixelSize: Theme.fontSize + 2
                }
                MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.doLogin()
                }
            }
        }
    }

    // Чипы пользователей (если их больше одного)
    Row {
        id: chips
        anchors.top: card.bottom
        anchors.topMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        visible: users.count > 1

        Repeater {
            model: root.um
            delegate: Rectangle {
                id: chip
                required property string name
                required property string realName
                readonly property bool selected: loginField.text === name
                height: 30
                width: chipText.implicitWidth + 24
                radius: 15
                color: selected ? Theme.primaryContainer
                     : chipMouse.containsMouse ? Theme.surfaceContainerHighest
                     : Theme.alpha(Theme.surfaceContainerHigh, Theme.panelAlpha)
                border.width: 1
                border.color: selected ? Theme.alpha(Theme.primary, 0.7) : Theme.alpha(Theme.outline, 0.28)
                Behavior on color {
                    ColorAnimation { duration: Theme.animMs; easing.type: Theme.easing }
                }
                Txt {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.realName.length > 0 ? chip.realName : chip.name
                    color: chip.selected ? Theme.fg : Theme.fgVariant
                }
                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.busy)
                            return;
                        loginField.text = chip.name;
                        passwordField.text = "";
                        root.errorMessage = "";
                        root.focusPassword();
                    }
                }
            }
        }
    }
}
