import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "components"
import "services"

// Панель Quickshell. «Плавающая» (отступ barMargin от краёв экрана, скруглена со всех сторон, альфа Config.barAlpha) — ближе
// к Caelestia, чем плоская полоса. Стоит у любой стороны экрана (Config.barPosition: top | bottom | left | right —
// настройка bar.position), состав и порядок элементов в трёх зонах берутся из настроек (bar.left / bar.center / bar.right,
// редактор — центр настроек → Внешний вид → Панель). Горизонтальная панель: слева — воркспейсы/заголовок, по центру —
// медиа, справа — лимиты/мониторинг/трей/статусы/часы/питание. Вертикальная: те же зоны сверху вниз; элементы без
// компактного вида (заголовок окна, медиа, лимиты ИИ, диски) на ней не показываются.
PanelWindow {
    id: win

    readonly property string pos: Config.barPosition
    readonly property bool vertical: Config.barVertical

    anchors {
        top: pos === "top" || vertical
        bottom: pos === "bottom" || vertical
        left: pos === "left" || !vertical
        right: pos === "right" || !vertical
    }
    color: "transparent"
    WlrLayershell.namespace: "zephyrine"
    WlrLayershell.layer: WlrLayer.Top

    // Размер поперёк экрана = бар + отступ от края; столько же резервируем у окон.
    implicitHeight: vertical ? 0 : Config.barExtent
    implicitWidth: vertical ? Config.barExtent : 0
    exclusiveZone: Config.barExtent

    // Единая hover-карточка рядом с баром (содержимое — popouts/*, состояние — PopoutState).
    Popout {
        bar: win
    }

    // Реестр элементов панели: id (как в settings/zsettings/barlayout.py) -> компонент для горизонтальной (h) и
    // вертикальной (v) панели; v: null — на вертикальной панели элемент не показывается.
    readonly property var registry: ({
        workspaces: { h: cWorkspaces, v: cVWorkspaces },
        activeWindow: { h: cActiveWindow, v: null },
        media: { h: cMedia, v: null },
        limits: { h: cLimits, v: null },
        disk: { h: cDisk, v: null },
        gpu: { h: cGpu, v: cVGpu },
        cpu: { h: cCpu, v: cVCpu },
        mem: { h: cMem, v: cVMem },
        net: { h: cNet, v: cVNet },
        tray: { h: cTray, v: cVTray },
        status: { h: cStatus, v: cVStatus },
        clock: { h: cClock, v: cVClock },
        power: { h: cPower, v: cPower },
        temp: { h: cTemp, v: cVTemp },
        battery: { h: cBattery, v: cVBattery },
        kbd: { h: cKbd, v: cVKbd },
        timer: { h: cTimer, v: cVTimer },
        weather: { h: cWeather, v: cVWeather },
        volume: { h: cVolume, v: cVVolume },
        wifi: { h: cWifi, v: cVWifi },
        bluetooth: { h: cBluetooth, v: cVBluetooth },
        apps: { h: cApps, v: cVApps }
    })

    Component { id: cWorkspaces; Workspaces { screen: win.screen } }
    Component { id: cActiveWindow; ActiveWindow {} }
    Component { id: cMedia; Media {} }
    Component { id: cLimits; Limits {} }
    Component { id: cDisk; DiskSpace {} }
    Component { id: cGpu; GpuMon {} }
    Component { id: cCpu; CpuMon {} }
    Component { id: cMem; MemMon {} }
    Component { id: cNet; NetMon {} }
    Component { id: cTray; Tray {} }
    Component { id: cStatus; StatusIcons {} }
    Component { id: cClock; Clock {} }
    Component { id: cPower; PowerButton {} }
    Component { id: cTemp; TempMon {} }
    Component { id: cBattery; BatteryMon {} }
    Component { id: cKbd; KbdLayout {} }
    Component { id: cTimer; TimerPill {} }
    Component { id: cWeather; WeatherPill {} }
    Component { id: cVolume; VolumePill {} }
    Component { id: cWifi; WifiPill {} }
    Component { id: cBluetooth; BluetoothPill {} }
    Component { id: cApps; AppsButton {} }

    Component { id: cVWorkspaces; VWorkspaces { screen: win.screen } }
    Component {
        id: cVGpu
        IconPill {
            icon: Config.icons.gpu
            iconColor: Gpu.state === "active" ? Gpu.loadColor(Gpu.util) : Gpu.state === "error" ? Colors.error : Colors.fgVariant
            kind: "gpu"
            shown: Gpu.state !== "none"
            tooltip: Gpu.state === "active" ? "GPU " + Math.round(Gpu.util * 100) + "%" : "GPU: " + Gpu.state
        }
    }
    Component {
        id: cVCpu
        IconPill {
            icon: Config.icons.chip
            iconColor: SysMon.loadColor(SysMon.cpuTotal)
            kind: "cpu"
            tooltip: "CPU " + Math.round(SysMon.cpuTotal * 100) + "%"
        }
    }
    Component {
        id: cVMem
        IconPill {
            icon: Config.icons.memory
            iconColor: SysMon.memFrac >= Config.memCrit ? Colors.error : SysMon.memFrac >= Config.memWarn ? Colors.tertiary : Colors.primary
            kind: "mem"
            tooltip: "Память: " + SysMon.fmtGiB(SysMon.memUsed) + " (" + Math.round(SysMon.memFrac * 100) + "%)"
        }
    }
    Component {
        id: cVNet
        IconPill {
            icon: Config.icons.arrowDown
            iconColor: SysMon.rxRate >= 1 || SysMon.txRate >= 1 ? Colors.tertiary : Colors.fgVariant
            kind: "net"
            tooltip: "↓ " + SysMon.fmtRate(SysMon.rxRate).trim() + "  ↑ " + SysMon.fmtRate(SysMon.txRate).trim()
        }
    }
    Component {
        id: cVTemp
        IconPill {
            readonly property real cpu: SysMon.cpuTempC
            readonly property real gpu: Gpu.state === "active" ? Gpu.tempC : -1
            icon: Config.icons.thermometer
            iconColor: Math.max(cpu, gpu) >= Config.tempCritC ? Colors.error : Math.max(cpu, gpu) >= Config.tempWarnC ? Colors.tertiary : Colors.primary
            shown: cpu >= 0 || gpu >= 0
            tooltip: (cpu >= 0 ? "Процессор: " + Math.round(cpu) + " °C" : "") + (cpu >= 0 && gpu >= 0 ? "\n" : "") + (gpu >= 0 ? "Видеокарта: " + Math.round(gpu) + " °C" : "")
        }
    }
    Component {
        id: cVBattery
        IconPill {
            readonly property var bat: UPower.displayDevice
            readonly property bool charging: bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged
            readonly property bool critical: !charging && bat.percentage < Config.batteryCritical
            icon: charging ? Config.icons.batteryCharging : critical ? Config.icons.batteryLow : Config.icons.battery
            iconColor: critical ? Colors.error : charging ? Colors.success : Colors.primary
            kind: "battery"
            shown: bat.isPresent
            tooltip: (charging ? "Заряжается " : "От батареи ") + Math.round(bat.percentage * 100) + "%"
        }
    }
    Component {
        id: cVKbd
        IconPill {
            label: Kbd.abbr
            iconColor: Colors.tertiary
            shown: Kbd.layout !== ""
            clickable: true
            tooltip: "Раскладка: " + Kbd.layout + "\nКлик — следующая"
            onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
        }
    }
    Component {
        id: cVTimer
        IconPill {
            icon: Config.icons.timer
            label: Countdown.active ? (Countdown.finished ? "0с" : Countdown.brief(Countdown.remaining)) : ""
            iconColor: Countdown.finished ? Colors.error : Countdown.paused ? Colors.fgVariant : Countdown.active ? Colors.tertiary : Colors.primary
            kind: "timer"
            clickable: true
            onClicked: {
                if (Countdown.finished)
                    Countdown.reset();
                else
                    Countdown.toggle();
            }
        }
    }
    Component {
        id: cVWeather
        IconPill {
            icon: Config.icons.weather
            label: Weather.loaded ? Weather.icon : ""
            iconColor: Weather.failed && !Weather.loaded ? Colors.fgVariant : Colors.primary
            kind: "weather"
            clickable: true
            onClicked: Weather.refresh()
        }
    }
    Component {
        id: cVVolume
        IconPill {
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property real vol: sink?.audio?.volume ?? 0
            readonly property bool muted: sink?.audio?.muted ?? false
            icon: muted ? Config.icons.volMute : vol > 0.66 ? Config.icons.volHigh : vol > 0.33 ? Config.icons.volMed : vol > 0 ? Config.icons.volLow : Config.icons.volOff
            iconColor: muted ? Colors.fgVariant : Colors.primary
            kind: "audio"
            shown: sink !== null
            clickable: true
            tooltip: (sink?.description ?? "") + " " + Math.round(vol * 100) + "%" + (muted ? "\nЗвук выключен" : "")
            onClicked: if (sink?.audio) sink.audio.muted = !sink.audio.muted
            onScrolled: delta => {
                if (!sink?.audio)
                    return;
                const v = sink.audio.volume + (delta > 0 ? Config.volumeStep : -Config.volumeStep);
                sink.audio.volume = Math.max(0, Math.min(Config.volumeMax, v));
            }
            PwObjectTracker {
                objects: parent.sink ? [parent.sink] : []
            }
        }
    }
    Component {
        id: cVWifi
        IconPill {
            icon: Net.kind === "ethernet" ? Config.icons.ethernet
                : Net.kind === "wifi" ? (Net.signal > 75 ? Config.icons.wifi4 : Net.signal > 50 ? Config.icons.wifi3 : Net.signal > 25 ? Config.icons.wifi2 : Config.icons.wifi1)
                : Config.icons.wifiOff
            iconColor: Net.kind === "none" ? Colors.fgVariant : Colors.tertiary
            kind: "wifi"
            tooltip: Net.kind === "wifi" ? "Wi-Fi: " + Net.ssid + " (" + Net.signal + "%)" : Net.kind === "ethernet" ? "Ethernet" : "Нет сети"
        }
    }
    Component {
        id: cVBluetooth
        IconPill {
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)
            icon: !(adapter?.enabled) ? Config.icons.btOff : connected.length > 0 ? Config.icons.btConnected : Config.icons.bt
            iconColor: adapter?.enabled ? Colors.primary : Colors.fgVariant
            kind: "bluetooth"
            shown: adapter !== null
            clickable: true
            onClicked: if (adapter) adapter.enabled = !adapter.enabled
        }
    }
    Component {
        id: cVApps
        IconPill {
            id: appsPill
            icon: Config.icons.apps
            clickable: true
            tooltip: "Приложения"
            onClicked: PopoutState.togglePinnedAt("apps", appsPill)
        }
    }
    Component { id: cVTray; VTray {} }
    Component { id: cVStatus; VStatus {} }
    Component { id: cVClock; VClock {} }

    // Один слот зоны: компонент элемента по id; пока элемент скрыт (shown === false) — слот не занимает места в Row/Column.
    Component {
        id: slot
        Loader {
            required property string modelData
            readonly property var entry: win.registry[modelData]
            sourceComponent: entry ? (win.vertical ? entry.v : entry.h) : null
            visible: item ? (item.shown === undefined ? true : item.shown) : false
        }
    }
    Component {
        id: hZone
        Row {
            property var ids: []
            spacing: Config.spacing
            Repeater {
                model: parent.ids
                delegate: slot
            }
        }
    }
    Component {
        id: vZone
        Column {
            property var ids: []
            spacing: Config.spacing
            Repeater {
                model: parent.ids
                delegate: slot
            }
        }
    }

    Rectangle {
        id: bg
        anchors {
            fill: parent
            topMargin: win.pos === "bottom" ? 0 : Config.barMargin
            bottomMargin: win.pos === "top" ? 0 : Config.barMargin
            leftMargin: win.pos === "right" ? 0 : Config.barMargin
            rightMargin: win.pos === "left" ? 0 : Config.barMargin
        }
        radius: Config.barRadius
        color: Qt.alpha(Colors.background, Config.barAlpha)
        border.width: 1
        border.color: Qt.alpha(Colors.outlineVariant, 0.5)

        // Начало зоны: слева (горизонтальная) / сверху (вертикальная).
        Loader {
            id: startZone
            sourceComponent: win.vertical ? vZone : hZone
            onLoaded: item.ids = Qt.binding(() => Prefs.barLeft)
            anchors.left: win.vertical ? undefined : parent.left
            anchors.leftMargin: Config.spacing
            anchors.verticalCenter: win.vertical ? undefined : parent.verticalCenter
            anchors.top: win.vertical ? parent.top : undefined
            anchors.topMargin: Config.spacing
            anchors.horizontalCenter: win.vertical ? parent.horizontalCenter : undefined
        }

        // Середина.
        Loader {
            id: midZone
            sourceComponent: win.vertical ? vZone : hZone
            onLoaded: item.ids = Qt.binding(() => Prefs.barCenter)
            anchors.centerIn: parent
        }

        // Конец зоны: справа / снизу.
        Loader {
            id: endZone
            sourceComponent: win.vertical ? vZone : hZone
            onLoaded: item.ids = Qt.binding(() => Prefs.barRight)
            anchors.right: win.vertical ? undefined : parent.right
            anchors.rightMargin: Config.spacing
            anchors.verticalCenter: win.vertical ? undefined : parent.verticalCenter
            anchors.bottom: win.vertical ? parent.bottom : undefined
            anchors.bottomMargin: Config.spacing
            anchors.horizontalCenter: win.vertical ? parent.horizontalCenter : undefined
        }
    }
}
