import QtQuick
import Quickshell.Io
import "../../"

// Агент BlueZ для сопряжения с кодом/PIN (DESIGN §4.2, этап N3): запускает помощник settings/bin/zs-btagent
// (zsettings/btagent.py) и говорит с ним JSON-строками по stdio. Не визуальный; жизнью управляет страница Bluetooth:
// start() — когда нужен (идёт сопряжение / включена видимость), stop() — когда нет. Протокол и события — в шапке btagent.py.
//
//   request  — текущий запрос {id, device, address, kind, passkey?, pin?, uuid?, entered?, timeout} или null
//   remaining — секунд до таймаута запроса, ждущего ответа
//   inputError — текст последней ошибки ввода (неверный PIN/passkey; запрос остаётся)
QtObject {
    id: root

    // Команда запуска; подменяется только в проверках без реального BlueZ.
    property var command: ["zs-btagent"]

    property bool running: false      // процесс запущен (в т.ч. ещё не зарегистрировался)
    property bool ready: false        // агент зарегистрирован в BlueZ
    property var request: null
    property int remaining: 0
    property string inputError: ""
    property string lastError: ""

    // Запрос закончился: reason = answered|rejected|cancel|timeout|dismissed|shutdown; req — как был.
    signal requestEnded(string reason, var req)
    // Процесс завершился (после ready или без него — тогда ready был false).
    signal stopped(bool wasReady)

    readonly property bool awaiting: request !== null && ["confirm", "authorize", "authorize_service", "passkey", "pin"].indexOf(request.kind) >= 0

    function start() {
        if (proc.running || stopTimer.running)
            return;
        lastError = "";
        ready = false;
        proc.command = command;
        proc.stdinEnabled = true;
        proc.running = true;
    }

    // Вежливо: quit по stdin (агент отклонит ждущее и снимет регистрацию); если за 1.5 с не вышел — SIGTERM.
    function stop() {
        if (!proc.running)
            return;
        send({ action: "quit" });
        stopTimer.restart();
    }

    function send(obj) {
        if (proc.running)
            proc.write(JSON.stringify(obj) + "\n");
    }

    function confirm() {
        inputError = "";
        if (request)
            send({ action: "confirm", id: request.id });
    }
    function reject() {
        inputError = "";
        if (request)
            send({ action: "reject", id: request.id });
    }
    function sendPasskey(value) {
        inputError = "";
        if (request)
            send({ action: "passkey", id: request.id, value: String(value) });
    }
    function sendPin(value) {
        inputError = "";
        if (request)
            send({ action: "pin", id: request.id, value: String(value) });
    }

    function handle(line) {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!ev || typeof ev !== "object")
            return;
        if (ev.event === "ready") {
            ready = true;
        } else if (ev.event === "pair_request") {
            inputError = "";
            request = ev;
            remaining = Math.round(ev.timeout ?? 0);
        } else if (ev.event === "pair_update") {
            if (request && request.id === ev.id) {
                const r = Object.assign({}, request);
                r.entered = ev.entered;
                request = r;
            }
        } else if (ev.event === "pair_end") {
            if (request && request.id === ev.id) {
                const was = request;
                request = null;
                inputError = "";
                requestEnded(String(ev.reason ?? ""), was);
            }
        } else if (ev.event === "error") {
            if (ev.id !== undefined && request && request.id === ev.id)
                inputError = String(ev.message ?? "");
            else
                lastError = String(ev.message ?? "");
        }
    }

    property Process proc: Process {
        // Пароли/коды в логи не пишем: stdout разбирается только здесь, stderr — только текст ошибок.
        stdout: SplitParser {
            onRead: data => root.handle(data)
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim() !== "")
                    root.lastError = data.trim();
            }
        }
        onRunningChanged: root.running = running
        onExited: {
            const was = root.ready;
            if (root.request) {
                const req = root.request;
                root.request = null;
                root.requestEnded("shutdown", req);
            }
            root.ready = false;
            root.stopTimer.stop();
            root.stopped(was);
        }
    }

    property Timer stopTimer: Timer {
        interval: 1500
        onTriggered: root.proc.running = false
    }

    // Обратный отсчёт для карточки запроса.
    property Timer tick: Timer {
        interval: 1000
        repeat: true
        running: root.awaiting
        onTriggered: if (root.remaining > 0)
            root.remaining -= 1
    }
}
