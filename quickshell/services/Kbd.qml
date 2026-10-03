pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Раскладка клавиатуры: начальное значение из `hyprctl devices -j`,
// дальше — событие activelayout из сокета Hyprland.
Singleton {
    id: root

    property string layout: ""       // полное имя, напр. "English (US)"
    property string mainKeyboard: ""

    // Короткие подписи по названию раскладки (xkb-имя, которое отдаёт Hyprland);
    // неизвестные — первые две буквы названия.
    readonly property var abbrMap: ({
            "polish": "PL",
            "russian": "RU",
            "english (us)": "US",
            "english (uk)": "GB",
            "german": "DE",
            "ukrainian": "UA",
            "belarusian": "BY",
            "czech": "CZ",
            "french": "FR",
            "spanish": "ES",
            "italian": "IT"
        })
    readonly property string abbr: {
        if (layout === "")
            return "";
        const known = abbrMap[layout.toLowerCase()];
        return known ?? layout.substring(0, 2).toUpperCase();
    }

    Process {
        id: proc
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards || [];
                    const kb = kbs.find(k => k.main) ?? kbs[0];
                    if (kb) {
                        root.mainKeyboard = kb.name;
                        root.layout = kb.active_keymap;
                    }
                } catch (e) {
                }
            }
        }
    }

    Connections {
        target: Hyprland

        // data: "<имя клавиатуры>,<имя раскладки>"
        function onRawEvent(event) {
            if (event.name !== "activelayout")
                return;
            const d = event.data;
            const i = d.lastIndexOf(",");
            if (i < 0)
                return;
            // Фильтра по имени клавиатуры нет: «главной» Hyprland считает служебное
            // устройство ASUS, а события смены раскладки приходят от реальной клавиатуры.
            // Группа раскладок общая для всех устройств, поэтому берём любое событие.
            root.layout = d.substring(i + 1);
        }
    }
}
