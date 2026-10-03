// Логика фильтрации, категоризации и подсчёта приложений для меню AppsPopout.
// Чистый JS без привязки к интерфейсу Quickshell, тестируется через node (apps-test.js).
.pragma library

var CATEGORIES = [
    { id: "favorites", label: "Часто используемые", icon: "starred", match: null },
    { id: "all", label: "Все приложения", icon: "applications-all", match: null },
    { id: "Development", label: "Разработка", icon: "applications-development", match: ["Development", "IDE", "Building", "Debugger"] },
    { id: "Game", label: "Игры", icon: "applications-games", match: ["Game"] },
    { id: "Graphics", label: "Графика", icon: "applications-graphics", match: ["Graphics", "RasterGraphics", "VectorGraphics", "Photography", "3DGraphics", "Viewer"] },
    { id: "AudioVideo", label: "Мультимедиа", icon: "applications-multimedia", match: ["AudioVideo", "Audio", "Video", "Player", "Recorder", "Music"] },
    { id: "Network", label: "Интернет", icon: "applications-internet", match: ["Network", "WebBrowser", "Email", "InstantMessaging"] },
    { id: "Office", label: "Офис", icon: "applications-office", match: ["Office", "WordProcessor", "Spreadsheet", "Presentation", "Publishing"] },
    { id: "Settings", label: "Настройки", icon: "preferences-system", match: ["Settings", "DesktopSettings", "HardwareSettings"] },
    { id: "System", label: "Система", icon: "applications-system", match: ["System", "Monitor", "Security", "PackageManager", "TerminalEmulator", "FileManager"] },
    { id: "Utility", label: "Утилиты", icon: "applications-utilities", match: ["Utility", "Accessories", "Calculator", "Clock", "TextEditor", "FileTools", "Archiving", "Compression"] }
];

function getCategory(catId) {
    for (var i = 0; i < CATEGORIES.length; i++) {
        if (CATEGORIES[i].id === catId)
            return CATEGORIES[i];
    }
    return CATEGORIES[0];
}

function matchesCategory(it, catId, history) {
    if (!catId || catId === "all")
        return true;
    if (catId === "favorites") {
        var hist = history || {};
        var id1 = it.id || "";
        var id2 = id1.replace(/\.desktop$/, "");
        var h = hist[id1] || hist[id2];
        return Boolean(h && (h.count || 0) > 0);
    }
    var cat = getCategory(catId);
    if (!cat || !cat.id)
        return false;
    var appCats = (it.entry && it.entry.categories) || it.categories || [];
    if (cat.match && Array.isArray(cat.match)) {
        for (var i = 0; i < cat.match.length; i++) {
            if (appCats.indexOf(cat.match[i]) >= 0)
                return true;
        }
        return false;
    }
    return appCats.indexOf(catId) >= 0;
}

function computeCategoryCounts(items, history) {
    var counts = {};
    for (var c = 0; c < CATEGORIES.length; c++) {
        var cat = CATEGORIES[c];
        var n = 0;
        for (var i = 0; i < items.length; i++) {
            if (matchesCategory(items[i], cat.id, history))
                n++;
        }
        counts[cat.id] = n;
    }
    return counts;
}

function filterApps(items, query, catId, history, searchModule, now, limit) {
    var maxCount = limit || 80;
    var q = (query || "").trim();
    if (q.length > 0) {
        if (searchModule && typeof searchModule.rank === "function")
            return searchModule.rank(items, q, history, now || Date.now(), maxCount);
        return [];
    }

    var selectedCat = catId || "favorites";
    var list = [];
    for (var i = 0; i < items.length; i++) {
        if (matchesCategory(items[i], selectedCat, history))
            list.push(items[i]);
    }

    if (selectedCat === "favorites") {
        if (searchModule && typeof searchModule.rank === "function")
            return searchModule.rank(list, "", history, now || Date.now(), maxCount);
        return list.slice(0, maxCount);
    }

    list.sort(function(a, b) {
        var na = (a.name || "").toString();
        var nb = (b.name || "").toString();
        return na.localeCompare(nb);
    });

    return list.slice(0, maxCount);
}
