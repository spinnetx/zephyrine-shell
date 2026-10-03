import QtQuick
import Quickshell.Io
import "../../"
import "../../components"

// Карточка «Шрифты» страницы «Внешний вид» (DESIGN §3.7, A1): шрифт панели (только Nerd Font), шрифт интерфейса
// и моноширинный шрифт, их размеры и предпросмотр. Списки семейств — `zephyrine-settings fonts --kind …`
// (fc-list; CLI один источник фильтров). Сама ничего не пишет: значения отправляет страница (page.send /
// page.sliderCommit → SettingsCli.set), а текущие читает так же, как она (оптимистичный слой local → Prefs → дефолт).
// Бар меняется сразу: шрифт/размер шелла идут в Prefs.preview, остальное применяется после ответа CLI.
SetCard {
    id: root

    property var page: null          // AppearancePage: local, errors, send(), sliderCommit()

    // Дефолты ключей, которых нет в Prefs.spec (дублируют schema.json — править в обоих местах).
    readonly property var defaults: ({
        "appearance.fonts.ui.family": "Inter",
        "appearance.fonts.ui.size": 10,
        "appearance.fonts.mono.family": "JetBrainsMono Nerd Font",
        "appearance.fonts.mono.size": 11,
        "appearance.fonts.lock.family": "JetBrainsMono Nerd Font",
        "appearance.fonts.login.family": "JetBrainsMono Nerd Font"
    })
    readonly property string kShell: "appearance.fonts.shell.family"
    readonly property string kShellSize: "appearance.fonts.shell.size"
    readonly property string kUi: "appearance.fonts.ui.family"
    readonly property string kUiSize: "appearance.fonts.ui.size"
    readonly property string kMono: "appearance.fonts.mono.family"
    readonly property string kMonoSize: "appearance.fonts.mono.size"
    readonly property string kLock: "appearance.fonts.lock.family"
    readonly property string kLogin: "appearance.fonts.login.family"

    property var nerdFonts: []
    property var allFonts: []
    property var monoFonts: []
    property bool listsFailed: false

    function val(key) {
        const l = page ? page.local[key] : undefined;
        if (l !== undefined)
            return l;
        if (Prefs.spec[key] !== undefined)
            return Prefs.get(key);
        const v = Prefs.lookup(Prefs.file, key);
        return (v === undefined || v === null) ? defaults[key] : v;
    }
    function def(key) {
        return Prefs.spec[key] !== undefined ? Prefs.def(key) : defaults[key];
    }
    function err(key) {
        return page ? (page.errors[key] ?? "") : "";
    }
    function pick(key, v) {
        if (key === kShell)
            Prefs.preview(key, v);
        if (page)
            page.send({ [key]: v });
    }
    function parse(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l !== "");
        for (let i = lines.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(lines[i]);
                if (o && Array.isArray(o.families))
                    return o.families;
            } catch (e) {}
        }
        return null;
    }
    function loaded(kind, text) {
        const f = parse(text);
        if (f === null) {
            listsFailed = true;
            return;
        }
        if (kind === "nerd")
            nerdFonts = f;
        else if (kind === "mono")
            monoFonts = f;
        else
            allFonts = f;
    }

    title: "Шрифты"
    icon: "Aa"

    Process {
        running: true
        command: [Config.settingsCli, "fonts", "--kind", "nerd"]
        stdout: StdioCollector {
            onStreamFinished: root.loaded("nerd", text)
        }
    }
    Process {
        running: true
        command: [Config.settingsCli, "fonts", "--kind", "any"]
        stdout: StdioCollector {
            onStreamFinished: root.loaded("any", text)
        }
    }
    Process {
        running: true
        command: [Config.settingsCli, "fonts", "--kind", "mono"]
        stdout: StdioCollector {
            onStreamFinished: root.loaded("mono", text)
        }
    }

    Txt {
        visible: root.listsFailed
        width: parent.width
        wrapMode: Text.WordWrap
        color: Colors.error
        font.pixelSize: Config.fontSize - 1
        text: "Не удалось получить список шрифтов (fc-list) — выбор недоступен, ползунки работают."
    }

    // ---------- шрифт панели ----------
    SetRow {
        width: parent.width
        label: "Шрифт панели"
        hint: "Только семейства с «Nerd Font» — иначе пропадут иконки панели"
        error: root.err(root.kShell)
        SetDropdown {
            width: 260
            options: root.nerdFonts
            current: root.val(root.kShell)
            placeholder: String(root.val(root.kShell))
            enabled: root.nerdFonts.length > 0
            onSelected: v => root.pick(root.kShell, v)
        }
        SetButton {
            icon: Config.icons.refresh
            tooltip: "По умолчанию"
            visible: root.val(root.kShell) !== root.def(root.kShell)
            onClicked: root.pick(root.kShell, root.def(root.kShell))
        }
    }
    PrefSliderRow {
        width: parent.width
        prefKey: root.kShellSize
        label: "Размер шрифта панели"
        hint: "Меняется на панели сразу"
        error: root.err(prefKey)
        from: 10
        to: 16
        step: 1
        decimals: 0
        suffix: " pt"
        defaultValue: 13
        value: root.val(prefKey)
        onPreviewed: (k, v) => Prefs.preview(k, v)
        onCommitted: (k, v) => {
            Prefs.preview(k, v);
            if (root.page)
                root.page.sliderCommit(k, v, 0);
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // ---------- шрифт интерфейса ----------
    SetRow {
        width: parent.width
        label: "Шрифт интерфейса"
        hint: "GTK, Qt, gsettings. GTK 4 подхватит сразу, GTK 3 и Qt — после перезапуска приложений"
        error: root.err(root.kUi)
        SetDropdown {
            width: 260
            options: root.allFonts
            current: root.val(root.kUi)
            placeholder: String(root.val(root.kUi))
            enabled: root.allFonts.length > 0
            onSelected: v => root.pick(root.kUi, v)
        }
        SetButton {
            icon: Config.icons.refresh
            tooltip: "По умолчанию"
            visible: root.val(root.kUi) !== root.def(root.kUi)
            onClicked: root.pick(root.kUi, root.def(root.kUi))
        }
    }
    PrefSliderRow {
        width: parent.width
        prefKey: root.kUiSize
        label: "Размер шрифта интерфейса"
        error: root.err(prefKey)
        from: 8
        to: 14
        step: 1
        decimals: 0
        suffix: " pt"
        defaultValue: 10
        value: root.val(prefKey)
        onCommitted: (k, v) => {
            if (root.page)
                root.page.sliderCommit(k, v, 0);
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // ---------- моноширинный ----------
    SetRow {
        width: parent.width
        label: "Моноширинный шрифт"
        hint: "Kitty, Zathura, Obsidian, моно-шрифт GTK/Qt. Только моноширинные семейства"
        error: root.err(root.kMono)
        SetDropdown {
            width: 260
            options: root.monoFonts
            current: root.val(root.kMono)
            placeholder: String(root.val(root.kMono))
            enabled: root.monoFonts.length > 0
            onSelected: v => root.pick(root.kMono, v)
        }
        SetButton {
            icon: Config.icons.refresh
            tooltip: "По умолчанию"
            visible: root.val(root.kMono) !== root.def(root.kMono)
            onClicked: root.pick(root.kMono, root.def(root.kMono))
        }
    }
    PrefSliderRow {
        width: parent.width
        prefKey: root.kMonoSize
        label: "Размер моноширинного шрифта"
        hint: "Kitty и Zathura"
        error: root.err(prefKey)
        from: 8
        to: 16
        step: 1
        decimals: 0
        suffix: " pt"
        defaultValue: 11
        value: root.val(prefKey)
        onCommitted: (k, v) => {
            if (root.page)
                root.page.sliderCommit(k, v, 0);
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // ---------- шрифты экранов блокировки и входа ----------
    SetRow {
        width: parent.width
        label: "Шрифт экрана блокировки"
        hint: "hyprlock; жирные надписи берут «Bold» этого семейства. Применится при следующей блокировке"
        error: root.err(root.kLock)
        SetDropdown {
            width: 260
            options: root.allFonts
            current: root.val(root.kLock)
            placeholder: String(root.val(root.kLock))
            enabled: root.allFonts.length > 0
            onSelected: v => root.pick(root.kLock, v)
        }
        SetButton {
            icon: Config.icons.refresh
            tooltip: "По умолчанию"
            visible: root.val(root.kLock) !== root.def(root.kLock)
            onClicked: root.pick(root.kLock, root.def(root.kLock))
        }
    }
    SetRow {
        width: parent.width
        label: "Шрифт окна входа"
        hint: "Тема SDDM. Нужен шрифт, доступный пользователю sddm; применится после «sudo sddm/install-theme.sh»"
        error: root.err(root.kLogin)
        SetDropdown {
            width: 260
            options: root.allFonts
            current: root.val(root.kLogin)
            placeholder: String(root.val(root.kLogin))
            enabled: root.allFonts.length > 0
            onSelected: v => root.pick(root.kLogin, v)
        }
        SetButton {
            icon: Config.icons.refresh
            tooltip: "По умолчанию"
            visible: root.val(root.kLogin) !== root.def(root.kLogin)
            onClicked: root.pick(root.kLogin, root.def(root.kLogin))
        }
    }

    // ---------- предпросмотр ----------
    Rectangle {
        width: parent.width
        height: previewCol.implicitHeight + 24
        radius: 10
        color: Qt.alpha(Colors.background, 0.6)
        border.width: 1
        border.color: Qt.alpha(Colors.outline, 0.3)

        Column {
            id: previewCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 12
            }
            spacing: 8

            Row {
                spacing: 10
                Txt {
                    text: Config.icons.wifi4 + " " + Config.icons.volHigh + " " + Config.icons.battery
                    color: Colors.primary
                    font.family: root.val(root.kShell)
                    font.pixelSize: Number(root.val(root.kShellSize)) + 3
                }
                Txt {
                    text: "Панель  14:32  Пт 2 окт"
                    font.family: root.val(root.kShell)
                    font.pixelSize: Number(root.val(root.kShellSize))
                }
            }
            Txt {
                width: parent.width
                elide: Text.ElideRight
                text: "Интерфейс — Съешьте ещё этих мягких французских булок, да выпейте чаю"
                font.family: root.val(root.kUi)
                font.pixelSize: Math.round(Number(root.val(root.kUiSize)) * 4 / 3)
            }
            Txt {
                width: parent.width
                elide: Text.ElideRight
                color: Colors.fgVariant
                text: "mono  const x = 42; // → != >= {} [] 0O1lI"
                font.family: root.val(root.kMono)
                font.pixelSize: Math.round(Number(root.val(root.kMonoSize)) * 4 / 3)
            }
        }
    }
}
