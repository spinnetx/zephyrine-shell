import QtQuick
import "../../"
import "../../components"

// Строка «подпись + ползунок ключа настроек»: превью при движении, фиксация при отпускании.
// Ничего не пишет: previewed/committed уходят на страницу, она решает, что делать (Prefs.preview, SettingsCli.set).
SetRow {
    id: root

    property string prefKey: ""
    property real from: 0
    property real to: 1
    property real step: 0
    property int decimals: 2
    property string suffix: ""
    property real defaultValue: NaN
    property alias value: slider.value
    signal previewed(string key, real v)
    signal committed(string key, real v)

    SetSlider {
        id: slider
        from: root.from
        to: root.to
        step: root.step
        decimals: root.decimals
        suffix: root.suffix
        defaultValue: root.defaultValue
        showReset: true
        onPreview: v => root.previewed(root.prefKey, v)
        onCommit: v => root.committed(root.prefKey, v)
    }
}
