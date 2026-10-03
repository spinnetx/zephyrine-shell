// Проверка settings/logic.js: node quickshell/settings/logic-test.js
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert");
const ctx = {};
const eq = (a, b) => assert.strictEqual(JSON.stringify(a), JSON.stringify(b));

const code = fs.readFileSync(path.join(__dirname, "logic.js"), "utf8").replace(/^\.pragma.*$/m, "");
vm.runInNewContext(code, ctx);

// Test parseMode
eq(ctx.parseMode("1920x1080@120.00Hz"), { width: 1920, height: 1080, refresh: 120 });
eq(ctx.parseMode("1920x1080@60"), { width: 1920, height: 1080, refresh: 60 });
eq(ctx.parseMode(""), { width: 1920, height: 1080, refresh: 60 });

// Test calcLogicalSize
eq(ctx.calcLogicalSize(1920, 1080, 1.0, 0), { width: 1920, height: 1080 });
eq(ctx.calcLogicalSize(1920, 1080, 1.25, 0), { width: 1536, height: 864 });
// Rotated 90 deg (transform 1)
eq(ctx.calcLogicalSize(1920, 1080, 1.0, 1), { width: 1080, height: 1920 });

// Test calcRelativePosition
const map = {
    "eDP-1": { width: 1920, height: 1080, scale: 1.0, transform: 0, x: 0, y: 0 }
};
const cur = { width: 1920, height: 1200, scale: 1.0, transform: 0 };

eq(ctx.calcRelativePosition("right-of", "eDP-1", cur, map), { x: 1920, y: 0, str: "1920x0" });
eq(ctx.calcRelativePosition("left-of", "eDP-1", cur, map), { x: -1920, y: 0, str: "-1920x0" });
eq(ctx.calcRelativePosition("above", "eDP-1", cur, map), { x: 0, y: -1200, str: "0x-1200" });
eq(ctx.calcRelativePosition("below", "eDP-1", cur, map), { x: 0, y: 1080, str: "0x1080" });
eq(ctx.calcRelativePosition("origin", "eDP-1", cur, map), { x: 0, y: 0, str: "0x0" });

// Test formatIdleSec
assert.strictEqual(ctx.formatIdleSec(null), "никогда");
assert.strictEqual(ctx.formatIdleSec(0), "никогда");
assert.strictEqual(ctx.formatIdleSec(60), "1 мин");
assert.strictEqual(ctx.formatIdleSec(150), "2.5 мин");
assert.strictEqual(ctx.formatIdleSec(330), "5.5 мин");
assert.strictEqual(ctx.formatIdleSec(3600), "1 час");

// Test formatBatteryTime
assert.strictEqual(ctx.formatBatteryTime(0), "");
assert.strictEqual(ctx.formatBatteryTime(180), "3 мин");
assert.strictEqual(ctx.formatBatteryTime(3700), "1 ч 2 мин");

console.log("logic-test.js: all tests passed!");
