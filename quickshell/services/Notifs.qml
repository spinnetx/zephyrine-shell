pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../"

// Демон уведомлений (org.freedesktop.Notifications) + история, сохраняемая в ~/.local/state/zephyrine/notifs.json.
// Единая модель для UI: `items`/`list` — JS-обёртки, новые первыми:
//   {uid, appName, appIcon, image, summary, body, urgency, time, read, hadActions, nid, inst, live}
// `live` — живой объект Notification (кнопки, CloseNotification) или null для «архивной» записи,
// восстановленной из файла. uid присваивается при первом появлении и хранится в файле (id записи).
// Дедупликация: (1) после live-reload сервер повторно присылает уже известные Notification
// (lastGeneration) — они привязываются к записи из файла по (inst = Quickshell.instanceId, nid = id уведомления);
// (2) свежее уведомление, совпавшее с архивной записью по (appName, summary, body, time±2с), не дублируется.
// Тосты: uid записей, показанных всплывашкой (`toastIds`), ставятся только для новых живых уведомлений
// (после live-reload/рестарта тост не повторяется), снимаются hideToast() — запись в истории остаётся.
Singleton {
    id: root

    // Записи истории, новые первыми.
    property var items: []
    readonly property var list: items
    readonly property int count: items.length
    // Непрочитанные: пришли, пока попап часов не открывался (флаг `read` сохраняется в файл).
    readonly property int unread: items.filter(w => !w.read).length
    // История загружена из файла (до этого приходящие уведомления ждут в `pending`).
    property bool loaded: false
    property var pending: []
    property var uidOf: ({})   // id живого Notification → uid
    property int seq: 0

    // «Не беспокоить»: тосты не показываются (critical — по Config.dndAllowCritical); история и точка на часах работают.
    // Сохраняется в state.json (services/Persist.qml).
    property bool dnd: false
    onDndChanged: {
        if (dnd) {
            // Включили DND — уже висящие обычные тосты убираем.
            for (const n of items)
                if (toastIds[n.uid] && !isCritical(n))
                    hideToast(n);
        }
        if (Persist.ready && Persist.dnd !== dnd) {
            Persist.dnd = dnd;
            Persist.save();
        }
    }
    Connections {
        target: Persist
        function onReadyChanged() {
            if (Persist.ready) {
                root.dnd = Persist.dnd;
                root.startLoad();
            }
        }
    }
    Component.onCompleted: {
        if (Persist.ready) {
            dnd = Persist.dnd;
            startLoad();
        }
    }

    // --- Файл истории ---
    readonly property string file: Persist.dir + "/notifs.json"
    property bool loadStarted: false

    // Создаёт файл с правами 600 (QSaveFile при атомарной записи сохраняет права существующего файла),
    // затем привязывает FileView.
    function startLoad() {
        if (loadStarted)
            return;
        loadStarted = true;
        prep.running = true;
    }
    Process {
        id: prep
        command: ["sh", "-c", "umask 077; [ -e \"$1\" ] || : > \"$1\"; chmod 600 \"$1\"", "sh", root.file]
        onExited: view.path = root.file
    }
    FileView {
        id: view
        printErrors: false
        atomicWrites: true
        onLoaded: root.restore(text())
        onLoadFailed: root.restore("")
    }
    // Запись с дебаунсом 500 мс.
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: if (root.loaded) view.setText(JSON.stringify(root.serialize(), null, 1))
    }

    function cleanImage(s) {
        if (typeof s !== "string" || s === "")
            return "";
        if (s.startsWith("/") || s.startsWith("file:"))
            return s.length <= 1024 ? s : "";
        if (s.startsWith("data:") && s.length <= 65536)
            return s;
        return "";
    }

    function serialize() {
        return items.map(w => ({
                    id: w.uid,
                    appName: w.appName,
                    // image://icon/<имя> (hint image-path с именем иконки) сохраняем как имя иконки.
                    appIcon: w.appIcon !== "" || !w.image.startsWith("image://icon/") ? w.appIcon : w.image.slice(13),
                    image: cleanImage(w.image),
                    summary: w.summary,
                    body: w.body,
                    urgency: w.urgency,
                    time: w.time,
                    read: w.read,
                    hadActions: w.hadActions,
                    nid: w.nid,
                    inst: w.inst
                }));
    }

    function str(v, max) {
        return typeof v === "string" ? v.slice(0, max) : "";
    }

    // Архивная запись из JSON-объекта файла (null — мусор).
    function fromRecord(r) {
        if (!r || typeof r !== "object" || typeof r.time !== "number" || !isFinite(r.time))
            return null;
        return {
            uid: typeof r.id === "string" && r.id !== "" ? r.id : newUid(),
            appName: str(r.appName, 200),
            appIcon: str(r.appIcon, 1024),
            image: cleanImage(r.image),
            summary: str(r.summary, 2000),
            body: str(r.body, 20000),
            urgency: r.urgency === 0 || r.urgency === 2 ? r.urgency : 1,
            time: r.time,
            read: r.read === true,
            hadActions: r.hadActions === true,
            nid: typeof r.nid === "number" ? r.nid : -1,
            inst: str(r.inst, 64),
            live: null
        };
    }

    function restore(txt) {
        let arr = [];
        try {
            const d = JSON.parse(txt);
            if (Array.isArray(d))
                arr = d;
        } catch (e) {
            arr = [];
        }
        const out = [];
        const seen = {};
        for (const r of arr) {
            const w = fromRecord(r);
            if (w && !seen[w.uid]) {
                seen[w.uid] = true;
                out.push(w);
            }
        }
        out.sort((a, b) => b.time - a.time);
        items = out.slice(0, Config.notifMax);
        loaded = true;
        // Всё, что пришло/уже жило на сервере, пока файл читался.
        const p = pending;
        pending = [];
        for (const n of p)
            handleLive(n, n.lastGeneration);
        for (const n of server.trackedNotifications.values.slice())
            handleLive(n, true);
    }

    // --- Тосты ---
    // uid → true, пока запись показана всплывашкой; toastList — живые записи с тостом, новые первыми.
    property var toastIds: ({})
    readonly property var toastList: items.filter(w => w.live && toastIds[w.uid] === true)

    function isCritical(n) {
        return n.urgency === NotificationUrgency.Critical;
    }

    function hideToast(n) {
        if (!toastIds[n.uid])
            return;
        const t = Object.assign({}, toastIds);
        delete t[n.uid];
        toastIds = t;
    }

    // Сколько мс держать тост: 0 — не закрывать (critical), иначе expireTimeout или дефолт.
    // expireTimeout в Quickshell 0.3.1 приходит в миллисекундах (проверено: notify-send -t 2000 → 2000),
    // несмотря на «секунды» в документации; 0 / -1 — отправитель не задал.
    function toastMs(n) {
        if (isCritical(n))
            return 0;
        const e = n.live ? n.live.expireTimeout : 0;
        return e > 0 ? e : Config.toastDefaultMs;
    }

    function timeOf(n) {
        return n.time;
    }

    // --- Подписи времени ---
    readonly property var monthsShort: ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    // До суток — «только что» / «5 мин назад» / «2 ч назад»; дальше — «вчера 21:34», «30 сен 21:34»,
    // «30 сен 2025 21:34» (другой год). now — внешний тик для обновления.
    function ago(n, now) {
        const s = Math.max(0, Math.floor((now - n.time) / 1000));
        if (s < 60)
            return "только что";
        const m = Math.floor(s / 60);
        if (m < 60)
            return m + " мин назад";
        const h = Math.floor(m / 60);
        if (h < 24)
            return h + " ч назад";
        const d = new Date(n.time);
        const cur = new Date(now);
        const y = new Date(cur.getFullYear(), cur.getMonth(), cur.getDate() - 1);
        const hm = Config.locale.toString(d, "HH:mm");
        if (d.getFullYear() === y.getFullYear() && d.getMonth() === y.getMonth() && d.getDate() === y.getDate())
            return "вчера " + hm;
        let r = d.getDate() + " " + monthsShort[d.getMonth()];
        if (d.getFullYear() !== cur.getFullYear())
            r += " " + d.getFullYear();
        return r + " " + hm;
    }

    // Действие по умолчанию («default»), если отправитель его задал (только у живых).
    function defaultAction(n) {
        return n.live ? (n.live.actions.find(a => a.identifier === "default") ?? null) : null;
    }

    // --- Изменения истории ---
    function newUid() {
        let u;
        do {
            u = Date.now() + "-" + (seq++);
        } while (items.some(w => w.uid === u));
        return u;
    }

    function commit(arr) {
        items = arr;
        saveTimer.restart();
    }

    function wrapLive(n, uid, time, read) {
        return {
            uid: uid,
            appName: n.appName,
            appIcon: n.appIcon,
            image: n.image,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
            time: time,
            read: read,
            hadActions: n.actions.length > 0,
            nid: n.id,
            inst: Quickshell.instanceId,
            live: n
        };
    }

    // Вставка с сохранением порядка «новые первыми» и лимитом Config.notifMax.
    function insert(w) {
        const a = items.slice();
        let i = a.findIndex(x => x.time < w.time);
        if (i < 0)
            i = a.length;
        a.splice(i, 0, w);
        while (a.length > Config.notifMax) {
            const old = a.pop();
            if (old.live)
                old.live.dismiss();
        }
        commit(a);
    }

    function replace(oldW, newW) {
        commit(items.map(x => x === oldW ? newW : x));
    }

    function liveClosed(nid) {
        const uid = uidOf[nid];
        delete uidOf[nid];
        if (uid !== undefined && items.some(w => w.uid === uid))
            commit(items.filter(w => w.uid !== uid));
    }

    // old — уведомление уже жило в процессе до перезагрузки шелла (не показывать тост, не считать новым).
    function handleLive(n, old) {
        if (uidOf[n.id] !== undefined)
            return;
        const now = Date.now();
        let pre = null;
        if (old)
            pre = items.find(w => !w.live && w.inst === Quickshell.instanceId && w.nid === n.id) ?? null;
        else
            pre = items.find(w => !w.live && w.appName === n.appName && w.summary === n.summary && w.body === n.body && Math.abs(w.time - now) <= 2000) ?? null;
        n.closed.connect(() => root.liveClosed(n.id));
        if (pre) {
            uidOf[n.id] = pre.uid;
            replace(pre, wrapLive(n, pre.uid, pre.time, pre.read));
            return;
        }
        const uid = newUid();
        uidOf[n.id] = uid;
        if (old) {
            // Записи в файле нет (первый запуск с историей) — время прихода неизвестно.
            insert(wrapLive(n, uid, now, true));
            return;
        }
        const w = wrapLive(n, uid, now, PopoutState.kind === "clock");
        insert(w);
        // Тост: DND глушит всё, кроме critical (если разрешено в Config).
        if (!dnd || (Config.dndAllowCritical && isCritical(w))) {
            const ids = Object.assign({}, toastIds);
            ids[uid] = true;
            toastIds = ids;
        }
    }

    function dismiss(w) {
        if (w.live)
            w.live.dismiss();
        if (items.includes(w))
            commit(items.filter(x => x !== w));
    }

    function clearAll() {
        // Копия: dismiss() изменяет trackedNotifications на ходу.
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        uidOf = {};
        commit([]);
    }

    function markRead() {
        if (items.some(w => !w.read)) {
            for (const w of items)
                w.read = true;
            commit(items.slice());
        }
    }

    NotificationServer {
        id: server

        // Живёт через live-reload конфига: уведомления и имя на шине не теряются.
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true

        onNotification: n => {
            n.tracked = true;
            // После live-reload сервер повторно присылает уже известные уведомления (lastGeneration).
            // Пока файл истории не прочитан — ждём, чтобы привязать их к сохранённым записям.
            if (!root.loaded) {
                root.pending.push(n);
                return;
            }
            root.handleLive(n, n.lastGeneration);
        }
    }

    // IPC для скриптов и биндов Hyprland: qs -p ~/.config/quickshell/zephyrine ipc call notifs toggle|dnd|clearAll
    IpcHandler {
        target: "notifs"

        // Открыть/закрыть карточку часов (календарь + уведомления), закреплённую на текущем мониторе.
        function toggle(): void {
            PopoutState.togglePinned("clock");
        }
        function dnd(): void {
            root.dnd = !root.dnd;
        }
        function clearAll(): void {
            root.clearAll();
        }
    }

    // Попап часов открыт — всё прочитано.
    Connections {
        target: PopoutState
        function onKindChanged() {
            if (PopoutState.kind === "clock")
                root.markRead();
        }
    }
}
