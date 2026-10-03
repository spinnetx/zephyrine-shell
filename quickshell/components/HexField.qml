import QtQuick
import "../"

// Поле цвета: PopField + проверка #rrggbb + образец + контраст с фоном (WCAG).
// value — нормализованный "#rrggbb" (или "" пока ввод некорректен). applied(hex) — по Enter/потере фокуса при корректном вводе.
Item {
    id: root

    property string value: ""                       // текущее значение снаружи (привязка)
    property color against: Colors.background       // относительно чего считать контраст
    property bool showContrast: true
    property real minContrast: 4.5
    property string errorText: "Ожидается цвет вида #rrggbb"
    readonly property string parsed: parseHex(field.text)    // "#rrggbb" в нижнем регистре или ""
    readonly property bool valid: parsed.length > 0
    readonly property real contrast: valid ? contrastRatio(Qt.color(parsed), against) : 0
    readonly property bool showError: field.text.length > 0 && !valid
    signal applied(string hex)

    // Палитра выбора: клик по образцу раскрывает сетку (цвета темы, оттенки, серые); выбор пишет hex в поле и применяет.
    property bool paletteOpen: false
    function hexOf(c) {
        function h(v) {
            var t = Math.round(v * 255).toString(16);
            return t.length < 2 ? "0" + t : t;
        }
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }
    readonly property var themeColors: [Colors.primary, Colors.secondary, Colors.tertiary, Colors.error, Colors.success,
                                        Colors.fg, Colors.fgVariant, Colors.outline].map(c => hexOf(Qt.color(c)))
    // Градиентная палитра: тон (полоса) + насыщенность/яркость (квадрат). h/s/v подтягиваются из текущего цвета, пока не тянут.
    property real hue: 0
    property real sat: 1
    property real val: 1
    property bool dragging: false
    function syncFromColor() {
        if (dragging || !valid)
            return;
        var c = Qt.color(parsed);
        if (c.hsvHue >= 0)
            hue = c.hsvHue;
        sat = c.hsvSaturation;
        val = c.hsvValue;
    }
    onParsedChanged: syncFromColor()
    onPaletteOpenChanged: if (paletteOpen) syncFromColor()
    function previewHsv() {
        field.text = hexOf(Qt.hsva(hue, sat, val, 1));
    }
    function pick(hex) {
        field.text = hex;
        commit();
    }

    function parseHex(t) {
        var m = /^\s*#?([0-9a-fA-F]{6})\s*$/.exec(t);
        return m ? "#" + m[1].toLowerCase() : "";
    }
    function lin(c) {
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }
    function luminance(c) {
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }
    function contrastRatio(a, b) {
        var la = luminance(a), lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    function focusInput() {
        field.focusInput();
    }
    function commit() {
        if (!valid)
            return;
        field.text = parsed;
        if (parsed !== value.toLowerCase())
            applied(parsed);
    }

    // Внешнее значение подтягиваем в поле, только пока пользователь его не редактирует.
    onValueChanged: if (!field.focused) field.text = value
    Component.onCompleted: field.text = value

    implicitWidth: 240
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 4

        Row {
            spacing: 8

            Rectangle {
                width: 34
                height: 34
                radius: 10
                color: root.valid ? root.parsed : "transparent"
                border.width: 1
                border.color: root.showError ? Colors.error : Qt.alpha(Colors.outline, 0.5)

                Behavior on color {
                    ColorAnimation { duration: 120; easing.type: Config.animEasing }
                }

                // Клик по образцу — палитра.
                HoverHandler {
                    id: sampleHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: root.paletteOpen = !root.paletteOpen
                }
                Txt {
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: 2
                    }
                    visible: sampleHover.hovered || root.paletteOpen
                    text: root.paletteOpen ? "▴" : "▾"
                    color: root.valid && Qt.color(root.parsed).hslLightness > 0.55 ? "#1a1a1a" : "#ffffff"
                    font.pixelSize: 10
                }

                // Перечёркнутый образец при невалидном вводе.
                Txt {
                    anchors.centerIn: parent
                    visible: !root.valid
                    text: Config.icons.close
                    color: Colors.fgVariant
                    font.pixelSize: Config.iconSize
                }
            }

            PopField {
                id: field
                width: root.width - 34 - 8 - (root.showContrast ? contrastText.width + 8 : 0)
                placeholder: "#rrggbb"
                onAccepted: root.commit()
                onFocusedChanged: if (!focused) root.commit()
            }

            Txt {
                id: contrastText
                visible: root.showContrast
                height: 34
                width: visible ? implicitWidth : 0
                text: root.valid
                    ? "контраст " + root.contrast.toFixed(1) + (root.contrast >= root.minContrast ? " ✓" : " ⚠")
                    : ""
                color: root.valid && root.contrast < root.minContrast ? Colors.error : Colors.fgVariant
                font.pixelSize: Config.fontSize - 1
            }
        }

        Column {
            visible: root.paletteOpen
            width: parent.width
            spacing: 6

            Txt {
                text: "Цвета темы"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }
            Flow {
                width: parent.width
                spacing: 5
                Repeater {
                    model: root.themeColors
                    delegate: Rectangle {
                        id: sw
                        required property string modelData
                        readonly property bool selected: root.valid && root.parsed === modelData
                        width: 22
                        height: 22
                        radius: 6
                        color: modelData
                        border.width: selected ? 2 : 1
                        border.color: selected ? Colors.fg : Qt.alpha(Colors.outline, 0.5)
                        scale: swHover.hovered ? 1.12 : 1
                        Behavior on scale {
                            NumberAnimation { duration: 100; easing.type: Config.animEasing }
                        }
                        HoverHandler {
                            id: swHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: root.pick(sw.modelData)
                        }
                    }
                }
            }
            Txt {
                text: "Градиент"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }

            // Насыщенность (слева направо) и яркость (сверху вниз) выбранного тона.
            Rectangle {
                id: svBox
                width: parent.width
                height: 120
                radius: 8
                clip: true
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.5)
                color: "transparent"

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ffffff" }
                        GradientStop { position: 1; color: Qt.hsva(root.hue, 1, 1, 1) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: "#00000000" }
                        GradientStop { position: 1; color: "#000000" }
                    }
                }
                Rectangle {
                    x: root.sat * svBox.width - width / 2
                    y: (1 - root.val) * svBox.height - height / 2
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.width: 2
                    border.color: root.val > 0.5 && root.sat < 0.5 ? "#000000" : "#ffffff"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    function set(mx, my) {
                        root.sat = Math.max(0, Math.min(1, mx / width));
                        root.val = 1 - Math.max(0, Math.min(1, my / height));
                        root.previewHsv();
                    }
                    onPressed: mouse => { root.dragging = true; set(mouse.x, mouse.y); }
                    onPositionChanged: mouse => { if (pressed) set(mouse.x, mouse.y); }
                    onReleased: { root.dragging = false; root.commit(); }
                }
            }

            // Тон.
            Rectangle {
                id: hueBar
                width: parent.width
                height: 16
                radius: 8
                clip: true
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.5)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.hsva(0.0, 1, 1, 1) }
                    GradientStop { position: 1 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) }
                    GradientStop { position: 2 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
                    GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) }
                    GradientStop { position: 4 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) }
                    GradientStop { position: 5 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) }
                    GradientStop { position: 1.0; color: Qt.hsva(0.0, 1, 1, 1) }
                }
                Rectangle {
                    x: root.hue * (hueBar.width - 0) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: hueBar.height + 4
                    radius: 3
                    color: "transparent"
                    border.width: 2
                    border.color: "#ffffff"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function set(mx) {
                        root.hue = Math.max(0, Math.min(0.999, mx / width));
                        root.previewHsv();
                    }
                    onPressed: mouse => { root.dragging = true; set(mouse.x); }
                    onPositionChanged: mouse => { if (pressed) set(mouse.x); }
                    onReleased: { root.dragging = false; root.commit(); }
                }
            }
        }

        Txt {
            visible: root.showError
            text: root.errorText
            color: Colors.error
            font.pixelSize: Config.fontSize - 1
        }
    }
}
