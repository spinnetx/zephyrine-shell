import QtQuick
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"

// Карточка «Клавиатура» (DESIGN §4.4, Y1): раскладки с вариантами, переключатель раскладок, задержка и частота повтора.
// Каталог xkb — `zephyrine-settings xkb` (base.lst); значения читает из Prefs.file (settings.json), пишет только через
// SettingsCli.set (CLI проверяет раскладки до записи, Hyprland перечитывает settings.lua сам).
SetCard {
    id: root

    title: "Клавиатура"
    icon: Config.icons.keyboard

    property var cat: ({ layouts: [], variants: ({}), switchOptions: [], options: [] })
    property string error: ""
    property bool sent: false

    readonly property var defLayouts: [{ layout: "pl", variant: "" }, { layout: "ru", variant: "" }]
    function val(key, dflt) {
        const v = Prefs.lookup(Prefs.file, key);
        return (v === undefined || v === null) ? dflt : v;
    }
    readonly property var layouts: val("input.layouts", defLayouts)
    readonly property string switchOpt: val("input.switchOption", "grp:alt_shift_toggle")

    readonly property var layoutOptions: cat.layouts.map(l => ({ value: l.id, label: l.id + " — " + l.desc }))
    readonly property var switchChoices: [{ value: "", label: "Нет" }].concat(
        cat.switchOptions.map(o => ({ value: o.id, label: o.desc + " (" + o.id.replace("grp:", "") + ")" })))
    function variantOptions(layout) {
        const vs = cat.variants[layout] ?? [];
        return [{ value: "", label: "По умолчанию" }].concat(vs.map(v => ({ value: v.id, label: v.desc })));
    }

    function save(pairs) {
        error = "";
        sent = true;
        SettingsCli.set(pairs);
    }
    function setLayouts(arr) {
        const p = { "input.layouts": arr };
        // с одной раскладкой переключатель не нужен, со второй — возвращаем разумный
        if (arr.length >= 2 && switchOpt === "")
            p["input.switchOption"] = "grp:alt_shift_toggle";
        save(p);
    }
    function withLayout(i, field, v) {
        const a = layouts.map(l => ({ layout: l.layout, variant: l.variant }));
        a[i][field] = v;
        if (field === "layout")
            a[i].variant = "";
        return a;
    }

    Connections {
        target: SettingsCli
        function onFinished(res, code) {
            if (!root.sent)
                return;
            root.sent = false;
            root.error = code === 0 ? "" : SettingsCli.errorText(res, code);
        }
    }

    Component.onCompleted: catProc.running = true

    Process {
        id: catProc
        command: [Config.settingsCli, "xkb"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ls = String(text).split("\n").filter(l => l.trim() !== "");
                for (let i = ls.length - 1; i >= 0; i--) {
                    try {
                        const o = JSON.parse(ls[i]);
                        if (o.xkb) {
                            root.cat = o.xkb;
                            return;
                        }
                    } catch (e) {}
                }
                root.error = "Не удалось прочитать список раскладок (xkb base.lst)";
            }
        }
    }

    Txt {
        text: "Раскладки"
        color: Colors.fgVariant
        font.pixelSize: Config.fontSize - 1
    }
    Repeater {
        model: root.layouts
        delegate: Row {
            id: lrow
            required property int index
            required property var modelData
            spacing: 8
            SetDropdown {
                width: 240
                options: root.layoutOptions
                current: lrow.modelData.layout
                onSelected: v => root.setLayouts(root.withLayout(lrow.index, "layout", v))
            }
            SetDropdown {
                width: 220
                options: root.variantOptions(lrow.modelData.layout)
                current: lrow.modelData.variant
                onSelected: v => root.setLayouts(root.withLayout(lrow.index, "variant", v))
            }
            SetButton {
                icon: Config.icons.trash
                tooltip: root.layouts.length <= 1 ? "Нужна хотя бы одна раскладка" : "Убрать раскладку"
                enabled: root.layouts.length > 1
                onClicked: root.setLayouts(root.layouts.filter((l, k) => k !== lrow.index))
            }
        }
    }
    SetButton {
        text: "+ раскладка"
        enabled: root.layoutOptions.length > 0
        onClicked: {
            const used = root.layouts.map(l => l.layout);
            const free = root.cat.layouts.find(l => used.indexOf(l.id) < 0);
            if (free)
                root.setLayouts(root.layouts.concat([{ layout: free.id, variant: "" }]));
        }
    }
    SetRow {
        width: parent.width
        label: "Переключение раскладки"
        hint: "Обязательно, если раскладок две и больше"
        SetDropdown {
            width: 280
            options: root.switchChoices
            current: root.switchOpt
            onSelected: v => root.save({ "input.switchOption": v })
        }
    }
    PrefSliderRow {
        width: parent.width
        prefKey: "input.repeatDelay"
        label: "Задержка повтора"
        hint: "Через сколько начинается автоповтор клавиши"
        from: 100
        to: 1000
        step: 10
        decimals: 0
        suffix: " мс"
        defaultValue: 600
        value: root.val(prefKey, 600)
        onCommitted: (k, v) => root.save({ "input.repeatDelay": Math.round(v) })
    }
    PrefSliderRow {
        width: parent.width
        prefKey: "input.repeatRate"
        label: "Частота повтора"
        hint: "Символов в секунду"
        from: 5
        to: 100
        step: 1
        decimals: 0
        suffix: "/с"
        defaultValue: 25
        value: root.val(prefKey, 25)
        onCommitted: (k, v) => root.save({ "input.repeatRate": Math.round(v) })
    }
    Txt {
        visible: root.error.length > 0
        width: parent.width
        text: root.error
        color: Colors.error
        wrapMode: Text.WordWrap
    }
}
