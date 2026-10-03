pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Вызов CLI zephyrine-settings (единственного писателя настроек, DESIGN §2.4) и разбор его
// JSON-конверта: {ok, changed[], actions[], restart[], skipped[], errors[], backup}.
// Один процесс за раз; пока идёт вызов, новые set склеиваются (последнее значение ключа побеждает).
// Сам ничего не вызывает при старте шелла: работает только по явным вызовам из окна настроек.
//
//   SettingsCli.set({ "appearance.glassAlpha": 0.82 })
//   SettingsCli.run(["undo"])
Singleton {
    id: root

    property bool busy: false
    // Результат последнего вызова: разобранный конверт (или null) и его код выхода.
    property var lastResult: null
    property int lastExitCode: 0
    // Текст последней ошибки ("" — нет); для строки ошибки в карточке.
    property string lastError: ""
    // Ключи из последнего успешного результата, требующие перезапуска приложений.
    property var restart: []

    // Сигнал после каждого завершённого вызова (result — конверт или null).
    signal finished(var result, int exitCode)

    // Очередь: [{ args: [...] }] и накопленные set-пары.
    property var queue: []
    property var pendingSet: ({})
    property var current: null

    // Разбор stdout: берём последнюю непустую строку, способную стать JSON-объектом.
    function parseEnvelope(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l !== "");
        for (let i = lines.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(lines[i]);
                if (o && typeof o === "object")
                    return o;
            } catch (e) {}
        }
        return null;
    }

    // Значение для KEY=VALUE: JSON-литерал (строки тоже кавычим) — CLI разберёт его сам.
    function encode(v) {
        return JSON.stringify(v);
    }

    // Сообщение об ошибке из конверта/кода выхода.
    function errorText(res, code) {
        if (res && Array.isArray(res.errors) && res.errors.length > 0) {
            return res.errors.map(e => typeof e === "string" ? e : (e.message ?? e.error ?? JSON.stringify(e))).join("; ");
        }
        if (!res)
            return "zephyrine-settings: нет ответа (код " + code + ")";
        return code === 0 ? "" : "zephyrine-settings: код выхода " + code;
    }

    // Записать значения: { key: value, … } одной транзакцией (set KEY=VALUE…).
    function set(pairs) {
        const p = Object.assign({}, pendingSet, pairs);
        pendingSet = p;
        pump();
    }

    // Произвольная команда CLI (reset/undo/apply/status…): args — массив строк без имени программы.
    function run(args) {
        queue = queue.concat([{ args: args }]);
        pump();
    }

    function pump() {
        if (busy)
            return;
        let args = null;
        if (queue.length > 0) {
            args = queue[0].args;
            queue = queue.slice(1);
        } else if (Object.keys(pendingSet).length > 0) {
            args = ["set"];
            for (const k of Object.keys(pendingSet))
                args.push(k + "=" + encode(pendingSet[k]));
            pendingSet = ({});
        }
        if (args === null)
            return;
        current = args;
        busy = true;
        proc.command = [Config.settingsCli].concat(args);
        proc.running = true;
    }

    Process {
        id: proc
        stdout: StdioCollector {
            id: out
        }
        stderr: StdioCollector {
            id: err
        }
        onExited: code => {
            const res = root.parseEnvelope(out.text);
            root.lastResult = res;
            root.lastExitCode = code;
            const ok = code === 0 && res !== null && res.ok !== false;
            root.lastError = ok ? "" : root.errorText(res, code);
            if (!ok && err.text.trim() !== "")
                console.warn("zephyrine-settings:", err.text.trim());
            root.restart = (ok && res && Array.isArray(res.restart)) ? res.restart : [];
            root.current = null;
            root.busy = false;
            root.finished(res, code);
            root.pump();
        }
    }

    // Сторож: если процесс не запустился/завис, очередь не должна встать навсегда.
    Timer {
        interval: 60000
        running: root.busy
        onTriggered: {
            proc.running = false;
            root.lastError = "zephyrine-settings: превышено время ожидания";
            root.lastResult = null;
            root.current = null;
            root.busy = false;
            root.finished(null, -1);
            root.pump();
        }
    }
}
