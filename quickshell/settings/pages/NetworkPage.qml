pragma ComponentBehavior: Bound

import QtQuick
import "../../"
import "../../services"
import "../../components"
import "../parts"

// Страница «Wi-Fi» раздела «Сеть и Bluetooth» (DESIGN §4.2, §6.5, §7.3): радио, список сетей, подключение/отключение,
// детали подключения, сохранённые сети. Радио, список, подключение и форма пароля — services/Wifi.qml (общий с попапом,
// логика не копируется); детали и сохранённые профили — parts/WifiData.qml (nmcli, только чтение + действия пользователя).
// Разрушительные действия (выключить радио, отключиться, забыть сеть) — SetButton с двойным нажатием.
Item {
    id: root

    property bool showAll: false         // по умолчанию показываем первые 8 сетей
    readonly property int shortCount: 8
    readonly property var nets: Wifi.networks
    readonly property var shownNets: showAll ? nets : nets.slice(0, shortCount)
    readonly property bool connectedNow: Wifi.enabled && wd.connected

    onVisibleChanged: {
        if (visible)
            pollNow();
        else
            Wifi.closeForm();
    }
    Component.onCompleted: if (visible) pollNow()

    function pollNow() {
        Wifi.refresh(false);
        wd.refresh();
    }

    // Периодическое обновление, пока страница на экране (свой таймер: Wifi.pollActive делит попап).
    Timer {
        interval: Config.wifiListPollMs
        running: root.visible && Wifi.enabled
        repeat: true
        onTriggered: root.pollNow()
    }

    WifiData {
        id: wd
    }

    // Известная сеть не подключилась из-за пароля (сохранённый пароль устарел) — спрашиваем новый.
    // В попапе то же делает Wifi.qml при открытом попапе; здесь страница делает это сама.
    Connections {
        target: Wifi
        function onMessageChanged() {
            if (!root.visible || Wifi.busy || !Wifi.messageIsError || !Wifi.attempt.known)
                return;
            if (Wifi.passwordErrRe.test(Wifi.message) || /Activation failed/i.test(Wifi.message))
                Wifi.openForm("password", Wifi.attempt.ssid, "Неверный пароль", Wifi.message);
        }
    }

    function sigIcon(s) {
        return s > 75 ? Config.icons.wifi4 : s > 50 ? Config.icons.wifi3 : s > 25 ? Config.icons.wifi2 : Config.icons.wifi1;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: 12

            Banner {
                width: parent.width
                visible: wd.errorText.length > 0
                kind: "error"
                text: wd.errorText
                detail: wd.errorRaw
                buttonText: "Скрыть"
                onClicked: wd.clearError()
            }

            // ---------- Wi-Fi: радио, список, форма ----------
            SetCard {
                width: parent.width
                title: "Wi-Fi"
                icon: !Wifi.enabled ? Config.icons.wifiOff : root.connectedNow && wd.ap ? root.sigIcon(wd.ap.signal) : Config.icons.wifi1
                chipKind: root.connectedNow ? "live" : "neutral"
                chipText: !Wifi.enabled ? "выключен"
                    : Wifi.busy && Wifi.connectingSsid !== "" ? "подключение…"
                    : root.connectedNow ? "подключено" : "не подключено"

                headerRight: [
                    // Выключение радио — с подтверждением (§7.3); включение — сразу.
                    SetButton {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: Wifi.enabled ? "danger" : "primary"
                        confirm: Wifi.enabled
                        confirmText: "Выключить Wi-Fi?"
                        text: Wifi.enabled ? "Выключить" : "Включить"
                        enabled: !Wifi.busy
                        onClicked: Wifi.setEnabled(!Wifi.enabled)
                    }
                ]

                Txt {
                    visible: root.connectedNow && wd.ap !== null
                    width: parent.width
                    elide: Text.ElideRight
                    color: Colors.fgVariant
                    text: wd.ap ? wd.ap.ssid + " · сигнал " + wd.ap.signal + "%"
                        + (wd.details.ip4.length > 0 ? " · IP " + wd.details.ip4[0].split("/")[0] : "") : ""
                }

                Txt {
                    visible: !Wifi.enabled
                    width: parent.width
                    text: "Включите Wi-Fi, чтобы увидеть сети."
                    color: Colors.fgVariant
                }

                // Ошибка последней операции без формы (например, сеть пропала из эфира).
                Txt {
                    visible: Wifi.enabled && Wifi.formMode === "" && Wifi.message !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Wifi.message
                    color: Wifi.messageIsError ? Colors.error : Colors.success
                    font.pixelSize: Config.fontSize - 1
                }

                WifiForm {
                    visible: Wifi.enabled && Wifi.formMode !== ""
                    width: parent.width
                }

                Txt {
                    visible: Wifi.enabled && Wifi.formMode === "" && root.nets.length === 0
                    width: parent.width
                    text: Wifi.scanning ? "Поиск сетей…" : "Сети не найдены"
                    color: Colors.fgVariant
                }

                Repeater {
                    model: Wifi.enabled && Wifi.formMode === "" ? root.shownNets : []

                    delegate: WifiNetworkRow {
                        id: netRow

                        required property var modelData

                        width: parent.width
                        net: modelData
                        known: Wifi.knownSsids.indexOf(modelData.ssid) >= 0
                        connecting: Wifi.busy && Wifi.connectingSsid === modelData.ssid
                        busy: Wifi.busy || wd.actBusy
                        onConnectClicked: Wifi.select(modelData)
                        onDisconnectClicked: wd.disconnectActive()
                    }
                }

                Row {
                    visible: Wifi.enabled && Wifi.formMode === ""
                    spacing: 8
                    topPadding: 4

                    SetButton {
                        visible: root.nets.length > root.shortCount
                        text: root.showAll ? "Свернуть" : "Показать все (" + root.nets.length + ")"
                        onClicked: root.showAll = !root.showAll
                    }
                    SetButton {
                        icon: Config.icons.refresh
                        text: Wifi.scanning ? "Поиск…" : "Обновить"
                        enabled: !Wifi.scanning
                        onClicked: {
                            Wifi.refresh(true);
                            wd.refresh();
                        }
                    }
                    SetButton {
                        icon: Config.icons.lock
                        text: "Скрытая сеть…"
                        enabled: !Wifi.busy
                        onClicked: Wifi.openForm("hidden", "", "", "")
                    }
                }
            }

            // ---------- детали подключения ----------
            WifiDetailsCard {
                width: parent.width
                visible: root.connectedNow
                store: wd
            }

            // ---------- сохранённые сети ----------
            WifiSavedCard {
                width: parent.width
                store: wd
            }
        }
    }

    ScrollBar {
        target: flick
    }
}
