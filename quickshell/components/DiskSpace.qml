import QtQuick
import "../"
import "../services"

// Свободное место: `/ 51G`, `data 192G` (warning < 20 ГиБ, critical < 10 ГиБ).
Row {
    id: root

    spacing: Config.spacing

    function tint(fs) {
        const l = Disks.level(fs);
        return l === "critical" ? Colors.error : l === "warning" ? Colors.tertiary : Colors.fg;
    }

    Pill {
        tooltip: Disks.tip(Disks.rootFs, "Раздел /")
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: "/ " + (Disks.rootFs.mounted ? Disks.fmt(Disks.rootFs.avail) : "—")
            color: root.tint(Disks.rootFs)
        }
    }
    Pill {
        tooltip: Disks.tip(Disks.dataFs, "Раздел " + Config.dataMount)
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: "data " + (Disks.dataFs.mounted ? Disks.fmt(Disks.dataFs.avail) : "—")
            color: root.tint(Disks.dataFs)
        }
    }
}
