import QtQuick
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"

// Карточка «Приложения по умолчанию» (DESIGN §4.4, Y3): по категории — выпадающий список приложений, зарегистрированных
// для основного MIME-типа (`zephyrine-settings mime list`); выбор назначает приложение на все типы категории
// (`mime set`, gio mime; для браузера ещё xdg-settings). В settings.json ничего не пишется.
SetCard {
    id: root

    title: "Приложения по умолчанию"
    icon: Config.icons.settings

    property var cats: []
    property string error: ""
    property string pending: ""

    function refresh() {
        if (listProc.running)
            return;
        listProc.running = true;
    }

    function lastJson(text, field) {
        const ls = String(text).split("\n").filter(l => l.trim() !== "");
        for (let i = ls.length - 1; i >= 0; i--) {
            try {
                const o = JSON.parse(ls[i]);
                if (o && typeof o === "object")
                    return o;
            } catch (e) {}
        }
        return null;
    }

    Component.onCompleted: refresh()

    Process {
        id: listProc
        command: [Config.settingsCli, "mime", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.lastJson(text);
                if (o && o.mime)
                    root.cats = o.mime;
                else
                    root.error = "Не удалось получить список приложений (gio mime)";
            }
        }
    }

    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.lastJson(text);
                if (o && o.ok === false)
                    root.error = SettingsCli.errorText(o, 1);
                root.pending = "";
                root.refresh();
            }
        }
    }

    Txt {
        visible: root.error.length > 0
        width: parent.width
        text: root.error
        color: Colors.error
        wrapMode: Text.WordWrap
    }

    Txt {
        visible: root.cats.length > 0 && root.cats.every(c => c.apps.length === 0)
        width: parent.width
        text: "gio не вернул ни одного приложения. Проверьте `gio mime text/plain` и `update-desktop-database`."
        color: Colors.fgVariant
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.cats
        delegate: SetRow {
            id: row
            required property var modelData
            width: root.width - Config.popoutPadding * 2
            label: modelData.label
            hint: modelData.error !== "" ? modelData.error : ""
            dimmed: modelData.apps.length === 0
            SetDropdown {
                width: 260
                options: row.modelData.apps.map(a => ({ value: a.id, label: a.name }))
                current: row.modelData.current ?? undefined
                placeholder: row.modelData.apps.length === 0 ? "нет приложений" : "не выбрано"
                onSelected: v => {
                    root.error = "";
                    root.pending = row.modelData.id;
                    setProc.command = [Config.settingsCli, "mime", "set", row.modelData.id, v];
                    setProc.running = true;
                }
            }
        }
    }
}
