import QtQuick
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"

// Карточка «Обои» (DESIGN §4.1, §9.2 A2): сетка обоев из каталога wallpapers/ с превью, выбор, статус цели и
// подсказка про SDDM. Каталог и превью даёт CLI `zephyrine-settings wallpaper list` (ffmpeg, кэш в состоянии);
// выбор — сигнал pick(value): страница отправляет appearance.wallpaper.desktop через SettingsCli.set.
// Сама ничего не пишет. Экран блокировки следует за рабочим столом (appearance.wallpaper.lock = null).
SetCard {
    id: root

    // Статус цели wallpaper из `status` (или null), текст ошибки CLI по ключу — от страницы.
    property var status: null
    property string error: ""
    signal pick(string value)

    property var items: []
    property var sddm: ({})
    property bool ffmpeg: true
    property bool mpvpaper: true
    property bool loading: false
    property string listError: ""
    property string pending: ""
    property bool again: false

    readonly property string tstate: status ? (status.state ?? "") : ""
    readonly property string sddmHint: sddm.hint ?? "sudo zephyrine-sddm-theme"

    title: "Обои"
    icon: Config.icons.monitor
    chipKind: tstate === "live" ? "live" : tstate === "error" ? "error" : tstate === "missing" ? "missing" : "neutral"
    chipText: tstate === "outdated" ? "не применено" : tstate === "missing" ? "mpvpaper не найден" : ""

    headerRight: [
        SetButton {
            text: "Выбрать файл..."
            icon: Config.icons.folder
            tooltip: "Открыть системный диалог выбора видео или картинки"
            enabled: !picker.running
            onClicked: {
                picker.command = [Config.settingsCli, "wallpaper", "pick"];
                picker.running = true;
            }
        }
    ]

    function reload() {
        if (list.running) {
            again = true;
            return;
        }
        loading = true;
        list.command = [Config.settingsCli, "wallpaper", "list"];
        list.running = true;
    }

    function parse(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l !== "");
        for (let i = lines.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(lines[i]);
                if (o && typeof o === "object")
                    return o;
            } catch (e) {}
        }
        return null;
    }

    Component.onCompleted: reload()

    // Настройки изменились (выбор, «Отменить», правка файла) — обновить отметку «выбрано».
    Connections {
        target: Prefs
        function onFileChanged() {
            debounce.restart();
        }
    }
    Timer {
        id: debounce
        interval: 300
        onTriggered: root.reload()
    }

    Process {
        id: list
        stdout: StdioCollector {
            id: out
        }
        onExited: code => {
            const res = root.parse(out.text);
            root.loading = false;
            if (res && res.ok !== false && Array.isArray(res.items)) {
                root.items = res.items;
                root.sddm = res.sddm ?? ({});
                root.ffmpeg = res.ffmpeg !== false;
                root.mpvpaper = res.mpvpaper !== false;
                root.listError = "";
                root.pending = "";
            } else {
                root.listError = "Не удалось получить список обоев (код " + code + ")";
            }
            if (root.again) {
                root.again = false;
                root.reload();
            }
        }
    }

    Process {
        id: copy
    }

    Process {
        id: picker
        stdout: StdioCollector {
            id: pickerOut
        }
        onExited: code => {
            if (code === 0) {
                const res = root.parse(pickerOut.text);
                if (res && res.ok && res.value) {
                    root.pending = res.value;
                    root.pick(res.value);
                    root.reload();
                } else if (res && res.error) {
                    root.listError = res.error;
                }
            } else if (code !== 0) {
                const res = root.parse(pickerOut.text);
                if (res && res.error)
                    root.listError = res.error;
            }
        }
    }

    WallpaperGrid {
        width: parent.width
        items: root.items
        pending: root.pending
        loading: root.loading
        onPicked: value => {
            root.pending = value;
            root.pick(value);
        }
    }

    Txt {
        width: parent.width
        visible: root.error.length > 0
        text: root.error
        color: Colors.error
        font.pixelSize: Config.fontSize - 1
        wrapMode: Text.WordWrap
        verticalAlignment: Text.AlignTop
    }
    Txt {
        width: parent.width
        visible: root.listError.length > 0
        text: root.listError
        color: Colors.error
        font.pixelSize: Config.fontSize - 1
        wrapMode: Text.WordWrap
        verticalAlignment: Text.AlignTop
    }

    SetRow {
        width: parent.width
        label: "Рабочий стол и экран блокировки"
        hint: (root.ffmpeg
            ? "Применяется сразу: перезапускаются только обои стола. Поиск видео и картинок: wallpapers/, ~/Pictures/Wallpapers, ~/.local/share/zephyrine/wallpapers."
            : "Превью недоступны: не найден ffmpeg. Выбор работает как обычно.")
    }

    SetRow {
        width: parent.width
        label: "SDDM (экран входа)"
        hint: root.sddm.inSync === true
            ? "Копия видео в системном каталоге совпадает с выбранным."
            : "SDDM: обновится после " + root.sddmHint + " (копия видео лежит в системном каталоге, нужен root)."
        SetButton {
            text: "Скопировать команду"
            tooltip: root.sddmHint
            onClicked: {
                copy.command = ["wl-copy", root.sddmHint];
                copy.running = true;
            }
        }
    }
}
