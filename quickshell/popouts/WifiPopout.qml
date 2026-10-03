pragma ComponentBehavior: Bound

import QtQuick
import "../"
import "../components"
import "../services"

// Wi-Fi: статус, текущая сеть, список доступных сетей (клик — подключение), rescan, вкл/выкл радио.
Item {
    id: root

    readonly property bool active: PopoutState.kind === "wifi"

    implicitWidth: 300
    implicitHeight: Wifi.formMode === "" ? col.implicitHeight : form.implicitHeight

    // Обновляем список при открытии; пока попап открыт — периодически (Wifi.pollActive).
    onActiveChanged: if (active) Wifi.refresh(false)
    Component.onCompleted: Wifi.refresh(false)
    Binding {
        target: Wifi
        property: "pollActive"
        value: root.active
    }

    // Закрепление снято (клик вне карточки / Esc в карточке) или попап сменился — форма закрывается.
    Connections {
        target: PopoutState
        function onPinnedChanged() {
            if (!PopoutState.pinned)
                Wifi.closeForm();
        }
        function onKindChanged() {
            if (PopoutState.kind !== "wifi")
                Wifi.closeForm();
        }
    }
    // Любая смена формы — очищаем поля (пароль не залёживается в памяти UI).
    Connections {
        target: Wifi
        function onFormModeChanged() {
            pw.text = "";
            pw.revealed = false;
            hiddenSsid.text = "";
            if (Wifi.formMode !== "")
                focusTimer.restart();
        }
    }
    // Фокус после того, как HyprlandFocusGrab выдал окну клавиатуру.
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: (Wifi.formMode === "hidden" ? hiddenSsid : pw).focusInput()
    }

    function submit() {
        if (Wifi.busy)
            return;
        Wifi.submitForm(hiddenSsid.text, pw.text);
        pw.text = "";   // поле чистим сразу после отправки; пароль ушёл в stdin nmcli
    }

    function sigIcon(s) {
        return s > 75 ? Config.icons.wifi4 : s > 50 ? Config.icons.wifi3 : s > 25 ? Config.icons.wifi2 : Config.icons.wifi1;
    }

    Column {
        id: col
        visible: Wifi.formMode === ""
        width: parent.width
        spacing: 8

        // Заголовок + переключатель радио
        Item {
            width: parent.width
            height: 26

            Txt {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                text: Net.kind === "wifi" ? root.sigIcon(Net.signal) : Net.kind === "ethernet" ? Config.icons.ethernet : Config.icons.wifiOff
                color: Colors.primary
                font.pixelSize: Config.iconSize + 2
            }
            Txt {
                anchors.left: title.right
                anchors.leftMargin: 8
                anchors.right: sw.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                font.bold: true
                text: !Wifi.enabled ? "Wi-Fi выключен"
                    : Net.kind === "wifi" ? Net.ssid
                    : Net.kind === "ethernet" ? "Ethernet" : "Нет подключения"
            }
            PopSwitch {
                id: sw
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: Wifi.enabled
                onToggled: value => Wifi.setEnabled(value)
            }
        }

        Txt {
            visible: Net.kind === "wifi"
            text: "Подключено · сигнал " + Net.signal + "%"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.35)
        }

        Txt {
            visible: !Wifi.enabled
            text: "Включите Wi-Fi, чтобы увидеть сети"
            color: Colors.fgVariant
        }
        Txt {
            visible: Wifi.enabled && Wifi.networks.length === 0
            text: Wifi.scanning ? "Поиск сетей…" : "Сети не найдены"
            color: Colors.fgVariant
        }

        ListView {
            id: list
            visible: Wifi.enabled && Wifi.networks.length > 0
            width: parent.width
            height: visible ? Math.min(contentHeight, 224) : 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: Wifi.networks

            delegate: PopItem {
                id: net

                required property var modelData

                width: list.width
                highlighted: modelData.active
                onClicked: if (!modelData.active) Wifi.select(modelData)

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sigIcon(net.modelData.signal)
                    color: net.modelData.active ? Colors.primary : Colors.fg
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 172
                    elide: Text.ElideRight
                    text: net.modelData.ssid
                    font.bold: net.modelData.active
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    text: Wifi.connectingSsid === net.modelData.ssid ? Config.icons.refresh : net.modelData.active ? Config.icons.check : net.modelData.security !== "" ? Config.icons.lock : ""
                    color: net.modelData.active ? Colors.success : Colors.fgVariant
                    font.pixelSize: Config.fontSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    text: net.modelData.signal + "%"
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                }
            }
        }

        // Результат последней операции nmcli (успех / «Secrets were required…» и т.п.).
        Txt {
            visible: Wifi.message !== "" || Wifi.busy
            width: parent.width
            wrapMode: Text.WordWrap
            text: Wifi.busy && Wifi.connectingSsid !== "" ? "Подключение к " + Wifi.connectingSsid + "…" : Wifi.message
            color: Wifi.messageIsError ? Colors.error : Colors.success
            font.pixelSize: Config.fontSize - 1
        }

        PopItem {
            width: parent.width
            enabled: Wifi.enabled
            onClicked: Wifi.openForm("hidden", "", "", "")
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.lock
                color: Colors.tertiary
                font.pixelSize: Config.iconSize
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Скрытая сеть…"
            }
        }

        Row {
            spacing: 8

            PopItem {
                width: 120
                enabled: Wifi.enabled
                onClicked: Wifi.refresh(true)
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.icons.refresh
                    color: Colors.tertiary
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Wifi.scanning ? "Поиск…" : "Обновить"
                }
            }
            // Глубокая ссылка в окно настроек (nm-connection-editor не используем — Wifi.hasEditor больше не нужен).
            PopItem {
                width: 130
                onClicked: Overlays.openSettings("network/wifi")
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.icons.settings
                    color: Colors.tertiary
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Настройки…"
                }
            }
        }
    }

    // Форма подключения (пароль новой сети / скрытая сеть) — вместо списка, в той же карточке.
    Column {
        id: form
        visible: Wifi.formMode !== ""
        width: parent.width
        spacing: 8

        Txt {
            width: parent.width
            font.bold: true
            elide: Text.ElideRight
            text: Wifi.formMode === "hidden" ? "Скрытая сеть" : "Подключение к " + Wifi.formSsid
        }

        PopField {
            id: hiddenSsid
            visible: Wifi.formMode === "hidden"
            width: parent.width
            placeholder: "Имя сети (SSID)"
            fieldEnabled: !Wifi.formBusy
            onAccepted: pw.focusInput()
            onTabbed: pw.focusInput()
            onEscaped: Wifi.cancelForm()
        }

        PopField {
            id: pw
            width: parent.width
            secret: true
            placeholder: Wifi.formMode === "hidden" ? "Пароль (пусто — открытая сеть)" : "Пароль"
            fieldEnabled: !Wifi.formBusy
            onAccepted: root.submit()
            onTabbed: if (Wifi.formMode === "hidden") hiddenSsid.focusInput()
            onEscaped: Wifi.cancelForm()
        }

        Txt {
            visible: Wifi.formMode === "hidden"
            width: parent.width
            text: "Защита: WPA/WPA2 (определяется автоматически)"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
        }

        // Состояние «Подключение…»
        Row {
            visible: Wifi.formBusy
            spacing: 8
            Txt {
                id: spinner
                text: Config.icons.refresh
                color: Colors.primary
                font.pixelSize: Config.iconSize
                RotationAnimation on rotation {
                    running: Wifi.formBusy
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }
            Txt {
                text: "Подключение…"
                color: Colors.fgVariant
            }
        }

        // Ошибка: по-русски красным + сырое сообщение nmcli мелким.
        Column {
            visible: Wifi.formError !== "" && !Wifi.formBusy
            width: parent.width
            spacing: 2
            Txt {
                width: parent.width
                wrapMode: Text.WordWrap
                text: Wifi.formError
                color: Colors.error
            }
            Txt {
                visible: Wifi.formRaw !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: Wifi.formRaw
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 3
            }
        }

        Row {
            spacing: 8

            PopItem {
                id: okBtn
                readonly property bool ready: !Wifi.busy && (Wifi.formMode === "hidden" ? hiddenSsid.text.trim() !== "" : pw.text !== "")
                width: 140
                centered: true
                clickable: ready
                highlighted: true
                opacity: ready ? 1 : 0.5
                onClicked: root.submit()
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Подключиться"
                    color: Colors.primary
                }
            }
            PopItem {
                width: 140
                centered: true
                onClicked: Wifi.cancelForm()
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Отмена"
                }
            }
        }
    }
}
