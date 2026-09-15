// His Stella screen, run outside the game: the controller lifted out of
// his app.js and fed the snapshots it polls from the unit, to see what it
// shows for the light, a zone, a pass, the buttons, the keys, and the three
// button power off he built and wants kept.
//
//   node tools/test_stella_ui_flow.js
const fs = require("fs");
const src = fs.readFileSync("client/ui/modules/apps/RaceManagerStella/app.js", "utf8");

let pass = 0, fail = 0;
function ok(cond, what) { if (cond) pass++; else { fail++; console.log("  FAIL  " + what); } }
function eq(got, want, what) { ok(got === want, what + " (got " + got + ", wanted " + want + ")"); }
function section(t) { console.log("\n== " + t); }

// the controller function, as the directive registers it
const start = src.indexOf("controller: ['$scope', function ($scope) {");
const end = src.lastIndexOf("    }]\n  };\n});");
if (start < 0 || end < 0) { console.error("could not find the controller"); process.exit(1); }
const body = src.slice(start + "controller: ['$scope', ".length, end + "    }".length);

// the page, faked: enough of a browser for the controller to run. The poll
// is the part that matters: the interval is caught and run by hand, and the
// answer to the unit's uiPoll is whatever snapshot the test hands over.
const lua = [];
const store = {};
const timers = [];
const intervals = [];
const polls = [];
const plays = [];
let now = 100000;
const fakeWindow = {
  innerWidth: 1920, innerHeight: 1080,
  addEventListener() {}, removeEventListener() {},
  getComputedStyle() { return { position: "static" }; },
};
function FakeAudio() {
  this.volume = 1; this.currentTime = 0; this.loop = false;
  this.play = () => { plays.push(this.src); return { then: () => ({ catch: () => {} }), catch: () => {} }; };
  this.pause = () => {};
}
const sandbox = {
  console,
  window: fakeWindow,
  navigator: {},
  document: { getElementById() { return null; }, querySelector() { return null; }, body: {},
              addEventListener() {}, removeEventListener() {} },
  localStorage: { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; } },
  bngApi: { engineLua: (cmd, cb) => { lua.push(cmd); if (cb && /uiPoll/.test(cmd)) polls.push(cb); } },
  Audio: function (srcUrl) { const a = new FakeAudio(); a.src = srcUrl; return a; },
  setTimeout: (fn, ms) => { timers.push({ at: now + (ms || 0), fn }); return timers.length; },
  clearTimeout: id => { if (timers[id - 1]) timers[id - 1].fn = null; },
  setInterval: (fn) => { intervals.push(fn); return intervals.length; },
  clearInterval: () => {},
  Date: { now: () => now },
  JSON, Math, String, Number, parseInt, parseFloat, isNaN, Object, Array,
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

// one snapshot from the unit, the way its getSnapshot() shapes it
function snapshot(over) {
  return Object.assign({ heading: 90, speed: 40, distToVCPm: 500, distToVCPkm: 0.5, vcpName: "VCP2", vcpIndex: 2,
    validatedVCPs: 1, totalVCPs: 4, totalDistKm: 1, raceActive: true, raceStarted: true, isApproaching: false,
    isStopped: false, breakdownActive: false, hazardAhead: false, blueFlagState: "none", blueFlagPlayer: "",
    ledColor: "off", ledFlash: false, ledPattern: "none", speedZoneActive: false, speedZoneWarning: false,
    speedZoneName: "", speedZoneLimit: 0, speedZoneLimitMph: 0, speedExceeding: false, greenLeft: 0,
    testStep: 0, keys: [], sounds: [] }, over || {});
}
// one tick of the poll: the interval fires, asks the unit, and gets this back
function poll(over) {
  polls.length = 0;
  intervals.forEach(fn => fn());
  ok(polls.length === 1, "the screen asked the unit once");
  const cb = polls.pop();
  cb(JSON.stringify(snapshot(over)));
}
const dotsOn = () => ($scope._ledMask || []).filter(Boolean).length;

