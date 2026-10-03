import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"

// Карточка «Автозапуск» (DESIGN §4.4, модель A, Y4): управляемый список `autostart` из settings.json (включить/выключить,
// задержка, удалить, добавить, «запустить сейчас») + инфраструктурные строки hyprland.lua только для просмотра
// (`zephyrine-settings autostart`). Изменения вступают в силу со следующего входа в сессию.
SetCard {
    id: root

    title: "Автозапуск"
    icon: Config.icons.power

    property var system: []
    property bool showSystem: false
    property string error: ""
    property bool sent: false

    readonly property var defaults: [
        { id: "telegram", name: "Telegram", cmd: "Telegram", enabled: true, delaySec: 0 },
        { id: "zen", name: "Zen Browser", cmd: "zen-browser", enabled: true, delaySec: 0 },
        { id: "viber", name: "Viber", cmd: "QT_QPA_PLATFORM=wayland viber", enabled: true, delaySec: 5 }
    ]
    readonly property var entries: {
        const v = Prefs.lookup(Prefs.file, "autostart");
        return Array.isArray(v) ? v : defaults;
    }

    function copyEntries() {
        return entries.map(e => ({ id: e.id, name: e.name, cmd: e.cmd, enabled: e.enabled, delaySec: e.delaySec }));
    }
    function save(arr) {
        error = "";
        sent = true;
        SettingsCli.set({ "autostart": arr });
    }
    function patch(i, field, v) {
        const a = copyEntries();
        a[i][field] = v;
        save(a);
    }
    function slug(name) {
        let s = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30);
        if (s === "")
            s = "app";
        const used = entries.map(e => e.id);
        let id = s, n = 2;
        while (used.indexOf(id) >= 0)
            id = s + "-" + n++;
        return id;
    }
    function add() {
        const name = nameField.text.trim(), cmd = cmdField.text.trim();
        if (name === "" || cmd === "") {
            error = "Укажите название и команду";
            return;
        }
        const a = copyEntries();
        a.push({ id: slug(name), name: name, cmd: cmd, enabled: true, delaySec: Math.max(0, Math.min(600, parseInt(delayField.text) || 0)) });
        save(a);
        nameField.text = "";
        cmdField.text = "";
        delayField.text = "";
    }

    Connections {
        target: SettingsCli
        function onFinished(res, code) {
            if (!root.sent)
                return;
            root.sent = false;
            root.error = code === 0 ? "" : SettingsCli.errorText(res, code);
        }
    }

    Component.onCompleted: sysProc.running = true

    Process {
        id: sysProc
        command: [Config.settingsCli, "autostart"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ls = String(text).split("\n").filter(l => l.trim() !== "");
                for (let i = ls.length - 1; i >= 0; i--) {
                    try {
                        const o = JSON.parse(ls[i]);
                        if (o.system) {
                            root.system = o.system;
                            return;
                        }
                    } catch (e) {}
                }
            }
        }
    }

    Txt {
        width: parent.width
        text: "Запускается при входе в сессию. Изменения вступают в силу со следующего входа."
        color: Colors.fgVariant
        font.pixelSize: Config.fontSize - 1
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.entries
        delegate: Item {
            id: row
            required property int index
            required property var modelData
            width: root.width - Config.popoutPadding * 2
            height: 40

            PopSwitch {
                id: sw
                anchors.verticalCenter: parent.verticalCenter
                checked: row.modelData.enabled
                onToggled: v => root.patch(row.index, "enabled", v)
            }
            Column {
                anchors {
                    left: sw.right
                    leftMargin: 12
                    right: actions.left
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                Txt {
                    width: parent.width
                    text: row.modelData.name
                    elide: Text.ElideRight
                    opacity: row.modelData.enabled ? 1 : 0.5
                }
                Txt {
                    width: parent.width
                    text: row.modelData.cmd + (row.modelData.delaySec > 0 ? "  ·  через " + row.modelData.delaySec + " с" : "")
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 2
                    elide: Text.ElideRight
                }
            }
            Row {
                id: actions
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 6
                SetButton {
                    text: "Запустить"
                    tooltip: "Запустить сейчас (без ожидания следующего входа)"
                    onClicked: Quickshell.execDetached(["sh", "-c", row.modelData.cmd])
                }
                SetButton {
                    icon: Config.icons.trash
                    tooltip: "Убрать из автозапуска"
                    onClicked: root.save(root.copyEntries().filter((e, k) => k !== row.index))
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }
    Txt {
        text: "Добавить"
        color: Colors.fgVariant
        font.pixelSize: Config.fontSize - 1
    }
    Row {
        spacing: 8
        PopField {
            id: nameField
            width: 160
            placeholder: "Название"
        }
        PopField {
            id: cmdField
            width: 280
            placeholder: "Команда, например: firefox"
            onAccepted: root.add()
        }
        PopField {
            id: delayField
            width: 90
            placeholder: "Задержка, с"
            onAccepted: root.add()
        }
        SetButton {
            text: "Добавить"
            kind: "primary"
            onClicked: root.add()
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
        visible: root.system.length > 0
        text: root.showSystem ? "Скрыть системное" : "Системное (только просмотр): " + root.system.length
        onClicked: root.showSystem = !root.showSystem
    }
    Column {
        visible: root.showSystem
        width: parent.width
        spacing: 2
        Txt {
            width: parent.width
            text: "Инфраструктура сессии из hyprland.lua (hyprglass, polkit, keyring, порталы, hypridle, панель, обои…). Правится в файле."
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: root.system
            delegate: Txt {
                required property string modelData
                width: parent.width
                text: modelData
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
                elide: Text.ElideRight
            }
        }
    }
}
