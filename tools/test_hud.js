// The numbers the HUD puts on screen, pulled straight out of app.js and run
// against the values that broke them. A race put 4:60.0 on the clock and
// emptied the lap bar the moment every gate was done.
//
//   node tools/test_hud.js

const fs = require("fs");

const src = fs.readFileSync("client/ui/modules/apps/RaceManager/app.js", "utf8");
function lift(pattern, name) {
  const m = src.match(pattern);
  if (!m) {
    console.error("could not find " + name + " in app.js");
    process.exit(1);
  }
  return m[0];
}

const fmt = new Function(
  lift(/function fmt\(sec, places\) \{[\s\S]*?\n      \}/, "fmt") + "; return fmt;")();

// lapProgress reads the scope, so it gets one
const lapProgress = new Function("race",
  "var $scope = { s: { race: race } };" +
  lift(/\$scope\.lapProgress = function \(\) \{[\s\S]*?\n      \};/, "lapProgress") +
  "return $scope.lapProgress();");

// penaltyWords reads the scope too, and it caches on the breakdown it was
// given, so each call gets a fresh copy of the whole thing
function penaltyWords(race) {
  const build = new Function("race",
    "var $scope = { s: { race: race } };" +
    lift(/var PENALTY_WORD = \{[\s\S]*?\n      \};/, "PENALTY_WORD") +
    lift(/var PENALTY_ORDER = \[[\s\S]*?\];/, "PENALTY_ORDER") +
    "var penFrom = null, penText = '';" +
    lift(/\$scope\.penaltyWords = function \(\) \{[\s\S]*?\n      \};/, "penaltyWords") +
    "return $scope.penaltyWords();");
  return build(race);
}

// The bottom bar sounds, against a fake Audio. Node has none, and the pattern
// is the part that keeps coming back: six bursts for six wheel nuts, a bottle
// for fuel, drill then hammer and ratchet for a repair, nothing for a
// reposition. It also has to keep moving when a clip will not play at all.
function soundRun(which, holdSecs, opts) {
  opts = opts || {};
  const played = [];
  const timers = [];

  function FakeAudio(src) {
    this.src = src;
    this.duration = 0.2;
    this.playbackRate = 1;
    this.onended = null;
    this.currentTime = 0;
    this.pause = function () {};
    const self = this;
    this.play = function () {
      played.push(String(src).split("/").pop());
      if (opts.neverEnds) return { catch: function () { return this; } };
      // ended fires on its own, the way a browser would
      timers.push(setTimeout(function () { if (self.onended) self.onended(); }, 1));
      return { catch: function () { return this; } };
    };
  }

  const sandbox = {
    Audio: FakeAudio,
    Date: Date,
    setTimeout: function (fn, ms) { return setTimeout(fn, Math.min(ms, 2)); },
    isFinite: isFinite,
  };

  const body =
    lift(/var SOUND_URL = [\s\S]*?\n      var soundChain = null;/, "sound header") +
    lift(/function clip\(name\) \{[\s\S]*?\n      \}/, "clip") +
    lift(/function stopSounds\(\) \{[\s\S]*?\n      \}/, "stopSounds") +
    lift(/function runSounds\(steps, endsAt\) \{[\s\S]*?\n      \}/, "runSounds") +
    lift(/function jobSounds\(which\) \{[\s\S]*?\n      \}/, "jobSounds") +
    "; return { run: runSounds, steps: jobSounds };";

  const make = new Function("Audio", "setTimeout", "isFinite", body);
  const api = make(sandbox.Audio, sandbox.setTimeout, sandbox.isFinite);
  const steps = api.steps(which);
  if (steps) api.run(steps, Date.now() + holdSecs * 1000);
  return { played: played, steps: steps, timers: timers };
}

// waits until the pattern stops growing rather than guessing a duration, so a
// slower machine does not read a half finished chain as a short one
function soundPattern(which, holdSecs, opts) {
  return new Promise(function (res) {
    const r = soundRun(which, holdSecs, opts);
    let last = -1, quiet = 0;
    const tick = setInterval(function () {
      if (r.played.length === last) quiet++; else { last = r.played.length; quiet = 0; }
      if (quiet >= 6) {
        clearInterval(tick);
        r.timers.forEach(clearTimeout);
        res(r.played);
      }
    }, 15);
  });
}


let pass = 0, fail = 0;
function eq(got, want, what) {
  if (got === want) { pass++; return; }
  fail++;
  console.log(`  FAIL  ${what} (got ${got}, wanted ${want})`);
}

console.log("\n== the minute boundary");
// 299.98 is four minutes and 59.98 seconds. Shown to a tenth that is 60.0, and
// the minutes were counted before the rounding, so it read 4:60.0.
eq(fmt(299.98, 1), "5:00.0", "299.98 to a tenth");
eq(fmt(419.97, 1), "7:00.0", "419.97 to a tenth");
eq(fmt(59.98, 1), "1:00.0", "a time that rounds up into a minute gains one");
eq(fmt(119.9999, 3), "2:00.000", "same thing at three decimals");
eq(fmt(299.94, 1), "4:59.9", "just below the boundary still rounds down");

