// The Stella's screen, run outside the game: the controller lifted out of
// his app.js and fed the events the unit's lua sends, to see what the
// screen shows for a gate, a pass, the red button, and the three-button
// power off he built and wants kept.
//
//   node tools/test_stella_ui_flow.js
const fs = require("fs");
const src = fs.readFileSync("client/ui/modules/apps/BajaStella/app.js", "utf8");

let pass = 0, fail = 0;
function ok(cond, what) { if (cond) pass++; else { fail++; console.log("  FAIL  " + what); } }
function eq(got, want, what) { ok(got === want, what + " (got " + got + ", wanted " + want + ")"); }
function section(t) { console.log("\n== " + t); }

// the controller function, as the directive registers it
const start = src.indexOf("controller: ['$scope', function ($scope) {");
const end = src.lastIndexOf("    }]\n  };\n});");
if (start < 0 || end < 0) { console.error("could not find the controller"); process.exit(1); }
const body = src.slice(start + "controller: ['$scope', ".length, end + "    }".length);

// the page, faked: enough of a browser for the controller to run
const lua = [];
const store = {};
const timers = [];
let now = 0;
const fakeWindow = {
  innerWidth: 1920, innerHeight: 1080,
  addEventListener() {}, removeEventListener() {},
  getComputedStyle() { return { position: "static" }; },
};
const sandbox = {
  console,
  window: fakeWindow,
  document: { getElementById() { return null; }, querySelector() { return null; }, body: {},
              addEventListener() {}, removeEventListener() {} },
  localStorage: { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; } },
  bngApi: { engineLua: cmd => lua.push(cmd) },
  Audio: function () { this.volume = 1; this.play = () => {}; this.pause = () => {}; this.currentTime = 0; },
  setTimeout: (fn, ms) => { timers.push({ at: now + (ms || 0), fn }); return timers.length; },
  clearTimeout: id => { if (timers[id - 1]) timers[id - 1].fn = null; },
  setInterval: () => 0, clearInterval: () => {},
  Date: { now: () => now },
  Math, String, Number, parseInt, parseFloat, isNaN, JSON, Object, Array,
};
sandbox.globalThis = sandbox;
function runTimers() {
  timers.slice().forEach(t => { if (t.fn && t.at <= now) { const f = t.fn; t.fn = null; f(); } });
}

const handlers = {};
const $scope = {
  $on(name, fn) { (handlers[name] = handlers[name] || []).push(fn); },
  $applyAsync(fn) { if (fn) fn(); },
  $apply(fn) { if (fn) fn(); },
  $watch() {},
  $emit() {},
};
function fire(name, data) { (handlers[name] || []).forEach(fn => fn({}, data)); }

const make = new Function(...Object.keys(sandbox), "return " + body)(...Object.values(sandbox));
make($scope);

// what the lua sends on every tick, with the light as it stands
function update(over) {
  fire("RmStella_Update", Object.assign({ heading: 90, speed: 40, distToVCPm: 500, distToVCPkm: 0.5, vcpName: "VCP2",
    vcpIndex: 2, validatedVCPs: 1, totalVCPs: 4, totalDistKm: 1, raceActive: true, raceStarted: true, bearingToVCP: 90,
    isApproaching: false, trackName: "Test", isStopped: false, breakdownActive: false, hazardAhead: false,
    blueFlagState: "none", blueFlagPlayer: "", ledColor: "off", ledFlash: false, ledPattern: "none",
    speedZoneActive: false, speedZoneWarning: false, speedZoneName: "", speedZoneLimit: 0, speedExceeding: false }, over || {}));
}
function led(color, flash, pattern) { fire("RmStella_LED", { color, flash, pattern }); }

section("a gate: the light goes green and back off as the lua says");
update();
eq($scope.ledCls, "", "off to begin with");
led("green", false, "all");
ok(/l-green/.test($scope.ledCls), "green on the crossing");
update({ ledColor: "green", ledPattern: "all" });
ok(/l-green/.test($scope.ledCls), "still green while the lua says so");
led("off", false, "none");
update();
eq($scope.ledCls, "", "and off when it says off");

