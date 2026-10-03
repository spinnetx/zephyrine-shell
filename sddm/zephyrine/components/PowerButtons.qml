import QtQuick

// Кнопки питания: сон / перезагрузка / выключение.
// Подтверждение вторым нажатием: кнопка краснеет на 3 с и показывает «Точно?».
Row {
    id: root

    spacing: 6
    // какая кнопка ждёт подтверждения: "", "suspend", "reboot", "poweroff"
    property string pending: ""

    Timer {
        id: resetTimer
        interval: 3000
        onTriggered: root.pending = ""
    }

    function press(kind) {
        if (pending === kind) {
            pending = "";
            resetTimer.stop();
            if (kind === "suspend")
                sddm.suspend();
            else if (kind === "reboot")
                sddm.reboot();
            else if (kind === "poweroff")
                sddm.powerOff();
        } else {
            pending = kind;
            resetTimer.restart();
        }
    }

    component PowerBtn: Pill {
        id: btn
        property string kind: ""
        property string glyph: ""
        readonly property bool confirming: root.pending === kind
        clickable: true
        active: confirming
        activeColor: Theme.error
        onClicked: root.press(kind)

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.glyph
            color: btn.confirming ? Theme.errorText : Theme.fgVariant
            font.pixelSize: Theme.fontSize + 1
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.confirming
            text: "Точно?"
            color: Theme.errorText
            font.bold: true
        }
    }

    PowerBtn {
        kind: "suspend"
        glyph: ""
        visible: typeof sddm !== "undefined" && sddm.canSuspend
    }
    PowerBtn {
        kind: "reboot"
        glyph: ""
        visible: typeof sddm !== "undefined" && sddm.canReboot
    }
    PowerBtn {
        kind: "poweroff"
        glyph: ""
        visible: typeof sddm !== "undefined" && sddm.canPowerOff
    }
}
