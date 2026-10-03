pragma ComponentBehavior: Bound

import QtQuick
import "../../"
import "../../components"

// Карточка запроса сопряжения (этап N3): подтверждение кода («Совпадает»/«Отклонить»), показ кода/PIN для ввода
// на устройстве, поле ввода PIN/passkey, разрешение входящего сопряжения/сервиса. Данные — BtAgent (agent.request);
// сама ничего не решает: только кнопки -> agent.confirm()/reject()/sendPin()/sendPasskey().
SetCard {
    id: root

    required property var agent
    // Запрос на отмену показа (display_*): страница заодно отменяет само сопряжение.
    signal cancelRequested

    readonly property var req: agent.request
    readonly property string kind: req ? String(req.kind) : ""
    readonly property string who: req ? (String(req.device) !== "" ? String(req.device) : String(req.address)) : ""
    readonly property bool isInput: kind === "pin" || kind === "passkey"

    function pad(n) {
        let s = String(Math.max(0, Math.floor(n ?? 0)));
        while (s.length < 6)
            s = "0" + s;
        return s;
    }
    // «123 456» — для чтения вслух; цифры одной группой не сливаются.
    function spaced(n) {
        const s = pad(n);
        return s.slice(0, 3) + " " + s.slice(3);
    }
    function serviceName(uuid) {
        const u = String(uuid ?? "").toLowerCase().slice(4, 8);
        const names = { "110a": "источник звука", "110b": "приём звука (A2DP)", "110c": "управление медиа", "110e": "управление медиа (AVRCP)",
            "111e": "гарнитура (HFP)", "1108": "гарнитура (HSP)", "1124": "устройство ввода (HID)", "1812": "устройство ввода (HID)", "1105": "передача файлов" };
        return names[u] ?? String(uuid ?? "");
    }
    // Проверка ввода на стороне UI (то же правило проверяет и агент): passkey — 1..6 цифр, PIN — 1..16 символов.
    function inputValid(text) {
        if (kind === "passkey")
            return /^[0-9]{1,6}$/.test(text);
        if (kind === "pin")
            return text.length >= 1 && text.length <= 16;
        return false;
    }
    function submit() {
        const t = field.text;
        if (!inputValid(t))
            return;
        field.text = "";
        if (kind === "passkey")
            agent.sendPasskey(t);
        else
            agent.sendPin(t);
    }

    visible: req !== null
    title: "Запрос сопряжения"
    icon: Config.icons.bt
    chipKind: agent.awaiting ? "restart" : "neutral"
    chipText: agent.awaiting ? "ждёт ответа · " + agent.remaining + " с" : ""

    onReqChanged: {
        field.text = "";
        field.revealed = false;
        if (isInput)
            focusTimer.restart();
    }
    Timer {
        id: focusTimer
        interval: 80
        onTriggered: field.focusInput()
    }

    // ---- пояснение ----
    Txt {
        width: parent.width
        wrapMode: Text.WordWrap
        text: {
            switch (root.kind) {
            case "confirm":
                return "«" + root.who + "» запрашивает сопряжение. Убедитесь, что на устройстве показан такой же код, и подтвердите.";
            case "display_passkey":
                return "Введите этот код на устройстве «" + root.who + "» (клавиатуре, телефоне). Сопряжение продолжится само.";
            case "display_pin":
                return "Введите этот PIN на устройстве «" + root.who + "».";
            case "passkey":
                return "Устройство «" + root.who + "» просит код (до 6 цифр). Введите код, который показан на нём.";
            case "pin":
                return "Устройство «" + root.who + "» просит PIN (до 16 символов). Обычно это 0000 или 1234 — смотрите инструкцию устройства.";
            case "authorize":
                return "«" + root.who + "» хочет сопрячься с этим компьютером. Разрешить?";
            case "authorize_service":
                return "«" + root.who + "» хочет использовать сервис: " + root.serviceName(root.req?.uuid) + ". Разрешить?";
            }
            return "";
        }
    }

    // ---- крупный код ----
    Txt {
        visible: root.kind === "confirm" || root.kind === "display_passkey"
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Config.fontSize * 2.6
        font.bold: true
        font.letterSpacing: 4
        color: Colors.primary
        text: root.spaced(root.req?.passkey)
    }
    // Сколько цифр уже введено на устройстве (DisplayPasskey).
    Row {
        visible: root.kind === "display_passkey"
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6
        Repeater {
            model: 6
            delegate: Rectangle {
                required property int index
                width: 10
                height: 10
                radius: 5
                color: index < (root.req?.entered ?? 0) ? Colors.primary : Qt.alpha(Colors.outline, 0.4)
            }
        }
    }
    Txt {
        visible: root.kind === "display_pin"
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Config.fontSize * 2.2
        font.bold: true
        color: Colors.primary
        text: String(root.req?.pin ?? "")
    }

    // ---- ввод PIN/passkey ----
    PopField {
        id: field
        visible: root.isInput
        width: Math.min(parent.width, 280)
        placeholder: root.kind === "passkey" ? "Код (цифры)" : "PIN"
        onAccepted: root.submit()
        onEscaped: root.agent.reject()
    }

    Txt {
        visible: root.agent.inputError !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        color: Colors.error
        font.pixelSize: Config.fontSize - 1
        text: root.agent.inputError
    }

    // ---- кнопки ----
    Row {
        spacing: 8
        SetButton {
            visible: root.kind === "confirm"
            text: "Совпадает"
            kind: "primary"
            onClicked: root.agent.confirm()
        }
        SetButton {
            visible: root.kind === "authorize" || root.kind === "authorize_service"
            text: "Разрешить"
            kind: "primary"
            onClicked: root.agent.confirm()
        }
        SetButton {
            visible: root.isInput
            text: "Подтвердить"
            kind: "primary"
            enabled: root.inputValid(field.text)
            onClicked: root.submit()
        }
        SetButton {
            visible: root.agent.awaiting
            text: "Отклонить"
            onClicked: root.agent.reject()
        }
        SetButton {
            visible: !root.agent.awaiting
            text: "Отмена"
            onClicked: root.cancelRequested()
        }
    }
}
