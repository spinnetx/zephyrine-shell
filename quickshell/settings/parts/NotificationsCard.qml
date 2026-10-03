import QtQuick
import "../../"
import "../../services"
import "../../components"

// Карточка «Уведомления» (DESIGN §4.4, Y5): «Не беспокоить», critical в DND, время показа тоста, размер истории,
// очистка. Значения читает из Prefs (settings.json), пишет только через SettingsCli.set; DND — живой Notifs.dnd.
SetCard {
    id: root

    title: "Уведомления"
    icon: Config.icons.bell
    chipKind: Notifs.dnd ? "manual" : "neutral"
    chipText: Notifs.dnd ? "не беспокоить" : ""

    SetRow {
        width: parent.width
        label: "Не беспокоить"
        hint: "Тосты не показываются; история и точка на часах работают"
        PopSwitch {
            checked: Notifs.dnd
            onToggled: v => Notifs.dnd = v
        }
    }
    SetRow {
        width: parent.width
        label: "Важные показывать в DND"
        hint: "Critical-уведомления всё равно появятся"
        PopSwitch {
            checked: Prefs.dndAllowCritical
            onToggled: v => SettingsCli.set({ "notifications.dndAllowCritical": v })
        }
    }
    PrefSliderRow {
        width: parent.width
        prefKey: "notifications.toastMs"
        label: "Время показа"
        hint: "Если отправитель не задал своё"
        from: 1000
        to: 30000
        step: 500
        decimals: 0
        defaultValue: 5000
        value: Prefs.toastMs
        suffix: " мс"
        onCommitted: (k, v) => SettingsCli.set({ "notifications.toastMs": Math.round(v) })
    }
    PrefSliderRow {
        width: parent.width
        prefKey: "notifications.historyMax"
        label: "Размер истории"
        hint: "Сколько уведомлений хранить"
        from: 10
        to: 500
        step: 10
        decimals: 0
        defaultValue: 50
        value: Prefs.historyMax
        onCommitted: (k, v) => SettingsCli.set({ "notifications.historyMax": Math.round(v) })
    }
    SetRow {
        width: parent.width
        label: "История"
        hint: Notifs.count + " в истории, непрочитанных: " + Notifs.unread
        SetButton {
            text: "Очистить историю"
            kind: "danger"
            confirm: true
            enabled: Notifs.count > 0
            onClicked: Notifs.clearAll()
        }
    }
}
