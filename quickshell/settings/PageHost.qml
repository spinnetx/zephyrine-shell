import QtQuick
import "../"
import "../components"

// Область страницы окна настроек: прокручиваемый столбец, в который по section загружается страница.
// Смена раздела — плавное появление (opacity 0→1, сдвиг y 8→0, DESIGN §6.4) и прокрутка в начало.
// «Внешний вид» — pages/AppearancePage.qml: страница сама прокручивается и держит снекбар, поэтому грузится
// мимо общего Flickable и остаётся жить при смене раздела (состояние, статус целей). «Сеть и Bluetooth» — pages/NetworkSection.qml (тоже сама прокручивается). Этапы 3–4 пока «скоро».
Item {
    id: root

    property string section: "appearance"
    property string sub: ""          // подраздел из openAt("раздел/подраздел"); пока только показывается в заглушке

    readonly property var soonInfo: ({
        "network": "Wi-Fi и сохранённые сети, Bluetooth: устройства, видимость, сопряжение.",
        "devices": "Звук (устройства, громкость, приложения), экраны и яркость, профиль питания и простой.",
        "system": "Раскладки и повтор клавиш, сочетания клавиш, приложения по умолчанию, автозапуск, уведомления, сведения о системе."
    })

    property bool networkSeen: section === "network"
    property bool devicesSeen: section === "devices"
    property bool systemSeen: section === "system"

    onSectionChanged: {
        if (section === "network")
            networkSeen = true;
        if (section === "devices")
            devicesSeen = true;
        if (section === "system")
            systemSeen = true;
        flick.contentY = 0;
        enter.restart();
    }

    ParallelAnimation {
        id: enter
        NumberAnimation { target: stage; property: "opacity"; from: 0; to: 1; duration: Config.animMs; easing.type: Config.animEasing }
        NumberAnimation { target: shift; property: "y"; from: 8; to: 0; duration: Config.animMs; easing.type: Config.animEasing }
    }

    Item {
        id: stage
        anchors.fill: parent
        transform: Translate { id: shift }

        Loader {
            id: appearanceLoader
            anchors.fill: parent
            visible: root.section === "appearance"
            source: "pages/AppearancePage.qml"
        }
        Binding {
            target: appearanceLoader.item
            property: "sub"
            value: root.sub
            when: appearanceLoader.item !== null
        }

        // «Сеть и Bluetooth» — pages/NetworkSection.qml (под-вкладки Wi-Fi/Bluetooth, страницы прокручиваются сами).
        // Создаётся при первом заходе в раздел и дальше остаётся жить (состояние, форма).
        Loader {
            id: networkLoader
            anchors.fill: parent
            visible: root.section === "network"
            active: root.networkSeen
            source: "pages/NetworkSection.qml"
        }
        Binding {
            target: networkLoader.item
            property: "sub"
            value: root.sub
            when: networkLoader.item !== null
        }

        // «Звук, экран, питание» — pages/DevicesPage.qml (этап 3).
        Loader {
            id: devicesLoader
            anchors.fill: parent
            visible: root.section === "devices"
            active: root.devicesSeen
            source: "pages/DevicesPage.qml"
        }
        Binding {
            target: devicesLoader.item
            property: "sub"
            value: root.sub
            when: devicesLoader.item !== null
        }

        // «Система и приложения» — pages/SystemSection.qml (этап 4, под-вкладки).
        Loader {
            id: systemLoader
            anchors.fill: parent
            visible: root.section === "system"
            active: root.systemSeen
            source: "pages/SystemSection.qml"
        }
        Binding {
            target: systemLoader.item
            property: "sub"
            value: root.sub
            when: systemLoader.item !== null
        }

        Flickable {
            id: flick
            anchors.fill: parent
            visible: root.section !== "appearance" && root.section !== "network" && root.section !== "devices" && root.section !== "system"
            clip: true
            contentWidth: width
            contentHeight: loader.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Loader {
                id: loader
                width: flick.width
                sourceComponent: (root.section === "appearance" || root.section === "network" || root.section === "devices" || root.section === "system") ? null : soonPage
            }
        }
    }

    // Заглушка разделов этапов 2–4.
    Component {
        id: soonPage
        Column {
            spacing: 12
            SetCard {
                width: parent.width
                title: "Раздел в разработке"
                icon: Config.icons.info
                chipKind: "neutral"
                chipText: "скоро"
                Txt {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Этот раздел ещё не готов."
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Colors.fgVariant
                    text: "Планируется: " + (root.soonInfo[root.section] ?? "")
                }
                Txt {
                    visible: root.sub !== ""
                    width: parent.width
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                    text: "Подраздел: " + root.sub
                }
            }
        }
    }
}
