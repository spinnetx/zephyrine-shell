pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// Тосты-сообщения самого шелла («Панель запущена», ошибка Wi-Fi…). Отображаются в том же стеке,
// что и уведомления (toasts/Toasts.qml), но не попадают в историю уведомлений.
//   Toaster.show("Wi-Fi", "Подключено к Home", "", "success")
// type: info | success | warning | error; icon — необязательный глиф Nerd Font (иначе по типу).
Singleton {
    id: root

    // Активные сообщения, новые первыми: [{key, title, message, icon, type, t}].
    property var list: []
    property int seq: 0

    function show(title, message, icon, type) {
        const t = ["info", "success", "warning", "error"].includes(type) ? type : "info";
        const item = {
            key: "msg" + (++seq),
            title: title ?? "",
            message: message ?? "",
            icon: icon ?? "",
            type: t,
            t: Date.now()
        };
        list = [item].concat(list).slice(0, Config.toastMax);
    }

    function hide(key) {
        list = list.filter(m => m.key !== key);
    }

    Component.onCompleted: {
        if (Persist.ready && Persist.freshStart)
            show("Панель запущена", "", "", "info");
    }

    // Стартовый тост — только при реальном запуске процесса (не при live-reload; см. Persist).
    Connections {
        target: Persist
        function onReadyChanged() {
            if (Persist.ready && Persist.freshStart)
                root.show("Панель запущена", "", "", "info");
        }
    }

    IpcHandler {
        target: "toaster"

        function show(title: string, message: string, type: string): void {
            root.show(title, message, "", type);
        }
        // То же самое под другим именем: CLI `qs ipc call toaster show …` путает «show» с подкомандой
        // `qs ipc show` (ошибка «arguments were not expected») — из скриптов вызывайте `notify`.
        function notify(title: string, message: string, type: string): void {
            root.show(title, message, "", type);
        }
    }
}
