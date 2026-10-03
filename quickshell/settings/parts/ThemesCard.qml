import QtQuick
import Quickshell.Io
import "../../"
import "../../components"

// Карточка «Курсор и иконки» страницы «Внешний вид» (DESIGN §3.11): тема иконок (null = по режиму темы: Papirus-Dark /
// Papirus), тема курсора мыши и его размер. Списки тем с файлами-превью даёт `zephyrine-settings themes --kind …`
// (иконки — SVG/PNG из темы, курсоры — PNG из Xcursor, кэш в состоянии). Сама ничего не пишет: значения отправляет
// страница (page.send / page.sliderCommit → SettingsCli.set); текущие читает так же, как карточка шрифтов
// (оптимистичный слой local → Prefs → дефолт). Применение — цели gtk3/gtk4-settings, qt6ct-conf, gsettings, hypr, cursor.
SetCard {
    id: root

    property var page: null          // AppearancePage: local, errors, send(), sliderCommit(), statusMap

    readonly property string kIcons: "appearance.icons.theme"
    readonly property string kCursor: "appearance.cursor.theme"
    readonly property string kSize: "appearance.cursor.size"
    // Дефолты ключей, которых нет в Prefs.spec (дублируют schema.json — править в обоих местах).
    readonly property var defaults: ({
        "appearance.icons.theme": null,
        "appearance.cursor.theme": "Qogir",
        "appearance.cursor.size": 24
    })

    property var iconThemes: []
    property var cursorThemes: []
    property bool iconsLoaded: false
    property bool cursorsLoaded: false
    property bool listsFailed: false

    function val(key) {
        const l = page ? page.local[key] : undefined;
        if (l !== undefined)
            return l;
        if (Prefs.spec[key] !== undefined)
            return Prefs.get(key);
        const v = Prefs.lookup(Prefs.file, key);
        return (v === undefined) ? defaults[key] : v;
    }
    function err(key) {
        return page ? (page.errors[key] ?? "") : "";
    }
    function pick(key, v) {
        if (page)
            page.send({ [key]: v });
    }
    function parse(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l !== "");
        for (let i = lines.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(lines[i]);
                if (o && Array.isArray(o.themes))
                    return o.themes;
            } catch (e) {}
        }
        return null;
    }
    function toItems(list) {
        return list.map(t => ({ name: t.name, value: t.name, samples: t.samples ?? [], note: "нет образцов" }));
    }
    function loaded(kind, text) {
        const t = parse(text);
        if (t === null) {
            listsFailed = true;
            return;
        }
        if (kind === "icons") {
            iconThemes = toItems(t);
            iconsLoaded = true;
        } else {
            cursorThemes = toItems(t);
            cursorsLoaded = true;
        }
    }

    // Плитки иконок: первая — «по режиму темы» (значение null → value "" в сетке).
    readonly property var iconItems: [{ name: "По режиму темы", value: "", samples: [],
        note: "Papirus-Dark / Papirus" }].concat(iconThemes)
    readonly property string iconCurrent: {
        const v = val(kIcons);
        return (v === null || v === undefined) ? "" : String(v);
    }
    readonly property string cursorCurrent: String(val(kCursor))
    readonly property var cursorSamples: {
        for (const t of cursorThemes)
            if (t.value === cursorCurrent)
                return t.samples;
        return [];
    }
    readonly property int cursorSize: Number(val(kSize))

    title: "Курсор и иконки"
    icon: Config.icons.palette

    Process {
        running: true
        command: [Config.settingsCli, "themes", "--kind", "icons"]
        stdout: StdioCollector {
            onStreamFinished: root.loaded("icons", text)
        }
    }
    Process {
        running: true
        command: [Config.settingsCli, "themes", "--kind", "cursors"]
        stdout: StdioCollector {
            onStreamFinished: root.loaded("cursors", text)
        }
    }

    Txt {
        visible: root.listsFailed
        width: parent.width
        wrapMode: Text.WordWrap
        color: Colors.error
        font.pixelSize: Config.fontSize - 1
        text: "Не удалось получить список тем — выбор недоступен."
    }

    // ---------- иконки ----------
    SetRow {
        width: parent.width
        label: "Тема иконок"
        hint: "GTK, Qt, gsettings. GTK 4 подхватит сразу, GTK 3 и Qt — после перезапуска приложений. Тему можно поставить в ~/.local/share/icons"
        error: root.err(root.kIcons)
    }
    ThemeGrid {
        width: parent.width
        items: root.iconItems
        current: root.iconCurrent
        sample: 32
        loading: !root.iconsLoaded
        onPicked: value => root.pick(root.kIcons, value === "" ? null : value)
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // ---------- курсор ----------
    SetRow {
        width: parent.width
        label: "Тема курсора"
        hint: "Hyprland и новые окна GTK меняются сразу; Qt, XWayland и открытые приложения — после перезапуска, переменные окружения — со следующего входа"
        error: root.err(root.kCursor)
    }
    ThemeGrid {
        width: parent.width
        items: root.cursorThemes
        current: root.cursorCurrent
        sample: 32
        loading: !root.cursorsLoaded
        emptyText: "Темы курсора не найдены (нужен каталог с подкаталогом cursors/)"
        onPicked: value => root.pick(root.kCursor, value)
    }
    PrefSliderRow {
        width: parent.width
        prefKey: root.kSize
        label: "Размер курсора"
        hint: "Пиксели; для HiDPI-экранов обычно 32–48"
        error: root.err(prefKey)
        from: 16
        to: 64
        step: 4
        decimals: 0
        suffix: " px"
        defaultValue: 24
        value: root.cursorSize
        onCommitted: (k, v) => {
            if (root.page)
                root.page.sliderCommit(k, v, 0);
        }
    }

    // ---------- предпросмотр курсора ----------
    Rectangle {
        width: parent.width
        height: Math.max(64, root.cursorSize + 32)
        radius: 10
        color: Qt.alpha(Colors.background, 0.6)
        border.width: 1
        border.color: Qt.alpha(Colors.outline, 0.3)

        Row {
            anchors.centerIn: parent
            spacing: 28
            Repeater {
                model: root.cursorSamples
                delegate: Image {
                    required property string modelData
                    width: root.cursorSize
                    height: root.cursorSize
                    source: "file://" + modelData
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
        }
        Txt {
            anchors.centerIn: parent
            visible: root.cursorSamples.length === 0
            text: "Нет образца для выбранной темы"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
        }
    }
}
