pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Wi-Fi через nmcli (LC_ALL=C): состояние радио, список сетей, подключение.
// Один опрос на все мониторы. Список обновляется при открытии попапа (refresh())
// и раз в wifiListPollMs, пока попап открыт (через pollActive).
Singleton {
    id: root

    property bool enabled: true
    // [{ssid, signal, security, active}], активная — первой, дальше по убыванию сигнала.
    property var networks: []
    property bool scanning: false
    property bool busy: false           // идёт подключение / переключение радио
    property string connectingSsid: ""
    // Результат последней операции (успех/ошибка nmcli) — показывается в попапе.
    property string message: ""
    property bool messageIsError: false
    // Установлен ли nm-connection-editor (кнопка «Подробнее»).
    property bool hasEditor: false
    // Включается попапом, пока он открыт, — тогда список периодически обновляется.
    property bool pollActive: false
    // SSID сохранённых профилей NetworkManager (для них пароль не спрашиваем сразу).
    property var knownSsids: []

    // Форма подключения внутри карточки попапа: "" (список) | "password" | "hidden".
    property string formMode: ""
    property string formSsid: ""        // для "password": к какой сети подключаемся
    property string formError: ""       // по-русски («Неверный пароль» / «Не удалось подключиться»)
    property string formRaw: ""         // сырое сообщение nmcli (мелким шрифтом)
    readonly property bool formBusy: busy && attempt.fromForm

    // Параметры текущей попытки подключения (пароль здесь НЕ хранится).
    property var attempt: ({ ssid: "", fromForm: false, known: false })
    // Пароль живёт только от connect() до записи в stdin процесса nmcli (onStarted), затем затирается.
    property string pendingPass: ""

    // Разбор строки `nmcli -t`: поля разделены ':', а двоеточие внутри значения экранировано '\:'.
    function splitTerse(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[i + 1];
                i++;
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    function parse(text) {
        const parts = text.split("---");
        enabled = parts[0].trim() === "enabled";
        const bySsid = {};
        for (const line of (parts[1] ?? "").split("\n")) {
            if (line === "")
                continue;
            const f = splitTerse(line);
            if (f.length < 4 || f[0] === "")
                continue;   // скрытые сети (пустой SSID) не показываем
            const n = {
                ssid: f[0],
                signal: Number(f[1]) || 0,
                security: f[2],
                active: f[3] === "*"
            };
            const old = bySsid[n.ssid];
            // Одна SSID может быть на нескольких точках: берём сильнейшую; активный признак сохраняем.
            if (!old) {
                bySsid[n.ssid] = n;
            } else {
                if (n.signal > old.signal)
                    old.signal = n.signal;
                old.active = old.active || n.active;
            }
        }
        networks = Object.values(bySsid).sort((a, b) => (b.active - a.active) || (b.signal - a.signal));
    }

    // rescan=true — сначала `nmcli device wifi rescan` (может занять пару секунд).
    function refresh(rescan) {
        if (!knownProc.running)
            knownProc.running = true;
        if (listProc.running)
            return;
        scanning = !!rescan;
        listProc.command = ["sh", "-c",
            (rescan ? "nmcli device wifi rescan >/dev/null 2>&1; " : "")
            + "nmcli radio wifi; echo '---'; nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE device wifi list --rescan no"];
        listProc.running = true;
    }

    function setEnabled(on) {
        if (radioProc.running)
            return;
        busy = true;
        radioProc.command = ["nmcli", "radio", "wifi", on ? "on" : "off"];
        radioProc.running = true;
    }

    // Классификация ошибки nmcli: пароль / сеть не найдена / прочее.
    readonly property var passwordErrRe: /secrets|password|psk|802-1x|4-way|supplicant/i

    // Клик по сети в списке: открытая или известная — подключаемся сразу (если известная
    // не подключилась из-за пароля — откроется форма); новая защищённая — сразу форма.
    function select(net) {
        if (connProc.running)
            return;
        const secured = net.security !== "" && net.security !== "--";
        const known = knownSsids.indexOf(net.ssid) >= 0;
        if (secured && !known)
            openForm("password", net.ssid, "", "");
        else
            connect(net.ssid, "", false, false, known);
    }

    // Пароль передаётся ТОЛЬКО через stdin (`nmcli --ask`), в аргументах его нет (не виден в ps).
    function connect(ssid, pass, hidden, fromForm, known) {
        if (connProc.running)
            return;
        busy = true;
        connectingSsid = ssid;
        message = "";
        formError = "";
        formRaw = "";
        attempt = { ssid: ssid, fromForm: fromForm, known: !!known };
        const cmd = ["nmcli"];
        if (pass !== "")
            cmd.push("--ask");
        cmd.push("device", "wifi", "connect", ssid);
        if (hidden)
            cmd.push("hidden", "yes");
        pendingPass = pass;
        connProc.stdinEnabled = pass !== "";
        connProc.command = cmd;
        connProc.running = true;
        watchdog.restart();
    }

    function submitForm(ssid, pass) {
        if (formMode === "password")
            connect(formSsid, pass, false, true, false);
        else if (formMode === "hidden" && ssid.trim() !== "")
            connect(ssid.trim(), pass, true, true, false);
    }

    function openForm(mode, ssid, err, raw) {
        formMode = mode;
        formSsid = ssid;
        formError = err;
        formRaw = raw;
        // Закрепляем попап: не закрывается по уходу курсора, получает клавиатуру (HyprlandFocusGrab в Popout).
        PopoutState.pin();
    }

    function closeForm() {
        if (formMode === "")
            return;
        formMode = "";
        formError = "";
        formRaw = "";
        if (PopoutState.kind === "wifi")
            PopoutState.unpin();
    }

    // Отмена: во время подключения процесс не трогаем (оно дойдёт до конца и покажет тост).
    function cancelForm() {
        closeForm();
    }

    function openEditor() {
        Quickshell.execDetached(["nm-connection-editor"]);
    }

    Process {
        id: listProc
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                root.parse(text);
            }
        }
        onExited: root.scanning = false
    }

    Process {
        id: radioProc
        environment: ({ LC_ALL: "C" })
        onExited: {
            root.busy = false;
            root.refresh(false);
            Net.refresh();
        }
    }

    Process {
        id: connProc
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            id: connOut
        }
        stderr: StdioCollector {
            id: connErr
        }
        onStarted: {
            if (root.pendingPass !== "") {
                write(root.pendingPass + "\n");
                root.pendingPass = "";
                closeStdin.start();   // закрыть stdin: повторный запрос пароля получит EOF, а не зависнет
            }
        }
        onExited: code => {
            watchdog.stop();
            closeStdin.stop();
            root.pendingPass = "";
            stdinEnabled = false;
            root.busy = false;
            root.connectingSsid = "";
            const att = root.attempt;
            const all = (connErr.text + "\n" + connOut.text).split("\n").map(l => l.trim()).filter(l => l !== "");
            // Предпочитаем строку «Error: …»; иначе последнюю непустую (без подсказки пароля).
            const errLine = all.find(l => l.startsWith("Error:")) ?? all[all.length - 1] ?? "";
            const raw = errLine.replace(/^Error: /, "");
            root.refresh(false);
            Net.refresh();
            if (code === 0) {
                root.messageIsError = false;
                root.message = "";
                Toaster.show("Wi-Fi", "Подключено: " + att.ssid, "", "success");
                root.closeForm();
                return;
            }
            const badPass = root.passwordErrRe.test(raw);
            const notFound = /No network with SSID/i.test(raw);
            const human = badPass ? "Неверный пароль" : notFound ? "Сеть не найдена" : "Не удалось подключиться";
            if (att.fromForm) {
                // Остаёмся в форме с сообщением.
                root.formError = human;
                root.formRaw = raw;
                return;
            }
            if (att.known && PopoutState.kind === "wifi" && (badPass || /Activation failed/i.test(raw))) {
                // Известная сеть, но пароль не подошёл/не сохранён — спрашиваем.
                root.openForm("password", att.ssid, human, raw);
                return;
            }
            root.messageIsError = true;
            root.message = raw;
            Toaster.show("Wi-Fi: не удалось подключиться", att.ssid + (raw !== "" ? "\n" + raw : ""), "", "error");
        }
    }

    // Закрывает stdin nmcli вскоре после записи пароля.
    Timer {
        id: closeStdin
        interval: 300
        onTriggered: connProc.stdinEnabled = false
    }

    // Если nmcli завис (ждёт ввода/сеть не отвечает) — прерываем через 60 с.
    Timer {
        id: watchdog
        interval: 60000
        onTriggered: connProc.running = false
    }

    // SSID сохранённых Wi-Fi профилей: по UUID, имя профиля может не совпадать с SSID.
    Process {
        id: knownProc
        environment: ({ LC_ALL: "C" })
        command: ["sh", "-c", "for u in $(nmcli -t -f UUID,TYPE connection show | awk -F: '$2==\"802-11-wireless\"{print $1}'); do nmcli -g 802-11-wireless.ssid connection show \"$u\"; done"]
        stdout: StdioCollector {
            onStreamFinished: root.knownSsids = text.split("\n").filter(l => l !== "")
        }
    }

    Process {
        id: editorCheck
        command: ["sh", "-c", "command -v nm-connection-editor"]
        stdout: StdioCollector {
            onStreamFinished: root.hasEditor = text.trim() !== ""
        }
        running: true
    }

    Timer {
        interval: Config.wifiListPollMs
        running: root.pollActive
        repeat: true
        onTriggered: root.refresh(false)
    }
}
