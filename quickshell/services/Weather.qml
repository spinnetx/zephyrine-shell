pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"
import "weather.js" as WJ

// Погода для виджета панели и попапа (wttr.in, ?format=j1): текущее состояние, подробности и прогноз на 3 дня. Город - настройка
// weather.city (пусто - по IP). Запросы идут ТОЛЬКО пока виджет «Погода» стоит на панели, раз в refreshMs; клик - обновить сразу.
// Сторонний сервис: в запросе уходит название города (или IP, если город пуст). Разбор - weather.js (проверяется weather-test.js).
Singleton {
    id: root

    readonly property string city: Prefs.weatherCity
    readonly property bool enabled: Prefs.barLeft.indexOf("weather") >= 0 || Prefs.barCenter.indexOf("weather") >= 0 || Prefs.barRight.indexOf("weather") >= 0
    readonly property int refreshMs: 30 * 60 * 1000

    property var current: ({})       // см. weather.js parse(): tempC, feelsC, humidity, windMs, windDir, pressureMm, visKm, uv, precipMm, desc, emoji
    property var days: []            // прогноз: [{date, maxC, minC, emoji, desc, rain, sunrise, sunset, hours:[…]}]
    property string place: ""
    property bool loaded: false
    property bool failed: false
    property bool busy: proc.running
    property real updatedMs: 0

    // Для пилюли и подсказок.
    readonly property string icon: loaded ? current.emoji : ""
    readonly property string cond: loaded ? current.desc : ""
    readonly property string brief: loaded ? WJ.sign(current.tempC) : "—"
    readonly property string temp: brief

    function sign(n) {
        return WJ.sign(n);
    }

    function refresh() {
        if (!enabled || proc.running)
            return;
        proc.command = ["curl", "-sf", "--max-time", "10", "-A", "zephyrine-bar",
                        "https://wttr.in/" + encodeURIComponent(city) + "?format=j1&lang=ru"];
        proc.running = true;
    }
    onEnabledChanged: if (enabled) refresh()
    onCityChanged: {
        loaded = false;
        refresh();
    }

    Timer {
        interval: root.refreshMs
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                const r = WJ.parse(text);
                if (!r.ok) {
                    root.failed = true;
                    return;
                }
                root.current = r.current;
                root.days = r.days;
                root.place = r.place;
                root.loaded = true;
                root.failed = false;
                root.updatedMs = Date.now();
            }
        }
        onExited: code => {
            if (code !== 0)
                root.failed = true;
        }
    }
}
