pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Палитра из scheme.json (формат как у Caelestia: colours.<имя> = hex без '#').
// Файл перечитывается на лету; при ошибке остаются безопасные дефолты
// (Obsidian Neon), поэтому цвета тут — единственное место, где допустим хардкод.
//
// ВНИМАНИЕ: свойства НЕ называем onSurface/onPrimary и т.п. — в QML имя "on"+Заглавная
// трактуется как обработчик сигнала, и такое свойство молча получало #000000
// (из-за этого весь основной текст бара был чёрным на тёмном). Поэтому fg/fgVariant/
// primaryText; ключи в scheme.json остаются в формате Caelestia (onSurface и т.д.).
Singleton {
    id: root

    property var scheme: ({})
    // Переопределения от центра настроек (scheme.override.json, генерирует zephyrine-settings):
    // только изменённые ключи; нет файла / пустые colours — палитра ровно из scheme.json.
    property var override: ({})

    function pick(key, def) {
        const o = override[key];
        const v = (typeof o === "string" && /^[0-9a-fA-F]{6,8}$/.test(o)) ? o : scheme[key];
        return "#" + ((typeof v === "string" && /^[0-9a-fA-F]{6,8}$/.test(v)) ? v : def);
    }

    function apply(text) {
        try {
            const o = JSON.parse(text);
            if (o && o.colours)
                root.scheme = o.colours;
        } catch (e) {
            console.warn("zephyrine: не удалось разобрать scheme.json:", e);
        }
    }

    readonly property color background: pick("background", "141414")
    readonly property color surface: pick("surface", "141414")
    readonly property color surfaceContainer: pick("surfaceContainer", "1c1d2b")
    readonly property color surfaceContainerHigh: pick("surfaceContainerHigh", "242538")
    readonly property color surfaceContainerHighest: pick("surfaceContainerHighest", "303249")
    readonly property color fg: pick("onSurface", "e8e8f0")
    readonly property color fgVariant: pick("onSurfaceVariant", "c0c0cc")
    readonly property color outline: pick("outline", "7f88b5")
    readonly property color outlineVariant: pick("outlineVariant", "41466a")
    readonly property color primary: pick("primary", "bb9af7")
    readonly property color primaryText: pick("onPrimary", "2a1a33")
    readonly property color primaryContainer: pick("primaryContainer", "4b3161")
    readonly property color secondary: pick("secondary", "7aa2f7")
    readonly property color tertiary: pick("tertiary", "2ac3de")
    readonly property color error: pick("error", "f7768e")
    readonly property color success: pick("success", "9ece6a")

    function applyOverride(text) {
        try {
            const o = JSON.parse(text);
            root.override = (o && o.colours && typeof o.colours === "object") ? o.colours : ({});
        } catch (e) {
            // Битый/недописанный файл: остаются последние валидные переопределения.
            console.warn("zephyrine: не удалось разобрать scheme.override.json:", e);
        }
    }

    FileView {
        path: Quickshell.shellPath("scheme.override.json")
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyOverride(text())
        // Файла нет (по умолчанию) или он удалён — переопределений нет.
        onLoadFailed: root.override = ({})
    }

    FileView {
        path: Quickshell.shellPath("scheme.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
}
