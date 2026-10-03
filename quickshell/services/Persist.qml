pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Мелкое постоянное состояние шелла в ~/.local/state/zephyrine/state.json (сейчас: флаг DND и
// id процесса, для которого уже показан стартовый тост). Каталог создаётся при старте;
// пока файл не прочитан (ready=false), изменения не записываются — иначе затрём сохранённое.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/zephyrine"

    property bool ready: false
    // true — шелл запущен «по-настоящему» (новый процесс), false — live-reload того же процесса.
    property bool freshStart: false
    property bool dnd: false

    // Записать текущее значение в файл (вызывают владельцы полей).
    function save() {
        if (!ready)
            return;
        adapter.dnd = root.dnd;
        view.writeAdapter();
    }

    Process {
        running: true
        command: ["mkdir", "-p", root.dir]
        onExited: view.path = root.dir + "/state.json"
    }

    FileView {
        id: view
        printErrors: false
        atomicWrites: true

        adapter: JsonAdapter {
            id: adapter
            property bool dnd: false
            property string instance: ""
        }

        function finish() {
            root.dnd = adapter.dnd;
            root.freshStart = adapter.instance !== Quickshell.instanceId;
            adapter.instance = Quickshell.instanceId;
            root.ready = true;
            if (root.freshStart)
                view.writeAdapter();
        }
        onLoaded: finish()
        // Файла ещё нет — первый запуск: пишем дефолты при первом изменении.
        onLoadFailed: finish()
    }
}
