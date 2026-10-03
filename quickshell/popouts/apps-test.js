// Автотест логики двухпанельного меню приложений (AppsPopout):
// проверка категорий, сопоставления, подсчёта количества и фильтрации.
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const searchCtx = {};
vm.runInNewContext(
    fs.readFileSync(path.join(__dirname, "../launcher/search.js"), "utf8").replace(/^\.pragma.*$/m, ""),
    searchCtx
);

const logicCtx = {};
vm.runInNewContext(
    fs.readFileSync(path.join(__dirname, "apps-logic.js"), "utf8").replace(/^\.pragma.*$/m, ""),
    logicCtx
);

// 1. Проверка структуры категорий
assert.ok(Array.isArray(logicCtx.CATEGORIES), "CATEGORIES должен быть массивом");
assert.strictEqual(logicCtx.CATEGORIES.length, 11, "Должно быть ровно 11 категорий");
assert.strictEqual(logicCtx.CATEGORIES[0].id, "favorites", "Первая категория — favorites");
assert.strictEqual(logicCtx.CATEGORIES[1].id, "all", "Вторая категория — all");

for (const cat of logicCtx.CATEGORIES) {
    assert.ok(cat.id, "Категория должна иметь id");
    assert.ok(cat.label, "Категория должна иметь label");
    assert.ok(cat.icon, "Категория должна иметь icon");
}

// 2. Тестовый набор приложений
const sampleApps = [
    { id: "virt-manager", name: "Virt-Manager", categories: ["System"] },
    { id: "zed", name: "Zed", categories: ["Development", "IDE", "TextEditor"] },
    { id: "firefox", name: "Firefox", categories: ["Network", "WebBrowser"] },
    { id: "thunar", name: "Thunar", categories: ["System", "FileManager", "Utility"] },
    { id: "obsidian", name: "Obsidian", categories: ["Office"] },
    { id: "mpv", name: "mpv", categories: ["AudioVideo", "Player"] },
    { id: "gimp", name: "GIMP", categories: ["Graphics", "RasterGraphics"] },
    { id: "steam", name: "Steam", categories: ["Game", "Network"] },
    { id: "calc", name: "Calculator", categories: ["Utility", "Calculator"] },
    { id: "settings-app", name: "Settings", categories: ["Settings", "DesktopSettings"] }
];

const mockHistory = {
    "zed": { count: 12, last: Date.now() - 1000 },
    "firefox": { count: 25, last: Date.now() - 500 },
    "virt-manager": { count: 3, last: Date.now() - 20000 }
};

// 3. Проверка matchesCategory
assert.strictEqual(logicCtx.matchesCategory(sampleApps[0], "System", mockHistory), true);
assert.strictEqual(logicCtx.matchesCategory(sampleApps[0], "Office", mockHistory), false);
assert.strictEqual(logicCtx.matchesCategory(sampleApps[0], "all", mockHistory), true);
assert.strictEqual(logicCtx.matchesCategory(sampleApps[0], "favorites", mockHistory), true);
assert.strictEqual(logicCtx.matchesCategory({ id: "zed.desktop", categories: ["Development"] }, "favorites", mockHistory), true, "zed.desktop должен сопоставляться с zed из истории");
assert.strictEqual(logicCtx.matchesCategory(sampleApps[4], "favorites", mockHistory), false); // obsidian нет в истории
assert.strictEqual(logicCtx.matchesCategory(sampleApps[1], "Development", mockHistory), true); // zed
assert.strictEqual(logicCtx.matchesCategory(sampleApps[2], "Network", mockHistory), true); // firefox
assert.strictEqual(logicCtx.matchesCategory(sampleApps[5], "AudioVideo", mockHistory), true); // mpv
assert.strictEqual(logicCtx.matchesCategory(sampleApps[6], "Graphics", mockHistory), true); // gimp
assert.strictEqual(logicCtx.matchesCategory(sampleApps[7], "Game", mockHistory), true); // steam
assert.strictEqual(logicCtx.matchesCategory(sampleApps[8], "Utility", mockHistory), true); // calc
assert.strictEqual(logicCtx.matchesCategory(sampleApps[9], "Settings", mockHistory), true); // settings-app

// 4. Проверка computeCategoryCounts
const counts = logicCtx.computeCategoryCounts(sampleApps, mockHistory);
assert.strictEqual(counts.favorites, 3, "В favorites должно быть 3 элемента из mockHistory");
assert.strictEqual(counts.all, 10, "В all должно быть 10 элементов");
assert.strictEqual(counts.Development, 1, "Development: zed");
assert.strictEqual(counts.Office, 1, "Office: obsidian");
assert.strictEqual(counts.Network, 2, "Network: firefox, steam");
assert.strictEqual(counts.System, 2, "System: virt-manager, thunar");
assert.strictEqual(counts.Utility, 3, "Utility: thunar, calc, zed");

// 5. Проверка filterApps без поискового запроса
const favList = logicCtx.filterApps(sampleApps, "", "favorites", mockHistory, searchCtx, Date.now(), 50);
assert.strictEqual(favList.length, 3);
// В истории у firefox 25 запусков, у zed 12 -> firefox первый
assert.strictEqual(favList[0].id, "firefox");
assert.strictEqual(favList[1].id, "zed");
assert.strictEqual(favList[2].id, "virt-manager");

// 6. Проверка filterApps по алфавиту в категории all
const allList = logicCtx.filterApps(sampleApps, "", "all", mockHistory, searchCtx, Date.now(), 50);
assert.strictEqual(allList.length, 10);
assert.strictEqual(allList[0].name, "Calculator"); // По алфавиту первый 'Calculator'
assert.strictEqual(allList[allList.length - 1].name, "Zed"); // По алфавиту последний 'Zed'

// 7. Проверка глобального поиска
for (const it of sampleApps) it.f = searchCtx.prepare(it);
const searchRes = logicCtx.filterApps(sampleApps, "zed", "Office", mockHistory, searchCtx, Date.now(), 50);
assert.ok(searchRes.length > 0, "Поиск должен находить zed даже если выбрана категория Office");
assert.strictEqual(searchRes[0].id, "zed");

console.log("OK: Все тесты apps-logic.js успешно пройдены!");
