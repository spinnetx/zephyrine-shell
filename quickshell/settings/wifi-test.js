// Проверка settings/wifi.js: node settings/wifi-test.js
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert");
const ctx = {};
const eq = (a, b) => assert.strictEqual(JSON.stringify(a), JSON.stringify(b));
vm.runInNewContext(fs.readFileSync(path.join(__dirname, "wifi.js"), "utf8").replace(/^\.pragma.*$/m, ""), ctx);

eq(ctx.splitTerse("a\\:b:c::d"), ["a:b", "c", "", "d"]);
assert.strictEqual(ctx.bandOf(2462), "2.4 ГГц");
assert.strictEqual(ctx.bandOf(5745), "5 ГГц");
assert.strictEqual(ctx.bandOf(6115), "6 ГГц");
assert.strictEqual(ctx.bandOf(0), "");

const dev = ctx.parseDeviceShow(`GENERAL.HWADDR:C4:47:4E:A0:11:08
GENERAL.STATE:100 (connected)
IP4.ADDRESS[1]:172.20.10.2/28
IP4.ADDRESS[2]:10.0.0.5/24
IP4.GATEWAY:172.20.10.1
IP4.DNS[1]:172.20.10.1
IP4.DNS[2]:1.1.1.1
IP6.ADDRESS[1]:fe80::e0f9:67ab:c64c:514a/64
GENERAL.CONNECTION:iPhone (RZ)
`);
assert.strictEqual(dev.mac, "C4:47:4E:A0:11:08");
eq(dev.ip4, ["172.20.10.2/28", "10.0.0.5/24"]);
assert.strictEqual(dev.gateway, "172.20.10.1");
eq(dev.dns, ["172.20.10.1", "1.1.1.1"]);
assert.strictEqual(dev.connection, "iPhone (RZ)");
// отключённое устройство: пустые/«--» значения
const off = ctx.parseDeviceShow("GENERAL.HWADDR:C4:47:4E:A0:11:08\nGENERAL.STATE:30 (disconnected)\nIP4.ADDRESS[1]:\nIP4.GATEWAY:--\n");
eq(off.ip4, []);
assert.strictEqual(off.gateway, "");

const ap = ctx.parseActiveAp(` ::80:5200 MHz:40:1170 Mbit/s:WPA2:DE\\:62\\:79\\:7A\\:96\\:1B
*:iPhone (RZ):75:5745 MHz:149:270 Mbit/s:WPA2 WPA3:7E\\:77\\:81\\:5E\\:AA\\:E7
`);
assert.strictEqual(ap.ssid, "iPhone (RZ)");
assert.strictEqual(ap.signal, 75);
assert.strictEqual(ap.freq, 5745);
assert.strictEqual(ap.band, "5 ГГц");
assert.strictEqual(ap.chan, "149");
assert.strictEqual(ap.rate, "270 Mbit/s");
assert.strictEqual(ap.security, "WPA2 WPA3");
assert.strictEqual(ap.bssid, "7E:77:81:5E:AA:E7");
assert.strictEqual(ctx.parseActiveAp(" :x:1:2412 MHz:1:54 Mbit/s:WPA2:AA\\:BB\n"), null);
assert.strictEqual(ctx.parseActiveAp(""), null);

const saved = ctx.parseSaved(`NETIASPOT-8Jh6:fe236277-2df4-4593-80cd-f3a967f3103c:802-11-wireless:yes:no
iPhone (RZ):2b3f006a-5f59-4c22-a41a-955010052ba4:802-11-wireless:yes:yes
docker0:abb3601d-31f6-4347-9a93-140bfef58c06:bridge:yes:yes
a\\:b:11111111-1111-1111-1111-111111111111:802-11-wireless:no:no
`);
eq(saved.map(s => s.name), ["iPhone (RZ)", "a:b", "NETIASPOT-8Jh6"]);
assert.strictEqual(saved[0].active, true);
assert.strictEqual(saved[1].autoconnect, false);
assert.strictEqual(ctx.stripPrefix("172.20.10.2/28"), "172.20.10.2");
assert.strictEqual(ctx.signalLevel(80), 4);
assert.strictEqual(ctx.signalLevel(10), 1);
console.log("wifi.js: ok");
