// Проверка ранжирования на реальных .desktop: node launcher/search-test.js [запрос ...]
// Локализованное имя берётся из Name[ru] (как отдаёт Quickshell в ru_RU), английское — из Name=.
const fs = require("fs"), path = require("path"), vm = require("vm");
const ctx = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, "search.js"), "utf8").replace(/^\.pragma.*$/m, ""), ctx);

const dirs = [process.env.HOME + "/.local/share/applications", "/usr/share/applications"];
const seen = new Set(), items = [];
for (const d of dirs) {
    if (!fs.existsSync(d)) continue;
    for (const fn of fs.readdirSync(d)) {
        if (!fn.endsWith(".desktop") || seen.has(fn)) continue;
        seen.add(fn);
        const g = {};
        let inMain = false;
        for (const line of fs.readFileSync(path.join(d, fn), "utf8").split("\n")) {
            if (line.startsWith("[")) { inMain = line.trim() === "[Desktop Entry]"; continue; }
            const m = inMain && line.match(/^([A-Za-z]+(?:\[[^\]]+\])?)=(.*)$/);
            if (m) g[m[1]] = m[2];
        }
        if (g.NoDisplay === "true" || g.Hidden === "true" || g.Type !== "Application") continue;
        const exec = (g.Exec || "").split(/\s+/)[0].split("/").pop();
        items.push({
            id: fn.replace(/\.desktop$/, ""),
            name: g["Name[ru]"] || g.Name || "", enName: g.Name || "",
            genericName: g["GenericName[ru]"] || g.GenericName || "",
            comment: g["Comment[ru]"] || g.Comment || "",
            keywords: (g["Keywords[ru]"] || "").split(";").concat((g.Keywords || "").split(";")).filter(Boolean),
            exec,
        });
    }
}
for (const it of items) it.f = ctx.prepare(it);
console.log("приложений:", items.length);
const queries = process.argv.length > 2 ? process.argv.slice(2)
    : ["virt-manager", "менеджер вирт", "firefox", "thunar", "zed", "obsidian", "kitty", "вирт", "brw", "термин"];
for (const q of queries) {
    const r = ctx.rank(items, q, {}, Date.now(), 4);
    console.log(`\n«${q}» ->`, r.map(x => `${x.name} [${x.id}]`).join(" | ") || "(ничего)");
}
