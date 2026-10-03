.pragma library

// Чистая логика для настроек экранов, звука и питания (DESIGN §6.2)
// Тестируется через node quickshell/settings/logic-test.js

function parseMode(modeStr) {
    if (!modeStr)
        return { width: 1920, height: 1080, refresh: 60 };
    // "1920x1080@120.00Hz" или "1920x1080@60"
    const m = /^(\d+)x(\d+)(?:@([\d\.]+)Hz?)?/.exec(modeStr);
    if (!m)
        return { width: 1920, height: 1080, refresh: 60 };
    return {
        width: parseInt(m[1], 10),
        height: parseInt(m[2], 10),
        refresh: m[3] ? parseFloat(m[3]) : 60
    };
}

function calcLogicalSize(width, height, scale, transform) {
    const s = (typeof scale === "number" && scale > 0) ? scale : 1.0;
    let w = Math.round(width / s);
    let h = Math.round(height / s);
    // transform 1 (90°) или 3 (270°) меняют местами ширину и высоту
    if (transform === 1 || transform === 3 || transform === 5 || transform === 7) {
        const tmp = w;
        w = h;
        h = tmp;
    }
    return { width: w, height: h };
}

function calcRelativePosition(relPos, relTargetName, currentMon, allMonitorsMap) {
    // relPos: "origin" | "right-of" | "left-of" | "above" | "below"
    if (!relPos || relPos === "origin" || !relTargetName || !allMonitorsMap[relTargetName])
        return { x: 0, y: 0, str: "0x0" };

    const target = allMonitorsMap[relTargetName];
    const targetSize = calcLogicalSize(target.width, target.height, target.scale, target.transform);
    const targetX = target.x || 0;
    const targetY = target.y || 0;

    const curSize = calcLogicalSize(currentMon.width, currentMon.height, currentMon.scale, currentMon.transform);

    let x = 0;
    let y = 0;
    switch (relPos) {
    case "right-of":
        x = targetX + targetSize.width;
        y = targetY;
        break;
    case "left-of":
        x = targetX - curSize.width;
        y = targetY;
        break;
    case "above":
        x = targetX;
        y = targetY - curSize.height;
        break;
    case "below":
        x = targetX;
        y = targetY + targetSize.height;
        break;
    default:
        x = 0;
        y = 0;
        break;
    }
    return { x: x, y: y, str: x + "x" + y };
}

function formatIdleSec(sec) {
    if (sec === null || sec === undefined || sec <= 0)
        return "никогда";
    if (sec < 60)
        return sec + " с";
    const min = sec / 60;
    if (min === Math.floor(min)) {
        if (min === 1) return "1 мин";
        if (min >= 2 && min <= 4) return min + " мин";
        if (min === 60) return "1 час";
        return min + " мин";
    }
    return min.toFixed(1) + " мин";
}

function formatBatteryTime(sec) {
    if (!sec || sec <= 0)
        return "";
    const h = Math.floor(sec / 3600);
    const m = Math.round((sec % 3600) / 60);
    if (h > 0)
        return h + " ч " + m + " мин";
    return m + " мин";
}
