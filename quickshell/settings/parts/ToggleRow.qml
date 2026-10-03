import QtQuick
import "../../components"

// Строка «подпись + переключатель»: ничего не пишет, только сообщает toggled(новое значение).
SetRow {
    id: row

    property bool checked: false
    signal toggled(bool value)

    PopSwitch {
        checked: row.checked
        onToggled: v => row.toggled(v)
    }
}
