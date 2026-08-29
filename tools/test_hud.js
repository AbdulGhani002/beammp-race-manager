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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
