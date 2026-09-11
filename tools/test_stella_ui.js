// The dots on his Stella, lifted out of his app.js: the limit is spelt in two
// digits, and the screen overlay comes up for a zone ahead as well as one you
// are in.
//
//   node tools/test_stella_ui.js
const fs = require("fs");
const src = fs.readFileSync("client/ui/modules/apps/BajaStella/app.js", "utf8");

let pass = 0, fail = 0;
function ok(cond, what) {
  if (cond) pass++;
  else { fail++; console.log("  FAIL  " + what); }
}
function eq(got, want, what) { ok(got === want, what + " (got " + got + ", wanted " + want + ")"); }
function section(t) { console.log("\n== " + t); }

function lift(pattern, name) {
  const m = src.match(pattern);
  if (!m) { console.error("could not find " + name); process.exit(1); }
  return m[0];
}

const mask = new Function(
  lift(/var DIGITS = \{[\s\S]*?\n      \};/, "DIGITS") +
  lift(/function digitRows\(text\) \{[\s\S]*?\n      \}/, "digitRows") +
  lift(/function ledMask\(pattern\) \{[\s\S]*?\n      \}/, "ledMask") +
  "return ledMask;")();

function rows(m) {
  const out = [];
  for (let r = 0; r < 5; r++) out.push(m.slice(r * 10, r * 10 + 10).map(b => b ? "1" : "0").join(""));
  return out;
}

section("thirty seven is spelt across the ten by five dots");
const r37 = rows(mask("limit:37"));
eq(r37[0], "1111001111", "the tops of a 3 and a 7, with a gap between");
eq(r37[2], "0111000010", "the middle of a 3 and the slant of a 7");
eq(r37[4], "1111000100", "the foot of a 3 and the foot of a 7");
eq(mask("limit:37").length, 50, "fifty dots");

section("one digit sits in the middle");
const r5 = rows(mask("limit:5"));
eq(r5[0], "0001111000", "a five, centred");
eq(r5[1], "0001000000", "its upper left stroke");

section("what the dots cannot spell lights them all, as before");
eq(rows(mask("limit:120"))[0], "1111111111", "three digits");
eq(rows(mask("limit:x"))[0], "1111111111", "no number");
eq(rows(mask("triangle"))[0], "0000010000", "the old warning triangle is untouched");
eq(rows(mask("none"))[0], "0000000000", "and off is off");

section("the screen overlay comes up for a zone ahead, not only one you are in");
ok(/lcd-sz-overlay" ng-show="szActive \|\| szWarning"/.test(src),
   "the overlay shows on the warning");
ok(/SPEED ZONE AHEAD/.test(src), "and says the zone is ahead");
ok(/sz-yellow[^']*\{color:#8a6300;animation:szPulse/.test(src),
   "ahead is yellow and flashing");
ok(/\.lcd-sz-limit\.sz-in[^{]*\{color:#8b1a12;animation:none;\}/.test(src),
   "inside is red and steady");
ok(/\.lcd-sz-limit\.sz-red,\.lcd-sz-unit\.sz-red\{animation:szPulse/.test(src),
   "over the limit flashes red");
ok(/d\.speedZoneLimitMph \|\| Math\.round/.test(src),
   "the number shown is the mph he set, not a rounding of km/h");

console.log("");
if (fail > 0) { console.log(pass + " passed, " + fail + " failed"); process.exit(1); }
console.log(pass + " passed, 0 failed");
