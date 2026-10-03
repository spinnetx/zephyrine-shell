import QtQuick
import "../../"
import "../../services"
import "../../components"

// Карточка «Тачпад» (DESIGN §4.4, Y7): естественная прокрутка, касание = клик, касание и перетаскивание, отключение при
// наборе, клик по числу пальцев, средняя кнопка, скорость прокрутки и чувствительность указателя. Значения читает из
// Prefs.file (settings.json), пишет только через SettingsCli.set; Hyprland подхватывает settings.lua сам.
SetCard {
    id: root

    title: "Тачпад"
    icon: Config.icons.keyboard

    property string error: ""
    property bool sent: false

    function val(key, dflt) {
        const v = Prefs.lookup(Prefs.file, key);
        return (v === undefined || v === null) ? dflt : v;
    }
    function save(pairs) {
        error = "";
        sent = true;
        SettingsCli.set(pairs);
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

    ToggleRow {
        width: parent.width
        label: "Естественная прокрутка"
        hint: "Контент следует за пальцами"
        checked: root.val("input.touchpad.naturalScroll", true)
        onToggled: v => root.save({ "input.touchpad.naturalScroll": v })
    }
    ToggleRow {
        width: parent.width
        label: "Касание = клик"
        checked: root.val("input.touchpad.tapToClick", true)
        onToggled: v => root.save({ "input.touchpad.tapToClick": v })
    }
    ToggleRow {
        width: parent.width
        label: "Касание и перетаскивание"
        hint: "Коснуться, коснуться и вести — перетащить"
        checked: root.val("input.touchpad.tapAndDrag", true)
        onToggled: v => root.save({ "input.touchpad.tapAndDrag": v })
    }
    ToggleRow {
        width: parent.width
        label: "Отключать при наборе"
        hint: "Защита от случайных касаний ладонью"
        checked: root.val("input.touchpad.disableWhileTyping", true)
        onToggled: v => root.save({ "input.touchpad.disableWhileTyping": v })
    }
    ToggleRow {
        width: parent.width
        label: "Клик по числу пальцев"
        hint: "1/2/3 пальца — левая/правая/средняя кнопка вместо зон тачпада"
        checked: root.val("input.touchpad.clickfinger", true)
        onToggled: v => root.save({ "input.touchpad.clickfinger": v })
    }
    ToggleRow {
        width: parent.width
        label: "Средняя кнопка двумя нажатиями"
        hint: "Левая и правая кнопки одновременно"
        checked: root.val("input.touchpad.middleButtonEmulation", false)
        onToggled: v => root.save({ "input.touchpad.middleButtonEmulation": v })
    }
    PrefSliderRow {
        width: parent.width
        prefKey: "input.touchpad.scrollFactor"
        label: "Скорость прокрутки"
        from: 0.2
        to: 3
        step: 0.1
        decimals: 1
        suffix: "×"
        defaultValue: 1
        value: root.val(prefKey, 1)
        onCommitted: (k, v) => root.save({ "input.touchpad.scrollFactor": Math.round(v * 10) / 10 })
    }
    PrefSliderRow {
        width: parent.width
        prefKey: "input.sensitivity"
        label: "Чувствительность указателя"
        hint: "Для всех указателей; 0 — без изменений"
        from: -1
        to: 1
        step: 0.05
        decimals: 2
        defaultValue: 0
        value: root.val(prefKey, 0)
        onCommitted: (k, v) => root.save({ "input.sensitivity": Math.round(v * 100) / 100 })
    }
    Txt {
        visible: root.error.length > 0
        width: parent.width
        text: root.error
        color: Colors.error
        wrapMode: Text.WordWrap
    }
}
