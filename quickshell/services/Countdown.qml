pragma Singleton

import QtQuick
import Quickshell
import "../"

// Таймер обратного отсчёта (виджет панели «Таймер», попап kind "timer"). Один на весь шелл: состояние общее для всех
// мониторов. Время считается по часам (endMs), а не по числу тиков, поэтому не уплывает; по окончании — тост и звук.
//   Countdown.start(300); Countdown.toggle(); Countdown.reset()
Singleton {
    id: root

    property int total: 0            // исходная длительность, сек
    property int remaining: 0        // осталось, сек
    property bool running: false
    property bool paused: false
    property bool finished: false    // отсчёт дошёл до нуля (сбрасывается reset/start)
    property real endMs: 0

    readonly property bool active: running || paused || finished
    // Доля прошедшего времени 0..1 (для полосы).
    readonly property real progress: total > 0 ? Math.max(0, Math.min(1, 1 - remaining / total)) : 0

    function fmt(sec) {
        sec = Math.max(0, Math.round(sec));
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
        const pad = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s);
    }
    // Короткая подпись для узкой панели: «5м» / «45с».
    function brief(sec) {
        sec = Math.max(0, Math.round(sec));
        return sec >= 3600 ? Math.ceil(sec / 3600) + "ч" : sec >= 60 ? Math.ceil(sec / 60) + "м" : sec + "с";
    }

    function start(sec) {
        sec = Math.round(sec);
        if (!(sec > 0))
            return;
        total = sec;
        remaining = sec;
        endMs = Date.now() + sec * 1000;
        running = true;
        paused = false;
        finished = false;
    }
    function pause() {
        if (!running)
            return;
        remaining = Math.max(1, Math.ceil((endMs - Date.now()) / 1000));
        running = false;
        paused = true;
    }
    function resume() {
        if (!paused)
            return;
        endMs = Date.now() + remaining * 1000;
        running = true;
        paused = false;
    }
    function toggle() {
        if (running)
            pause();
        else if (paused)
            resume();
    }
    function reset() {
        running = false;
        paused = false;
        finished = false;
        remaining = 0;
        total = 0;
    }

    Timer {
        interval: 250
        repeat: true
        running: root.running
        onTriggered: {
            const r = Math.ceil((root.endMs - Date.now()) / 1000);
            if (r > 0) {
                root.remaining = r;
                return;
            }
            root.running = false;
            root.remaining = 0;
            root.finished = true;
            Toaster.show("Таймер", "Время вышло: " + root.fmt(root.total), Config.icons.timer, "warning");
            // Звук - если есть canberra или pulseaudio/pipewire-pulse; нет - тихо пропускаем.
            Quickshell.execDetached(["sh", "-c", "canberra-gtk-play -i complete 2>/dev/null || paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true"]);
        }
    }
}
