import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../components"

// Раздел «Сеть и Bluetooth» (DESIGN §6.5): под-вкладки «Wi-Fi» и «Bluetooth». Подраздел приходит из openAt
// («network/wifi», «network/bluetooth»). Wi-Fi — pages/NetworkPage.qml; Bluetooth — pages/BluetoothPage.qml, если файл
// есть (проверяется при открытии вкладки), иначе заглушка «скоро». Страницы прокручиваются сами.
Item {
    id: root

    property string sub: ""              // из Overlays.settingsSub; "wifi" | "bluetooth" | ""
    property string tab: "wifi"
    property bool btExists: false
    property bool btChecked: false

    readonly property string btFile: Quickshell.shellPath("settings/pages/BluetoothPage.qml")   // путь на диске (URL компонента виртуальный qs:@/…)

    onSubChanged: applySub()
    Component.onCompleted: applySub()

    function applySub() {
        if (sub === "wifi" || sub === "bluetooth")
            tab = sub;
    }

    onTabChanged: if (tab === "bluetooth") checkBt()

    function checkBt() {
        if (!btCheck.running)
            btCheck.running = true;
    }

    Process {
        id: btCheck
        command: ["test", "-f", root.btFile]
        onExited: code => {
            root.btExists = code === 0;
            root.btChecked = true;
        }
    }

    SetSegmented {
        id: tabs
        anchors {
            left: parent.left
            top: parent.top
        }
        options: [{ value: "wifi", label: "Wi-Fi" }, { value: "bluetooth", label: "Bluetooth" }]
        current: root.tab
        onSelected: v => root.tab = v
    }

    Item {
        anchors {
            left: parent.left
            right: parent.right
            top: tabs.bottom
            topMargin: 12
            bottom: parent.bottom
        }

        Loader {
            anchors.fill: parent
            visible: root.tab === "wifi"
            source: "NetworkPage.qml"
        }

        Loader {
            id: btLoader
            anchors.fill: parent
            visible: root.tab === "bluetooth" && root.btExists
            active: root.btExists
            source: "BluetoothPage.qml"
        }

        // Заглушка, пока страницы Bluetooth нет.
        SetCard {
            visible: root.tab === "bluetooth" && root.btChecked && !root.btExists
            width: parent.width
            title: "Bluetooth"
            icon: Config.icons.bt
            chipKind: "neutral"
            chipText: "скоро"
            Txt {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Colors.fgVariant
                text: "Страница в разработке: устройства, видимость, сопряжение."
            }
        }
    }
}
