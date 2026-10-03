pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Пользовательские настройки (центр настроек, DESIGN §2.3/§2.5). Только ЧИТАЕТ
// ~/my_zephyrine_conf/settings/settings.json (разреженный: лишь отличия от дефолтов); пишет файл
// только CLI zephyrine-settings (services/SettingsCli.qml), поэтому петель записи нет.
//
// Дефолты ниже ДОЛЖНЫ совпадать с прежними константами Config.qml: без settings.json (или при
// битом/пустом файле) вид бара не меняется. Эффективное значение = превью ?? файл ?? дефолт;
// значение не того типа или вне диапазона игнорируется (берётся дефолт).
//
// Prefs не импортирует Config (иначе цикл Config -> Prefs -> Config). Имя не «Settings»/«State».
Singleton {
    id: root

    readonly property string userPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/zephyrine/settings.json"
    readonly property string devPath: Quickshell.env("HOME") + "/my_zephyrine_conf/settings/settings.json"
    readonly property string path: userPath

    // Разобранный settings.json (вложенные объекты). Заменяется целиком — так срабатывают привязки.
    property var file: ({})
    // Временные значения от ползунков окна настроек: { "appearance.glassAlpha": 0.8 }.
    property var previewMap: ({})
    property bool ready: false

    // key: [тип, дефолт, min, max]; тип: "real" | "int" | "bool" | "nerdfont".
    readonly property var spec: ({
        "appearance.glassAlpha": ["real", 0.88, 0.5, 1.0],
        "appearance.surfaceAlpha": ["real", 0.94, 0.7, 1.0],
        "appearance.radius": ["int", 12, 0, 20],
        "appearance.fonts.shell.family": ["nerdfont", "JetBrainsMono Nerd Font"],
        "appearance.fonts.shell.size": ["int", 13, 10, 16],
        "audio.volumeMax": ["real", 1.0, 1.0, 1.5],
        "audio.volumeStep": ["real", 0.05, 0.01, 0.1],
        "power.batteryCritical": ["real", 0.15, 0.05, 0.3],
        "notifications.toastMs": ["int", 5000, 1000, 30000],
        "notifications.historyMax": ["int", 50, 10, 500],
        "notifications.dndAllowCritical": ["bool", true]
    })

    // Вложенный поиск по ключу с точками; undefined, если нет.
    function lookup(obj, key) {
        let cur = obj;
        for (const part of key.split(".")) {
            if (cur === null || typeof cur !== "object" || !(part in cur))
                return undefined;
            cur = cur[part];
        }
        return cur;
    }

    // Проверка и приведение значения по описанию; undefined — значение негодно.
    function coerce(s, v) {
        switch (s[0]) {
        case "real":
        case "int":
            if (typeof v !== "number" || !isFinite(v))
                return undefined;
            if (s[0] === "int" && Math.floor(v) !== v)
                return undefined;
            return (v < s[2] || v > s[3]) ? undefined : v;
        case "bool":
            return typeof v === "boolean" ? v : undefined;
        case "nerdfont":
            // Только семейства с «Nerd Font»: иначе пропадут иконки бара.
            return (typeof v === "string" && v.indexOf("Nerd Font") >= 0) ? v : undefined;
        }
        return undefined;
    }

    function def(key) {
        const s = spec[key];
        return s ? s[1] : undefined;
    }

    // Эффективное значение ключа: превью ?? файл ?? дефолт.
    function get(key) {
        const s = spec[key];
        if (!s)
            return undefined;
        let v = coerce(s, previewMap[key]);
        if (v === undefined)
            v = coerce(s, lookup(file, key));
        return v === undefined ? s[1] : v;
    }

    function preview(key, v) {
        const m = Object.assign({}, previewMap);
        m[key] = v;
        previewMap = m;
    }

    function clearPreview(key) {
        const m = Object.assign({}, previewMap);
        delete m[key];
        previewMap = m;
    }

    function apply(text) {
        try {
            const o = JSON.parse(text);
            if (o && typeof o === "object" && !Array.isArray(o)) {
                root.file = o;
                // CLI переписал файл: превью больше не нужно, значение теперь «настоящее».
                root.previewMap = ({});
            }
        } catch (e) {
            // Битый/недописанный JSON: остаются последние валидные значения.
            console.warn("zephyrine: не удалось разобрать settings.json:", e);
        }
        root.ready = true;
    }

    // --- Значения для остального шелла (привязаны в Config.qml) ---
    readonly property real glassAlpha: get("appearance.glassAlpha")
    readonly property real surfaceAlpha: get("appearance.surfaceAlpha")
    readonly property int radius: get("appearance.radius")
    readonly property string shellFont: get("appearance.fonts.shell.family")
    readonly property int shellFontSize: get("appearance.fonts.shell.size")
    readonly property real volumeMax: get("audio.volumeMax")
    readonly property real volumeStep: get("audio.volumeStep")
    readonly property real batteryCritical: get("power.batteryCritical")
    readonly property int toastMs: get("notifications.toastMs")
    readonly property int historyMax: get("notifications.historyMax")
    readonly property bool dndAllowCritical: get("notifications.dndAllowCritical")

    // --- Панель: положение и состав зон (центр настроек → Внешний вид → Панель; ключи bar.*) ---
    // Список id элементов и дефолты дублируют settings/zsettings/barlayout.py и schema.json - править во всех местах.
    readonly property var barPositions: ["top", "bottom", "left", "right"]
    readonly property var barZoneDefaults: ({
        left: ["workspaces", "activeWindow"],
        center: ["media"],
        right: ["limits", "disk", "gpu", "cpu", "mem", "net", "tray", "status", "clock", "power"]
    })
    readonly property string barPosition: {
        const v = lookup(file, "bar.position");
        return barPositions.indexOf(v) >= 0 ? v : "top";
    }
    function barZone(z) {
        const v = lookup(file, "bar." + z);
        return (Array.isArray(v) && v.every(x => typeof x === "string")) ? v : barZoneDefaults[z];
    }
    // Город для виджета погоды (weather.city; пусто - по IP).
    readonly property string weatherCity: {
        const v = lookup(file, "weather.city");
        return typeof v === "string" ? v : "";
    }
    readonly property var barLeft: barZone("left")
    readonly property var barCenter: barZone("center")
    readonly property var barRight: barZone("right")

    FileView {
        id: userView
        path: root.userPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        onLoadFailed: {
            if (devView.loaded)
                root.apply(devView.text());
            else {
                root.file = ({});
                root.ready = true;
            }
        }
    }

    FileView {
        id: devView
        path: root.devPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!userView.loaded)
                root.apply(text());
        }
    }
}
