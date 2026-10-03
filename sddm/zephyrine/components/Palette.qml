pragma Singleton

import QtQuick

// Singleton Theme (qmldir; имя Palette занято встроенным типом QtQuick). Палитра и настройки темы. Все значения читаются из theme.conf (объект config,
// его передаёт Main.qml через Theme.conf = config); дефолты — obsidian-neon.
// Хардкод цветов допустим только здесь.
// Имена свойств не начинаем с "on"+Заглавная (QML считает это обработчиком сигнала).
QtObject {
    id: root

    // Объект config из SDDM (пока не задан — работают дефолты)
    property var conf: null

    function str(key, def) {
        const v = root.conf ? root.conf[key] : undefined;
        return (v === undefined || v === null || v === "") ? def : String(v);
    }
    function num(key, def) {
        const n = parseFloat(root.str(key, ""));
        return isNaN(n) ? def : n;
    }
    function flag(key, def) {
        const v = root.str(key, "").toLowerCase();
        if (v === "")
            return def;
        return v === "true" || v === "1" || v === "yes";
    }
    function col(key, def) {
        const v = root.str(key, def).replace("#", "");
        return /^[0-9a-fA-F]{6,8}$/.test(v) ? "#" + v : "#" + def;
    }
    // Цвет с альфой: Qt.rgba вместо Qt.alpha для совместимости
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // --- Цвета ---
    readonly property color background: col("background", "141414")
    readonly property color surfaceContainer: col("surfaceContainer", "1c1d2b")
    readonly property color surfaceContainerHigh: col("surfaceContainerHigh", "242538")
    readonly property color surfaceContainerHighest: col("surfaceContainerHighest", "303249")
    readonly property color fg: col("fg", "e8e8f0")
    readonly property color fgVariant: col("fgVariant", "c0c0cc")
    readonly property color outline: col("outline", "7f88b5")
    readonly property color outlineVariant: col("outlineVariant", "41466a")
    readonly property color primary: col("primary", "bb9af7")
    readonly property color primaryText: col("primaryText", "2a1a33")
    readonly property color primaryContainer: col("primaryContainer", "4b3161")
    readonly property color secondary: col("secondary", "7aa2f7")
    readonly property color tertiary: col("tertiary", "2ac3de")
    readonly property color error: col("error", "f7768e")
    readonly property color errorText: col("errorText", "4a0d17")
    readonly property color success: col("success", "9ece6a")

    // --- Геометрия, шрифт, анимации ---
    readonly property int barRadius: num("barRadius", 14)
    readonly property int cardRadius: num("cardRadius", 18)
    readonly property int pillRadius: num("pillRadius", 12)
    readonly property int barMargin: num("barMargin", 6)
    readonly property real panelAlpha: num("panelAlpha", 0.85)
    readonly property real cardAlpha: num("cardAlpha", 0.86)
    readonly property real dimTop: num("dimTop", 0.55)
    readonly property real dimBottom: num("dimBottom", 0.70)
    readonly property int animMs: num("animMs", 200)
    readonly property int easing: Easing.OutCubic
    readonly property int fontSize: num("fontSize", 14)
    readonly property string fontFamily: str("fontFamily", "JetBrainsMono Nerd Font")
    readonly property bool showLoginField: bool("showLoginField", true)
    readonly property string video: str("video", "assets/background.mp4")
}