console.log("\n== the padding");
// the decision to pad was made against 9.98 and the number printed was 10.0
eq(fmt(249.98, 1), "4:10.0", "a second that rounds up to ten is not padded");
eq(fmt(249.94, 1), "4:09.9", "one that stays under ten still is");
eq(fmt(245.0, 1), "4:05.0", "an ordinary single digit is padded");

console.log("\n== ordinary times");
eq(fmt(0, 1), "0.0", "zero");
eq(fmt(9.645, 3), "9.645", "a split under a minute");
eq(fmt(171.189, 3), "2:51.189", "a lap time");
eq(fmt(512.306, 3), "8:32.306", "the run that was recorded");
eq(fmt(210, 0), "3:30", "a penalty total, whole seconds");
eq(fmt(30, 0), "30", "one penalty");

console.log("\n== nothing to show");
eq(fmt(null, 1), "—", "no number");
eq(fmt(undefined, 1), "—", "missing");
eq(fmt(NaN, 1), "—", "not a number");
eq(fmt(Infinity, 1), "—", "infinite");
eq(fmt(-5.5, 1), "-5.5", "negative keeps its sign");

console.log("\n== the lap bar");
// nextGate sits one past the last gate for the whole drive back to the line,
// so working the bar back from it read that as no gates done and the bar
// emptied itself right at the end of the lap
eq(lapProgress({ gates: 30, done: 0, next: 1 }), 0, "on the line, nothing done");
eq(lapProgress({ gates: 30, done: 13, next: 14 }), 43, "part way round");
eq(lapProgress({ gates: 30, done: 29, next: 30 }), 97, "one gate left");
eq(lapProgress({ gates: 30, done: 30, next: 1 }), 100, "every gate done, heading for the line");
eq(lapProgress({ gates: 0 }), 0, "no course, no bar");
eq(lapProgress({}), 0, "nothing at all");
eq(lapProgress({ gates: 30, done: 44 }), 100, "never past the end");

console.log("\n== what the clock calls a penalty");
// It used to be handed one count and call every one of them a cut, so a driver
// who cut one corner and then pressed Reposition was told he had cut twice.
eq(penaltyWords({ penalties: 0 }), "", "a clean run says nothing");
eq(penaltyWords({ penalties: 1, penaltyBy: { missed_gate: 1 } }),
   "1 cut", "one cut is one cut");
eq(penaltyWords({ penalties: 2, penaltyBy: { missed_gate: 2 } }),
   "2 cuts", "two of them read as a plural");
eq(penaltyWords({ penalties: 2, penaltyBy: { missed_gate: 1, recovery: 1 } }),
   "1 cut, 1 reposition", "a reposition is not a second cut, which is the bug this had");
eq(penaltyWords({ penalties: 3, penaltyBy: { recovery: 1, repair: 1, flatTire: 1 } }),
   "1 reposition, 1 tire change, 1 repair", "each kind gets its own name");
eq(penaltyWords({ penalties: 2, penaltyBy: { speeding: 2 } }),
   "2 speeding", "speeding reads the same either way");
// the server can start charging for something this build has no word for
eq(penaltyWords({ penalties: 2, penaltyBy: { missed_gate: 1, jumpstart: 1 } }),
   "1 cut, 1 penalty", "anything unknown is still counted, just not named");
eq(penaltyWords({ penalties: 2 }),
   "2 penalties", "and an older server that sends no breakdown still says how many");

(async function () {
  console.log("\n== the sounds the bottom bar makes");

  const spare = await soundPattern("spare", 30);
  eq(spare.length, 6, "a spare tire is six bursts, one per wheel nut");
  eq(spare.every(function (n) { return n === "drill.mp3"; }), true, "all of them the drill");

  const fuel = await soundPattern("fuel", 20);
  eq(fuel.join(","), "fuel.mp3", "fuel is the bottle, once");

  const repair = await soundPattern("repair", 60);
  eq(repair[0], "drill.mp3", "a repair starts on the drill");
  eq(repair[1], "hammer.mp3", "then the hammer");
  eq(repair[2], "ratchet.mp3", "then the ratchet");
  eq(repair.length, 17, "drill once and eight of each after it");

  const rep = await soundPattern("reposition", 5);
  eq(rep.length, 0, "reposition stays quiet, which is what he asked for");

  const rerack = await soundPattern("rerack", 30);
  eq(rerack.length, 0, "and so does re-racking");

  // the hold is what cuts the pattern short
  const none = await soundPattern("spare", 0);
  eq(none.length, 0, "a hold that is already over plays nothing at all");

  // Waiting only on the clip ending left the whole pattern stalled after one
  // note whenever a clip could not be played, and one drill on its own is
  // exactly what an unattached sound sounds like.
  const stuck = await soundPattern("spare", 30, { neverEnds: true });
  eq(stuck.length, 6, "a clip that never ends does not stall the rest");

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})();
