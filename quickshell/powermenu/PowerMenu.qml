pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"
import "../services"
import "../components"

// Меню питания: центрированная карточка с шестью кнопками (IPC `powermenu`, кнопка питания в баре).
// Навигация: ←/→ + Enter, горячие клавиши L/E/S/R/P/I, Esc или клик вне карточки — закрыть.
// Необратимые действия (выход, перезагрузка, выключение) требуют второго нажатия в течение 3 с.
PanelWindow {
    id: win

    readonly property bool open: Overlays.powerOpen
    readonly property int confirmMs: 3000

    // Действия: key — горячая клавиша (Qt.Key_*), ru — та же клавиша в русской раскладке, danger — требует подтверждения.
    readonly property var actions: [
        { label: "Заблокировать", icon: Config.icons.lock, hint: "L", key: Qt.Key_L, ru: "д", danger: false, cmd: Config.lockCommand },
        { label: "Выйти", icon: Config.icons.logout, hint: "E", key: Qt.Key_E, ru: "у", danger: true, cmd: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
        { label: "Спящий режим", icon: Config.icons.sleep, hint: "S", key: Qt.Key_S, ru: "ы", danger: false, cmd: ["systemctl", "suspend"] },
        { label: "Перезагрузка", icon: Config.icons.restart, hint: "R", key: Qt.Key_R, ru: "к", danger: true, cmd: ["systemctl", "reboot"] },
        { label: "Выключение", icon: Config.icons.power, hint: "P", key: Qt.Key_P, ru: "з", danger: true, cmd: ["systemctl", "poweroff"] },
        // Без cmd: открывает окно настроек шелла, а не запускает команду.
        { label: "Настройки", icon: Config.icons.settings, hint: "I", key: Qt.Key_I, ru: "ш", danger: false, cmd: null }
    ]

    // Выбранная кнопка и кнопка, ожидающая подтверждения (-1 — нет).
    property int current: 0
    property int armed: -1

    screen: Overlays.screen
    visible: open || t > 0.001
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "zephyrine-powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property real t: open ? 1 : 0
    Behavior on t {
        NumberAnimation { duration: 180; easing.type: Config.animEasing }
    }

    function select(i) {
        if (i !== current)
            armed = -1;
        current = i;
    }

    // Нажатие на кнопку: безопасное действие — сразу; опасное — сначала «Точно?», затем выполнение.
    function activate(i) {
        const a = actions[i];
        if (a.danger && armed !== i) {
            current = i;
            armed = i;
            confirmTimer.restart();
            return;
        }
        confirmTimer.stop();
        armed = -1;
        Overlays.closePower();
        if (a.cmd)
            Quickshell.execDetached(a.cmd);
        else
            Overlays.openSettings();
    }

    Timer {
        id: confirmTimer
        interval: win.confirmMs
        onTriggered: win.armed = -1
    }

    onOpenChanged: {
        if (open) {
            current = 0;
            armed = -1;
            confirmTimer.stop();
            keys.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Overlays.closePower()
    }

    Rectangle {
        id: card
        readonly property int btnW: 132
        readonly property int btnH: 140

        width: row.implicitWidth + Config.popoutPadding * 4
        height: btnH + Config.popoutPadding * 4 + hintText.implicitHeight + 6
        anchors.centerIn: parent
        radius: Config.barRadius + 4
        color: Qt.alpha(Colors.background, 0.94)
        border.width: 1
        border.color: Qt.alpha(Colors.outlineVariant, 0.6)
        opacity: win.t
        scale: 0.95 + 0.05 * win.t

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    Overlays.closePower();
                } else if (event.key === Qt.Key_Left) {
                    win.select((win.current + win.actions.length - 1) % win.actions.length);
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                    win.select((win.current + 1) % win.actions.length);
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    win.activate(win.current);
                } else {
                    const i = win.actions.findIndex(a => a.key === event.key || a.ru === event.text.toLowerCase());
                    if (i < 0)
                        return;
                    win.activate(i);
                }
                event.accepted = true;
            }
        }

        Row {
            id: row
            anchors.horizontalCenter: parent.horizontalCenter
            y: Config.popoutPadding * 2
            spacing: Config.popoutPadding

            Repeater {
                model: win.actions

                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    required property int index
                    readonly property bool current: win.current === btn.index
                    readonly property bool armed: win.armed === btn.index
                    readonly property color accent: modelData.danger ? Colors.error : Colors.primary

                    width: card.btnW
                    height: card.btnH
                    radius: Config.barRadius
                    color: armed ? Qt.alpha(Colors.error, 0.28)
                                 : current ? Qt.alpha(Colors.primaryContainer, 0.75)
                                           : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
                    border.width: 1
                    border.color: armed ? Colors.error : current ? Qt.alpha(Colors.primary, 0.7) : Qt.alpha(Colors.outline, 0.28)
                    Behavior on color {
                        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: btn.modelData.icon
                            color: btn.accent
                            font.pixelSize: 44
                        }
                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: btn.armed ? "Точно?" : btn.modelData.label
                            color: btn.armed ? Colors.error : Colors.fg
                            font.bold: btn.armed
                        }
                        // Подсказка горячей клавиши.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 22
                            height: 22
                            radius: 6
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(Colors.outline, 0.5)

                            Txt {
                                anchors.centerIn: parent
                                text: btn.modelData.hint
                                color: Colors.fgVariant
                                font.pixelSize: Config.fontSize - 2
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: win.select(btn.index)
                        onClicked: win.activate(btn.index)
                    }
                }
            }
        }

        Txt {
            id: hintText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.popoutPadding
            text: "←/→ выбор · Enter — подтвердить · Esc — закрыть"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
            opacity: 0.7
        }
    }
}
