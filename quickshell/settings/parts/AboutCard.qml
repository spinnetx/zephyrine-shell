import QtQuick
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"

// Карточка «О системе» (DESIGN §4.4, Y6): zephyrine-settings sysinfo — хост, ОС, ядро, Hyprland/Quickshell, CPU, ОЗУ,
// GPU, аптайм, наличие нужных программ. «Скопировать» кладёт краткую сводку в буфер (wl-copy).
SetCard {
    id: root

    title: "О системе"
    icon: Config.icons.info

    property var info: ({})
    property string error: ""
    property bool copied: false

    function refresh() {
        if (proc.running)
            return;
        error = "";
        proc.running = true;
    }

    function parse(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l !== "");
        for (let i = lines.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(lines[i]);
                if (o && o.sysinfo) {
                    info = o.sysinfo;
                    return;
                }
            } catch (e) {}
        }
        error = "Не удалось получить сведения о системе";
    }

    function fmtUptime(sec) {
        if (sec === undefined || sec === null)
            return "";
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return (d > 0 ? d + " д " : "") + (h > 0 || d > 0 ? h + " ч " : "") + m + " мин";
    }

    readonly property var rows: {
        const i = info;
        const out = [];
        const add = (k, v) => { if (v !== undefined && v !== null && String(v) !== "") out.push({ k: k, v: String(v) }); };
        add("Хост", i.hostname);
        add("Система", i.os);
        add("Ядро", i.kernel ? "Linux " + i.kernel : "");
        add("Hyprland", i.hyprland);
        add("Quickshell", i.quickshell);
        add("Процессор", i.cpu);
        if (i.memTotalKiB) {
            const tot = i.memTotalKiB / 1048576;
            const used = i.memAvailableKiB ? tot - i.memAvailableKiB / 1048576 : -1;
            add("Память", (used >= 0 ? used.toFixed(1) + " из " : "") + tot.toFixed(1) + " ГиБ");
        }
        (i.gpus ?? []).forEach((g, n) => add(n === 0 ? "Видеокарта" : "", g));
        add("Аптайм", fmtUptime(i.uptimeSec));
        return out;
    }

    Component.onCompleted: refresh()

    Process {
        id: proc
        command: [Config.settingsCli, "sysinfo"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Process {
        id: copyProc
        onExited: code => {
            root.copied = code === 0;
            if (code !== 0)
                Toaster.show("О системе", "wl-copy недоступен — не удалось скопировать", "", "error");
        }
    }

    Txt {
        visible: root.error.length > 0
        width: parent.width
        text: root.error
        color: Colors.error
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.rows
        delegate: Row {
            required property var modelData
            width: root.width - Config.popoutPadding * 2
            spacing: 12
            Txt {
                width: 110
                text: parent.modelData.k
                color: Colors.fgVariant
            }
            Txt {
                width: parent.width - 122
                text: parent.modelData.v
                wrapMode: Text.WordWrap
            }
        }
    }

    Txt {
        visible: (root.info.components ?? []).length > 0
        text: "Компоненты"
        color: Colors.fgVariant
        font.pixelSize: Config.fontSize - 1
    }
    Flow {
        width: parent.width
        spacing: 6
        Repeater {
            model: root.info.components ?? []
            delegate: StatusChip {
                required property var modelData
                kind: modelData.present ? "live" : "neutral"
                text: (modelData.present ? "✓ " : "✗ ") + modelData.label
            }
        }
    }

    Row {
        spacing: 8
        SetButton {
            text: root.copied ? "Скопировано" : "Скопировать"
            enabled: (root.info.text ?? "") !== ""
            onClicked: {
                copyProc.command = ["wl-copy", "--", root.info.text];
                copyProc.running = true;
            }
        }
        SetButton {
            text: "Обновить"
            onClicked: root.refresh()
        }
    }
}