section("push to pass: the overlay follows the state, and the light is the lua's");
fire("RmStella_BlueFlag", { state: "requested", playerName: "" });
eq($scope.flagState, "requested", "asking");
fire("RmStella_BlueFlag", { state: "delivered", playerName: "Bravo" });
eq($scope.flagState, "delivered", "delivered");
eq($scope.flagPlayer, "Bravo", "to Bravo");
led("green", true, "lines");
ok(/l-green/.test($scope.ledCls) && /l-flash/.test($scope.ledCls), "flashing green lines");
fire("RmStella_BlueFlag", { state: "go", playerName: "Bravo" });
eq($scope.flagState, "go", "go");
led("green", true, "all");
ok(/l-green/.test($scope.ledCls), "green");
fire("RmStella_BlueFlag", { state: "none", playerName: "" });
led("off", false, "none");
eq($scope.flagState, "none", "over");
eq($scope.ledCls, "", "light out");
ok(/flagState===\\'go\\'/.test(src) || /flagState==='go'/.test(src), "the overlay knows the go state");
ok(/stella\.flag\.go/.test(src), "and has words for it");

section("the car ahead: OVERTAKE comes up with the name and the beep, and the flag button answers it");
fire("RmStella_BlueFlag", { state: "incoming", playerName: "Charlie" });
eq($scope.flagState, "incoming", "incoming");
eq($scope.flagPlayer, "Charlie", "from Charlie");
lua.length = 0;
$scope.pressFlag();
ok(lua.some(c => /acknowledgeBlueFlag/.test(c)), "the flag button lets them by when somebody is asking");
lua.length = 0;
fire("RmStella_BlueFlag", { state: "none", playerName: "" });
$scope.pressFlag();
ok(lua.some(c => /requestBlueFlag/.test(c)), "and asks when nobody is");

section("the red button is a press, and the press is the lua's toggle");
const stops = () => lua.filter(c => /requestMechanicalBreakdown/.test(c)).length;
lua.length = 0;
$scope.pressSOSStart({ stopPropagation() {} });
eq(stops(), 1, "pressed, the car is stopped");
$scope.pressSOSCancel({ stopPropagation() {} });
now += 3100; runTimers();
eq(stops(), 1, "letting go changes nothing");
$scope.pressSOSStart({ stopPropagation() {} });
eq(stops(), 2, "pressed again, moving again");

section("his power off: all three buttons within three seconds, and any button brings it back");
eq($scope.powered, true, "on to begin with");
now += 10000;
$scope.pressFlag();
now += 500;
$scope.pressOK();
now += 500;
$scope.pressSOSStart({ stopPropagation() {} });
eq($scope.powered, false, "off");
eq(store["rm.stella.powered"], "0", "and remembered off");
lua.length = 0;
now += 5000; runTimers();
eq(stops(), 0, "the third press did not also stop the car");
$scope.pressOK();
eq($scope.powered, true, "one press and it is back on");
eq(store["rm.stella.powered"], "1", "remembered on");
eq(lua.filter(c => /acknowledgeBlueFlag/.test(c)).length, 0, "and that press was swallowed");
now += 10000;
$scope.pressFlag();
now += 4000;
$scope.pressOK();
now += 500;
$scope.pressSOSStart({ stopPropagation() {} });
eq($scope.powered, true, "three presses spread over more than three seconds do not power it off");

section("a power key from the lua side");
fire("RaceManagerStellaKey", { action: "toggle" });
eq($scope.powered, false, "toggled off");
fire("RaceManagerStellaKey", { action: "toggle" });
eq($scope.powered, true, "and on");
fire("RaceManagerStellaKey", { action: "off" });
eq($scope.powered, false, "off");
fire("RaceManagerStellaKey", { action: "on" });
eq($scope.powered, true, "on");

section("the speed on the idle screen is mph, like the tachometer");
fire("streamsUpdate", { electrics: { airspeed: 20 } });
eq($scope.spd, "45", "twenty metres a second is forty five");
ok(/stella\.unit\.mph/.test(src), "and the unit says mph");

console.log("");
console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
