import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"
import "../parts"

// Страница «Звук, экран, питание» (DESIGN §4.3, §6.5, этап 3), под-вкладки «Звук» · «Экраны» · «Питание» (SetSegmented, как в NetworkSection):
// - AudioCard: устройства, громкость, потоки приложений, pavucontrol.
// - DisplaysCard: конфигурация мониторов, относительное положение, яркость, сторож отката.
// - PowerCard: профиль питания, батарея, таймауты простоя (hypridle).
// - MonitorConfirm: всплывающий диалог обратного отсчёта при тестировании новых параметров экрана.
Item {
    id: root

    property string sub: ""              // "audio" | "display" | "power" | ""
    property string tab: "audio"
    property bool confirmOpen: false
    property string confirmToken: ""
    property int confirmTimeout: 15

    onTabChanged: flick.contentY = 0
    onSubChanged: applySub()
    Component.onCompleted: applySub()

    function applySub() {
        if (sub === "audio" || sub === "power")
            tab = sub;
        else if (sub === "display" || sub === "screens")
            tab = "display";
    }

    SetSegmented {
        id: tabs
        anchors {
            left: parent.left
            top: parent.top
        }
        options: [
            { value: "audio", label: "Звук" },
            { value: "display", label: "Экраны" },
            { value: "power", label: "Питание" }
        ]
        current: root.tab
        onSelected: v => root.tab = v
    }

    Flickable {
        id: flick
        anchors {
            left: parent.left
            right: parent.right
            top: tabs.bottom
            topMargin: 12
            bottom: parent.bottom
        }
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 20
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: 16

            AudioCard {
                id: audioCard
                width: parent.width
                visible: root.tab === "audio"
            }

            DisplaysCard {
                id: displaysCard
                width: parent.width
                visible: root.tab === "display"
                onTryPending: (tok, tout) => {
                    root.confirmToken = tok;
                    root.confirmTimeout = tout || 15;
                    root.confirmOpen = true;
                }
            }

            PowerCard {
                id: powerCard
                width: parent.width
                visible: root.tab === "power"
            }
        }
    }

    // Диалог подтверждения мониторов (поверх всей страницы)
    MonitorConfirm {
        id: monitorConfirm
        visible: root.confirmOpen
        token: root.confirmToken
        timeoutSec: root.confirmTimeout

        onConfirmed: {
            root.confirmOpen = false;
            confirmProc.command = [Config.settingsCli, "monitors", "confirm", root.confirmToken];
            confirmProc.running = true;
        }

        onReverted: {
            root.confirmOpen = false;
            revertProc.command = [Config.settingsCli, "monitors", "revert", root.confirmToken];
            revertProc.running = true;
        }
    }

    Process {
        id: confirmProc
        onExited: code => {
            if (code === 0) {
                Toaster.show("Экраны", "Новые настройки экранов сохранены", "", "success");
            } else {
                Toaster.show("Экраны", "Ошибка подтверждения параметров экрана", "", "error");
            }
            displaysCard.refresh();
        }
    }

    Process {
        id: revertProc
        onExited: code => {
            Toaster.show("Экраны", "Прежние настройки экранов возвращены", "", "info");
            displaysCard.refresh();
        }
    }
}