section("the screen polls the unit, and the light is what the unit says");
ok(intervals.length >= 1, "a poll is running");
poll();
eq($scope.ledCls, "", "off to begin with");
eq($scope.hdg, "090", "the heading");
poll({ ledColor: "green", ledPattern: "all" });
ok(/l-green/.test($scope.ledCls), "green on a crossing");
eq(dotsOn(), 50, "all the dots");
poll({ ledColor: "yellow", ledFlash: true, ledPattern: "limit:37", speedZoneWarning: true, speedZoneLimitMph: 37 });
ok(/l-yellow/.test($scope.ledCls) && /l-flash/.test($scope.ledCls), "flashing yellow for a zone ahead");
ok(dotsOn() >= 18 && dotsOn() <= 26, "spelling thirty seven, two digits of dots (" + dotsOn() + ")");
eq($scope.szWarning, true, "and the screen shows the zone ahead");
eq($scope.szLimitMph, 37, "with the limit");
poll({ ledColor: "red", ledPattern: "limit:37", speedZoneActive: true, speedZoneLimitMph: 37 });
ok(/l-red/.test($scope.ledCls) && !/l-flash/.test($scope.ledCls), "steady red inside");
eq($scope.szActive, true, "the zone is on");
poll({ ledColor: "red", ledFlash: true, ledPattern: "limit:37", speedZoneActive: true, speedExceeding: true, speedZoneLimitMph: 37 });
ok(/l-flash/.test($scope.ledCls), "flashing red over the limit");
eq($scope.szExceeding, true, "and the screen says so");
poll();
eq($scope.ledCls, "", "off when the unit says off");
eq($scope.szActive, false, "no zone");

section("the sounds the unit queues are played, once each");
// the first sound of all also unlocks the audio, with a quiet play of its own
poll({ sounds: ["advance"] });
plays.length = 0;
poll({ sounds: ["advance"] });
eq(plays.length, 1, "the warning sound");
ok(/speed_zone_entry/.test(plays[0]), "the entry tone");
plays.length = 0;
poll({ sounds: ["vcp"] });
eq(plays.length, 1, "the gate sound");
ok(/vcp_sound/.test(plays[0]), "the vcp tone");
plays.length = 0;
poll({});
eq(plays.length, 0, "and nothing when there is nothing queued");

section("push to pass: the overlay follows the state the unit reports");
poll({ blueFlagState: "delivered", blueFlagPlayer: "Bravo", ledColor: "green", ledFlash: true, ledPattern: "lines" });
eq($scope.flagState, "delivered", "delivered");
eq($scope.flagPlayer, "Bravo", "to Bravo");
poll({ blueFlagState: "go", blueFlagPlayer: "Bravo", ledColor: "green", ledFlash: true, ledPattern: "all" });
eq($scope.flagState, "go", "go");
poll();
eq($scope.flagState, "none", "over");
ok(/flagState===\\'go\\'/.test(src) || /flagState==='go'/.test(src), "the overlay knows the go state");

section("the buttons press the unit");
lua.length = 0;
poll({ blueFlagState: "incoming", blueFlagPlayer: "Charlie" });
$scope.pressFlag();
ok(lua.some(c => /acknowledgeBlueFlag/.test(c)), "the flag button lets them by when somebody is asking");
lua.length = 0;
poll();
$scope.pressFlag();
ok(lua.some(c => /requestBlueFlag/.test(c)), "and asks when nobody is");
lua.length = 0;
now += 4000;
$scope.pressOK();
ok(lua.some(c => /acknowledgeBlueFlag/.test(c)), "OK acknowledges");
lua.length = 0;
now += 4000;
$scope.pressSOSStart({ stopPropagation() {} });
ok(lua.some(c => /requestMechanicalBreakdown/.test(c)), "the red button is a press, and the unit toggles");

section("his power off: all three buttons within three seconds, and any button brings it back");
eq($scope.powered, true, "on to begin with");
now += 10000;
$scope.pressFlag();
now += 500;
$scope.pressOK();
now += 500;
$scope.pressSOSStart({ stopPropagation() {} });
eq($scope.powered, false, "off");
eq(store["rm.rmsi.powered"], "0", "and remembered off");
lua.length = 0;
$scope.pressOK();
eq($scope.powered, true, "one press and it is back on");
eq(store["rm.rmsi.powered"], "1", "remembered on");
eq(lua.filter(c => /acknowledgeBlueFlag/.test(c)).length, 0, "and that press was swallowed");
now += 10000;
$scope.pressFlag();
now += 4000;
$scope.pressOK();
now += 500;
$scope.pressSOSStart({ stopPropagation() {} });
eq($scope.powered, true, "three presses spread over more than three seconds do not power it off");

