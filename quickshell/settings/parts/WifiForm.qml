import QtQuick
import "../../"
import "../../components"
import "../../services"

// Форма подключения на странице Wi-Fi: пароль новой сети или скрытая сеть. Состояние и логика — services/Wifi.qml
// (formMode/formError/submitForm/cancelForm, пароль уходит только в stdin nmcli); здесь только поля и кнопки.
Column {
    id: root

    spacing: 8

    function submit() {
        if (Wifi.busy)
            return;
        Wifi.submitForm(hiddenSsid.text, pw.text);
        pw.text = "";   // пароль уже ушёл в stdin nmcli — поле чистим сразу
    }

    // Любая смена формы — поля очищаются (пароль не залёживается в памяти UI).
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
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: (Wifi.formMode === "hidden" ? hiddenSsid : pw).focusInput()
    }

    Txt {
        width: parent.width
        font.bold: true
        elide: Text.ElideRight
        text: Wifi.formMode === "hidden" ? "Скрытая сеть" : "Подключение к " + Wifi.formSsid
    }

    PopField {
        id: hiddenSsid
        visible: Wifi.formMode === "hidden"
        width: Math.min(parent.width, 360)
        placeholder: "Имя сети (SSID)"
        fieldEnabled: !Wifi.formBusy
        onAccepted: pw.focusInput()
        onTabbed: pw.focusInput()
        onEscaped: Wifi.cancelForm()
    }

    PopField {
        id: pw
        width: Math.min(parent.width, 360)
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

    Row {
        visible: Wifi.formBusy
        spacing: 8
        Txt {
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
        SetButton {
            kind: "primary"
            text: "Подключиться"
            enabled: !Wifi.busy && (Wifi.formMode === "hidden" ? hiddenSsid.text.trim() !== "" : pw.text !== "")
            onClicked: root.submit()
        }
        SetButton {
            text: "Отмена"
            onClicked: Wifi.cancelForm()
        }
    }
}
