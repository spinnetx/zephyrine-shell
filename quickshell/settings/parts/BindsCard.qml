import QtQuick
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"

// Карточка «Сочетания клавиш» (DESIGN §4.4, Y2): действия Zephyrine с их комбинациями (изменить / добавить / сбросить)
// и остальные бинды Hyprland только для просмотра. Список — `zephyrine-settings binds list`, запись — SettingsCli.set
// (`binds.<действие>`), проверка занятости — `binds check`. Захват: на время ввода CLI включает submap `zp_capture`
// (без биндов, иначе Hyprland перехватит SUPER+… раньше окна), сторож сбрасывает его сам.
SetCard {
    id: root

    title: "Сочетания клавиш"
    icon: Config.icons.keyboard

    property var actions: []
    property var others: []
    property bool showOthers: false
    property string error: ""
    property bool sent: false

    // захват
    property string capId: ""            // действие, для которого ловим комбинацию ("" — нет захвата)
    property string capCombo: ""         // пойманная комбинация
    property var capConflicts: []
    property bool capChecking: false
    property string capHint: ""
    property string capState: ""         // "" | starting | ready | failed (режим захвата подтверждён / не включился)
    property string capDiag: ""

    function refresh() {
        if (!listProc.running)
            listProc.running = true;
    }
    function lastJson(text) {
        const ls = String(text).split("\n").filter(l => l.trim() !== "");
        for (let i = ls.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(ls[i]);
                if (o && typeof o === "object")
                    return o;
            } catch (e) {}
        }
        return null;
    }
    function actionById(id) {
        return actions.find(a => a.id === id);
    }

    // ---- захват комбинации
    readonly property var keyNames: ({
        [Qt.Key_Space]: "space", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Tab]: "Tab",
        [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up",
        [Qt.Key_Down]: "Down", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Prior",
        [Qt.Key_PageDown]: "Next", [Qt.Key_Insert]: "Insert", [Qt.Key_Delete]: "Delete", [Qt.Key_Print]: "Print",
        [Qt.Key_Minus]: "minus", [Qt.Key_Equal]: "equal", [Qt.Key_Comma]: "comma", [Qt.Key_Period]: "period",
        [Qt.Key_Slash]: "slash", [Qt.Key_Semicolon]: "semicolon", [Qt.Key_Apostrophe]: "apostrophe",
        [Qt.Key_BracketLeft]: "bracketleft", [Qt.Key_BracketRight]: "bracketright", [Qt.Key_Backslash]: "backslash",
        [Qt.Key_QuoteLeft]: "grave",
        // цифры с Shift приходят как символы: возвращаем клавишу
        [Qt.Key_Exclam]: "1", [Qt.Key_At]: "2", [Qt.Key_NumberSign]: "3", [Qt.Key_Dollar]: "4", [Qt.Key_Percent]: "5",
        [Qt.Key_AsciiCircum]: "6", [Qt.Key_Ampersand]: "7", [Qt.Key_Asterisk]: "8", [Qt.Key_ParenLeft]: "9",
        [Qt.Key_ParenRight]: "0"
    })
    function keyName(k) {
        if (k >= Qt.Key_A && k <= Qt.Key_Z)
            return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9)
            return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F12)
            return "F" + (k - Qt.Key_F1 + 1);
        return keyNames[k] ?? "";
    }
    function startCapture(id) {
        capId = id;
        capCombo = "";
        capConflicts = [];
        capHint = "";
        capState = "starting";
        capDiag = "";
        capProc.command = [Config.settingsCli, "binds", "capture"];
        capProc.running = true;
    }
    function endCapture() {
        capTimeout.stop();
        if (capState !== "failed") {
            relProc.command = [Config.settingsCli, "binds", "release"];
            relProc.running = true;
        }
        capState = "";
        capId = "";
        capCombo = "";
        capConflicts = [];
        capHint = "";
    }
    function onKey(ev) {
        if (capId === "" || capState !== "ready")
            return;
        ev.accepted = true;
        if (ev.key === Qt.Key_Escape) {
            endCapture();
            return;
        }
        if (ev.key === Qt.Key_Meta || ev.key === Qt.Key_Super_L || ev.key === Qt.Key_Super_R || ev.key === Qt.Key_Shift
                || ev.key === Qt.Key_Control || ev.key === Qt.Key_Alt || ev.key === Qt.Key_AltGr)
            return;
        const name = keyName(ev.key);
        if (name === "") {
            capHint = "Эта клавиша не поддерживается (нужна латинская раскладка)";
            return;
        }
        const mods = [];
        if (ev.modifiers & Qt.MetaModifier)
            mods.push("SUPER");
        if (ev.modifiers & Qt.ShiftModifier)
            mods.push("SHIFT");
        if (ev.modifiers & Qt.ControlModifier)
            mods.push("CTRL");
        if (ev.modifiers & Qt.AltModifier)
            mods.push("ALT");
        capHint = "";
        capCombo = mods.concat([name]).join(" + ");
        capTimeout.stop();
        relProc.command = [Config.settingsCli, "binds", "release"];
        relProc.running = true;
        capState = "";
        checkCombo(capCombo);
    }
    function checkCombo(combo) {
        capCombo = combo;
        capChecking = true;
        checkProc.command = [Config.settingsCli, "binds", "check", combo, "--ignore", capId];
        checkProc.running = true;
    }
    // Ручной ввод ("SUPER + SHIFT + K"): запасной путь, если режим захвата не включился. Ничего не нажимается в Hyprland.
    function submitManual() {
        const parts = manualField.text.split("+").map(p => p.trim()).filter(p => p !== "");
        if (parts.length === 0)
            return;
        const mods = parts.slice(0, -1).map(p => p.toUpperCase());
        const combo = mods.concat([parts[parts.length - 1]]).join(" + ");
        if (capState === "ready") {
            relProc.command = [Config.settingsCli, "binds", "release"];
            relProc.running = true;
        }
        capTimeout.stop();
        capState = "";
        checkCombo(combo);
    }
    function assign(replace) {
        const a = actionById(capId);
        if (!a)
            return;
        const combos = replace ? [capCombo] : a.combos.concat([capCombo]);
        sent = true;
        error = "";
        SettingsCli.set({ ["binds." + capId]: combos });
        capId = "";
        capCombo = "";
    }
    function removeCombo(a, c) {
        const rest = a.combos.filter(x => x !== c);
        if (rest.length === 0)
            return;
        sent = true;
        error = "";
        SettingsCli.set({ ["binds." + a.id]: rest });
    }
    function resetAction(a) {
        sent = true;
        error = "";
        SettingsCli.run(["reset", "binds." + a.id]);
    }

    Connections {
        target: SettingsCli
        function onFinished(res, code) {
            if (!root.sent)
                return;
            root.sent = false;
            root.error = code === 0 ? "" : SettingsCli.errorText(res, code);
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
    Component.onDestruction: if (capId !== "") endCapture()

    Timer {
        id: capTimeout
        interval: 15000
        onTriggered: root.endCapture()
    }

    Process {
        id: listProc
        command: [Config.settingsCli, "binds", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.lastJson(text);
                if (o && o.binds) {
                    root.actions = o.binds.actions;
                    root.others = o.binds.others;
                } else {
                    root.error = "Не удалось получить список сочетаний";
                }
            }
        }
    }
    Process {
        id: capProc
        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.lastJson(text);
                const c = o ? o.capture : null;
                if (root.capId === "")
                    return;
                if (c && c.active) {
                    root.capState = "ready";
                    capTimeout.restart();
                    grab.forceActiveFocus();
                } else {
                    // режим не включился: нажатые сочетания СРАБОТАЛИ бы, поэтому клавиши не принимаем
                    root.capState = "failed";
                    root.capDiag = (c && c.diagnostic) ? c.diagnostic : "не удалось запустить zephyrine-settings binds capture";
                }
            }
        }
    }
    Process { id: relProc }
    Process {
        id: checkProc
        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.lastJson(text);
                root.capChecking = false;
                root.capConflicts = (o && o.conflicts) ? o.conflicts : [];
            }
        }
    }

    // Невидимый приёмник клавиш: на время захвата держит фокус.
    FocusScope {
        id: grab
        width: 0
        height: 0
        focus: root.capId !== ""
        Keys.onPressed: ev => root.onKey(ev)
    }

    Txt {
        width: parent.width
        text: "Действия Zephyrine. «Изменить» — нажмите нужное сочетание (Esc — отмена)."
        color: Colors.fgVariant
        font.pixelSize: Config.fontSize - 1
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.actions
        delegate: Column {
            id: arow
            required property var modelData
            width: root.width - Config.popoutPadding * 2
            spacing: 4

            Item {
                width: parent.width
                height: 36
                Txt {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    width: 180
                    text: arow.modelData.label
                    elide: Text.ElideRight
                }
                Row {
                    anchors {
                        left: parent.left
                        leftMargin: 190
                        right: btns.left
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6
                    Repeater {
                        model: arow.modelData.combos
                        delegate: StatusChip {
                            required property string modelData
                            kind: "neutral"
                            text: modelData
                            tooltip: arow.modelData.combos.length > 1 ? "Клик — убрать это сочетание" : ""
                            MouseArea {
                                anchors.fill: parent
                                enabled: arow.modelData.combos.length > 1
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeCombo(arow.modelData, parent.modelData)
                            }
                        }
                    }
                }
                Row {
                    id: btns
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6
                    SetButton {
                        text: root.capId === arow.modelData.id ? (root.capState === "ready" ? "Ждём…" : "…") : "Изменить"
                        enabled: root.capId === "" || root.capId === arow.modelData.id
                        onClicked: root.capId === arow.modelData.id ? root.endCapture() : root.startCapture(arow.modelData.id)
                    }
                    SetButton {
                        visible: arow.modelData.custom
                        icon: Config.icons.close
                        tooltip: "Вернуть по умолчанию"
                        onClicked: root.resetAction(arow.modelData)
                    }
                }
            }

            // состояние захвата для этого действия
            Rectangle {
                visible: root.capId === arow.modelData.id
                width: parent.width
                height: capCol.implicitHeight + 16
                radius: Config.popoutRadius / 2
                color: Qt.alpha(Colors.primary, 0.12)
                border.width: 1
                border.color: Qt.alpha(Colors.primary, 0.4)
                Column {
                    id: capCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        margins: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6
                    Txt {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: root.capState === "starting" ? "Включаем режим захвата… (не нажимайте сочетание)"
                            : root.capState === "failed" ? "Режим захвата не включился — нажимать сочетания нельзя, они сработают. Введите сочетание текстом."
                            : root.capCombo === "" ? "Нажмите сочетание… (Esc — отмена)"
                            : root.capChecking ? root.capCombo + " · проверяем…"
                            : root.capConflicts.length === 0 ? root.capCombo + " · свободно ✓"
                            : root.capCombo + " · занято: " + root.capConflicts.map(c => c.label).join(", ")
                        color: root.capCombo !== "" && root.capConflicts.length > 0 ? Colors.error : Colors.fg
                    }
                    Txt {
                        visible: root.capState === "failed" && root.capDiag !== ""
                        width: parent.width
                        text: root.capDiag + ". Проверьте, что hyprland.lua перечитан (hyprctl reload) и в нём есть hl.define_submap(\"zp_capture\")."
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 2
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        visible: (root.capState === "ready" || root.capState === "failed")
                        spacing: 8
                        PopField {
                            id: manualField
                            width: 260
                            placeholder: "или вручную: SUPER + SHIFT + K"
                            onAccepted: root.submitManual()
                        }
                        SetButton {
                            text: "Проверить"
                            onClicked: root.submitManual()
                        }
                        SetButton {
                            visible: root.capState === "failed"
                            text: "Отмена"
                            onClicked: root.endCapture()
                        }
                    }
                    Txt {
                        visible: root.capHint !== ""
                        width: parent.width
                        text: root.capHint
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 1
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        visible: root.capCombo !== "" && !root.capChecking && root.capConflicts.length === 0
                        spacing: 8
                        SetButton {
                            text: "Заменить"
                            kind: "primary"
                            onClicked: root.assign(true)
                        }
                        SetButton {
                            text: "Добавить ещё одно"
                            onClicked: root.assign(false)
                        }
                        SetButton {
                            text: "Отмена"
                            onClicked: root.endCapture()
                        }
                    }
                }
            }
        }
    }

    Txt {
        visible: root.error.length > 0
        width: parent.width
        text: root.error
        color: Colors.error
        wrapMode: Text.WordWrap
    }

    SetButton {
        visible: root.others.length > 0
        text: root.showOthers ? "Скрыть остальные" : "Остальные сочетания Hyprland (только просмотр): " + root.others.length
        onClicked: root.showOthers = !root.showOthers
    }
    Column {
        visible: root.showOthers
        width: parent.width
        spacing: 2
        Repeater {
            model: root.others
            delegate: Row {
                required property var modelData
                width: root.width - Config.popoutPadding * 2
                spacing: 12
                Txt {
                    width: 190
                    text: modelData.combo
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width - 202
                    text: modelData.description !== "" ? modelData.description
                        : modelData.dispatcher === "__lua" ? "действие из hyprland.lua (без описания)" : (modelData.dispatcher + " " + modelData.arg).trim()
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                    elide: Text.ElideRight
                }
            }
        }
    }
}