section("a key arrives once, through the poll, and does what the button does");
poll({ keys: ["toggle"] });
eq($scope.powered, false, "the power key: off");
poll({ keys: ["toggle"] });
eq($scope.powered, true, "and on again");
poll({ keys: ["off"] });
eq($scope.powered, false, "off");
poll({ keys: ["on"] });
eq($scope.powered, true, "on");
lua.length = 0;
now += 10000;
poll({ keys: ["flag"] });
eq(lua.filter(c => /requestBlueFlag/.test(c)).length, 1, "the flag key asks once");

section("the test from chat: each step is answered once");
lua.length = 0;
poll({ testStep: 1, ledColor: "yellow", ledFlash: true, ledPattern: "triangle" });
poll({ testStep: 1, ledColor: "yellow", ledFlash: true, ledPattern: "triangle" });
eq(lua.filter(c => /screenSaw/.test(c)).length, 1, "step one, answered once for two polls");
poll({ testStep: 2, ledColor: "blue", ledFlash: true, ledPattern: "lines" });
eq(lua.filter(c => /screenSaw/.test(c)).length, 2, "step two, answered");
poll({ testStep: 0 });
poll({ testStep: 1, ledColor: "yellow", ledFlash: true, ledPattern: "triangle" });
eq(lua.filter(c => /screenSaw/.test(c)).length, 3, "a new run answers step one again");

section("the unit's word by hook takes the same road in as the poll's answer");
lua.length = 0;
plays.length = 0;
fire("RMSI_Update", snapshot({ ledColor: "green", ledPattern: "all", sounds: ["vcp"], testStep: 5 }));
ok(/l-green/.test($scope.ledCls), "the light");
eq(plays.length, 1, "the sound, once");
eq(lua.filter(c => /screenSaw/.test(c)).length, 1, "and the test step answered");
fire("RMSI_Update", snapshot({ keys: ["toggle"] }));
eq($scope.powered, false, "a key by hook does what the button does");
fire("RMSI_Update", snapshot({ keys: ["toggle"] }));
eq($scope.powered, true, "and back");
fire("RMSI_Update", snapshot({ heading: 355, raceActive: true, vcpIndex: 3, vcpName: "VCP3" }));
eq($scope.hdg, "355", "the heading");
eq($scope.wpLabel, "03-VCP3", "and the gate");

section("while the hook flows the poll stands aside, and asks again once it is quiet");
polls.length = 0;
intervals.forEach(fn => fn());
eq(polls.length, 0, "no poll a moment after a hook");
now += 1500;
polls.length = 0;
intervals.forEach(fn => fn());
eq(polls.length, 1, "a second and a half later it asks again");
const late = polls.pop();
fire("RMSI_Update", snapshot({ ledColor: "yellow", ledPattern: "limit:37" }));
late(JSON.stringify(snapshot({ ledColor: "off" })));
ok(/l-yellow/.test($scope.ledCls), "an answer that lands after a fresh hook is not painted over it");
now += 1500;
poll({ ledColor: "red", ledPattern: "limit:37" });
ok(/l-red/.test($scope.ledCls), "and the poll paints again once the hook is quiet");

section("an answer with no light in it is no reading");
fire("RMSI_Update", {});
ok(/l-red/.test($scope.ledCls), "an empty answer leaves the dots as they were");
fire("RMSI_Update", { sounds: ["vcp"] });
ok(/l-red/.test($scope.ledCls), "so does one with only a sound in it");

section("the speed on the idle screen is mph, like the tachometer");
fire("streamsUpdate", { electrics: { airspeed: 20 } });
eq($scope.spd, "45", "twenty metres a second is forty five");
ok(/stella\.unit\.mph/.test(src), "and the unit says mph");

console.log("");
console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
