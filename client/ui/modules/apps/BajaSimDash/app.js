angular.module("beamng.apps").directive("bajaSimDash", [
  function () {
    return {
      restrict: "EA",
      replace: true,
      template: `
<div class="baja-root">
<style>
@import url("https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@500;600;700&display=swap");
.baja-root{width:100%;height:100%;background:transparent !important;pointer-events:none;font-family:"Chakra Petch","Overpass","Segoe UI",sans-serif;color:#f2f0eb}
.baja-root svg{width:100%;height:100%;display:block;overflow:visible;background:transparent}
.baja-root .hit{pointer-events:auto;cursor:pointer}
.baja-root .tabular{font-variant-numeric:tabular-nums}
@keyframes bajaPark{0%,100%{opacity:1}50%{opacity:.28}}
@keyframes bajaFlash{0%,100%{opacity:1}50%{opacity:.18}}
@keyframes bajaLimit{0%,49%{opacity:1;fill:#c90d18}50%,100%{opacity:.06;fill:#c90d18}}
.baja-root .lamp-park{animation:bajaPark 1.15s ease-in-out infinite}
.baja-root .lamp-flash{animation:bajaFlash .7s ease-in-out infinite}
.baja-root .gear-limit{fill:#c90d18 !important;animation:bajaLimit var(--limit-period,.24s) steps(1,end) infinite}
@media (prefers-reduced-motion:reduce){
  .baja-root .lamp-park,.baja-root .lamp-flash,.baja-root .gear-limit{animation:none;opacity:1}
}
</style>
<svg viewBox="0 0 552 447" role="img" aria-label="Baja Sim race dashboard">
  <defs>
    <filter id="bajaNeedleGlow" x="-40%" y="-40%" width="180%" height="180%">
      <feDropShadow dx="0" dy="1" stdDeviation="1.8" flood-color="#c90d18" flood-opacity="0.75"/>
    </filter>
    <filter id="bajaRead" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="1" stdDeviation="2.2" flood-color="#000" flood-opacity="0.9"/>
    </filter>
    <g id="ico-signalL"><path d="M27 10.5 H14.2 V7 L3.5 16 L14.2 25 V21.5 H27 Z" fill="currentColor"/></g>
    <g id="ico-signalR"><path d="M5 10.5 H17.8 V7 L28.5 16 L17.8 25 V21.5 H5 Z" fill="currentColor"/></g>
    <g id="ico-highbeam">
      <path d="M19 7.5 C26.2 7.5 29 11.2 29 16 S26.2 24.5 19 24.5 H17.2 V7.5 H19 Z" fill="currentColor"/>
      <path d="M14.2 9.6 H3.6 M14.2 13.6 H3.2 M14.2 18.4 H3.2 M14.2 22.4 H3.6" stroke="currentColor" stroke-width="2.15" stroke-linecap="round" fill="none"/>
    </g>
    <g id="ico-parkingbrake">
      <circle cx="16" cy="16" r="11.2" fill="currentColor"/>
      <text x="16" y="21" text-anchor="middle" fill="#050506" font-size="13.5" font-weight="800">P</text>
    </g>
    <g id="ico-engine">
      <path d="M7.2 14.2 h3.4 v-3.6 h7.4 v3.6 h7.2 v2.4 h2.6 v4 h-2.6 v4.6 h-4.2 v2.4 h-7.2 v-2.4 H7.2 v-4.6 H4.4 v-2.4 h2.8z" fill="currentColor"/>
      <circle cx="8.6" cy="23.6" r="2.15" fill="none" stroke="currentColor" stroke-width="1.6"/>
    </g>
    <g id="ico-oil">
      <path d="M7.2 12.8 h11.2 l6 4.8 v8.6 H7.2 V17.4 Z" fill="currentColor"/>
      <path d="M24.2 17.6 H29.4 L32 20.4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M13.4 27.6 c0 2.8 4 2.8 4 0" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round"/>
    </g>
    <g id="ico-battery">
      <rect x="5.2" y="11.6" width="21.6" height="14.2" rx="1.8" fill="currentColor"/>
      <rect x="8.6" y="8.4" width="5.2" height="3.4" rx="0.5" fill="currentColor"/>
      <rect x="18.2" y="8.4" width="5.2" height="3.4" rx="0.5" fill="currentColor"/>
      <path d="M9.4 18.8 h5 M21.6 16.4 v4.8 M19.4 18.8 h4.4" stroke="#050506" stroke-width="1.8" stroke-linecap="round"/>
    </g>
    <g id="ico-coolant">
      <path d="M14.8 4.8 h2.4 v9.2 c3.4 1.1 5.4 3.5 5.4 6.7 0 4.1-3.4 6.9-6.6 6.9s-6.6-2.8-6.6-6.9c0-3.2 2-5.6 5.4-6.7 V4.8z" fill="currentColor"/>
      <path d="M14.4 8.4 h3.2" stroke="#050506" stroke-width="1.5" stroke-linecap="round"/>
      <path d="M3.6 20.2 q2.4 1.8 4.8 0 q2.4 -1.8 4.8 0" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round"/>
    </g>
  </defs>

  <g id="bajaLamps"></g>

  <g id="bajaLeft" filter="url(#bajaRead)">
    <g id="bajaSlot0">
      <text class="slot-lab" x="130" y="0" text-anchor="end" fill="#9a958c" font-size="11" font-weight="600" letter-spacing="0.32em">WATER</text>
      <text id="bajaWater" class="slot-val tabular" x="130" y="40" text-anchor="end" fill="#f2f0eb" font-size="36" font-weight="600">—</text>
    </g>
    <g id="bajaSlot1">
      <text class="slot-lab" x="130" y="0" text-anchor="end" fill="#9a958c" font-size="11" font-weight="600" letter-spacing="0.32em">OIL</text>
      <text id="bajaOil" class="slot-val tabular" x="130" y="40" text-anchor="end" fill="#f2f0eb" font-size="36" font-weight="600">—</text>
    </g>
    <g id="bajaSlot2" class="hit">
      <title>Click to clear trip</title>
      <text class="slot-lab" x="130" y="0" text-anchor="end" fill="#9a958c" font-size="11" font-weight="600" letter-spacing="0.32em">TRIP</text>
      <text id="bajaTrip" class="slot-val tabular" x="130" y="40" text-anchor="end" fill="#f2f0eb" font-size="36" font-weight="600">—</text>
    </g>
    <g id="bajaSlot3" style="display:none">
      <text class="slot-lab" x="130" y="0" text-anchor="end" fill="#9a958c" font-size="11" font-weight="600" letter-spacing="0.32em">BOOST</text>
      <text id="bajaBoost" class="slot-val tabular" x="130" y="40" text-anchor="end" fill="#f2f0eb" font-size="36" font-weight="600">—</text>
    </g>
  </g>

  <g id="bajaTach">
    <path fill="#181a1d" fill-rule="evenodd" d="M 135 218 a 163 163 0 1 1 326 0 a 163 163 0 1 1 -326 0 M 147 218 a 151 151 0 1 0 302 0 a 151 151 0 1 0 -302 0"/>
    <circle cx="298" cy="218" r="145" fill="#000000" fill-opacity="0.25"/>
    <circle cx="298" cy="218" r="145" fill="none" stroke="#c90d18" stroke-width="2.4"/>
    <path id="bajaTrack" d="" fill="none" stroke="#2a2c30" stroke-opacity="0.9" stroke-width="5.5"/>
    <path id="bajaSweep" d="" fill="none" stroke="#c90d18" stroke-width="5.5"/>
    <g id="bajaTicks"></g>
    <text x="298" y="144" text-anchor="middle" fill="#5a5d63" font-size="10" font-weight="600" letter-spacing="0.38em">RPM</text>
    <text x="298" y="157" text-anchor="middle" fill="#5a5d63" font-size="8" font-weight="600" letter-spacing="0.18em">x1000</text>
    <g transform="translate(298 218)">
      <g id="bajaNeedle" filter="url(#bajaNeedleGlow)" transform="rotate(-135 0 0)">
        <polygon points="0,-118 5.2,-44 0,-38 -5.2,-44" fill="#c90d18"/>
      </g>
    </g>
    <circle cx="298" cy="218" r="40" fill="#070708" fill-opacity="0.82" stroke="#121314" stroke-width="1.8"/>
    <text id="bajaGear" x="298" y="222" text-anchor="middle" dominant-baseline="middle" fill="#f2f0eb" font-size="58" font-weight="700" class="tabular">N</text>
    <text id="bajaSpeed" x="298" y="310" text-anchor="middle" fill="#f2f0eb" font-size="42" font-weight="700" class="tabular" filter="url(#bajaRead)">0</text>
    <text id="bajaUnit" x="298" y="330" text-anchor="middle" fill="#9a958c" font-size="11" font-weight="600" letter-spacing="0.28em">KM/H</text>
  </g>

  <g filter="url(#bajaRead)">
    <text x="466" y="110" fill="#9a958c" font-size="11" font-weight="600" letter-spacing="0.32em">FUEL</text>
    <g id="bajaFuelBars"></g>
    <g id="bajaJerry" transform="translate(500 174) scale(0.84)">
      <path id="jerryBody" d="M8 9 L15 2 H43 Q51 2 51 11 V56 Q51 64 43 64 H10 Q2 64 2 56 V23 Q2 17 6 13" fill="transparent" stroke="#f2f0eb" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M18 10 H43 V20 H14 Z" fill="none" stroke="#f2f0eb" stroke-width="2.4" stroke-linejoin="round"/>
      <path d="M15 27 L38 53 M38 27 L15 53" fill="none" stroke="#f2f0eb" stroke-width="2.4" stroke-linecap="round"/>
      <path d="M7 13 L0 7 L7 0 L13 7 Z" fill="none" stroke="#f2f0eb" stroke-width="2.4" stroke-linejoin="round"/>
    </g>
  </g>
  <g id="bajaDrive"></g>
</svg>
</div>`,
      link: function (scope, element) {
        var streamsList = ["electrics", "engineInfo", "powertrainDeviceData", "forcedInductionInfo"];
        StreamsManager.add(streamsList);
        scope.$on("$destroy", function () {
          StreamsManager.remove(streamsList);
        });

        var root = element[0];
        var svg = root.querySelector("svg");
        var NS = "http://www.w3.org/2000/svg";
        var CX = 298,
          CY = 218,
          R = 132,
          START = -135,
          SWEEP = 270,
          SWEEP_R = 136,
          DRIVE_Y = 421;
        var BLOOD = "#c90d18";
        var TICK = "#6d7076";
        var CREAM = "#f2f0eb";
        var MUTED = "#9a958c";
        var ORANGE = "#ff7a14";
        var OUTER = "#8a8e94";
        var OFF_FILL = "#070708";
        var tachK = 7;
        var tachMax = 7000;
        var limiterRpm = 7000;
        var limiterCutSec = 0.12;
        var laggedRpm = 0;
        var lastNeedleT = performance.now();
        var lastMetaAt = 0;
        var tripMeters = 0;
        var tripBaseMeters = 0;
        var tripFromEvent = false;
        var devices = [];
        var hasEngine = false;
        var ignitionLevel = 0;
        var leftLaid = -1;
        var MI = 0.000621371;

        function layoutLeft(n) {
          if (n === leftLaid) return;
          leftLaid = n;
          var compact = n > 3;
          var y0 = compact ? 106 : 110;
          var step = compact ? 55 : 78;
          var vSize = compact ? 28 : 34;
          var vDy = compact ? 31 : 38;
          var i;
          for (i = 0; i < 4; i++) {
            var slot = svg.querySelector("#bajaSlot" + i);
            if (!slot) continue;
            slot.style.display = i < n ? "block" : "none";
            slot.setAttribute("transform", "translate(0 " + (y0 + i * step) + ")");
            var lab = slot.querySelector(".slot-lab");
            var val = slot.querySelector(".slot-val");
            if (val) {
              val.setAttribute("y", String(vDy));
              val.setAttribute("font-size", String(vSize));
            }
            if (lab) lab.setAttribute("font-size", "11");
          }
        }
        layoutLeft(3);
        svg.querySelector("#bajaSlot2").addEventListener("click", function (event) {
          event.preventDefault();
          event.stopPropagation();
          tripBaseMeters = tripMeters;
          paintTrip();
        });

        function polar(cx, cy, r, deg) {
          var rad = ((deg - 90) * Math.PI) / 180;
          return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
        }
        function arcD(cx, cy, r, a0, a1) {
          var p0 = polar(cx, cy, r, a0);
          var p1 = polar(cx, cy, r, a1);
          var large = a1 - a0 > 180 ? 1 : 0;
          return "M " + p0.x.toFixed(2) + " " + p0.y.toFixed(2) + " A " + r + " " + r + " 0 " + large + " 1 " + p1.x.toFixed(2) + " " + p1.y.toFixed(2);
        }
        function el(name, attrs, parent) {
          var n = document.createElementNS(NS, name);
          Object.keys(attrs).forEach(function (k) {
            n.setAttribute(k, attrs[k]);
          });
          if (parent) parent.appendChild(n);
          return n;
        }
        function clamp(n, a, b) {
          return Math.max(a, Math.min(b, n));
        }
        function readTempC(v) {
          if (v == null || isNaN(v)) return null;
          if (v <= 2) return 50 + v * 70;
          return v;
        }
        function readVolt(e) {
          if (!e) return null;
          var v = e.batteryVoltage;
          if (v == null) v = e.voltage;
          if (v == null) v = e.voltmeter;
          if (v == null) return null;
          if (v <= 1.5) return 11.4 + v * 3.2;
          return v;
        }

        var LAMPS = [
          { id: "signalL", tone: "#2fa85a", flash: "lamp-flash", ico: "ico-signalL" },
          { id: "signalR", tone: "#2fa85a", flash: "lamp-flash", ico: "ico-signalR" },
          { id: "highbeam", tone: "#3b7dd8", ico: "ico-highbeam" },
          { id: "parkingbrake", tone: BLOOD, flash: "lamp-park", ico: "ico-parkingbrake" },
          { id: "engine", tone: "#d4a017", ico: "ico-engine" },
          { id: "oil", tone: BLOOD, ico: "ico-oil" },
          { id: "battery", tone: BLOOD, ico: "ico-battery" },
          { id: "coolant", tone: BLOOD, ico: "ico-coolant" },
        ];

        var lampNodes = {};
        (function buildLamps() {
          var g = svg.querySelector("#bajaLamps");
          var step = 48;
          var start = CX - ((LAMPS.length - 1) * step) / 2 - 21;
          LAMPS.forEach(function (l, i) {
            var x = start + i * step;
            var wrap = el("g", { transform: "translate(" + x + " 5)", opacity: "0", "data-id": l.id }, g);
            el("rect", { x: "0", y: "0", width: "42", height: "30", rx: "5", fill: "#050506", "fill-opacity": "0.94", stroke: "#000", "stroke-width": "1" }, wrap);
            el("rect", { x: "1.2", y: "1.2", width: "39.6", height: "27.6", rx: "4", fill: "none", stroke: "#141416", "stroke-width": "0.8" }, wrap);
            el("use", { href: "#" + l.ico, "xlink:href": "#" + l.ico, x: "5", y: "-1", color: l.tone, fill: l.tone, style: "color:" + l.tone }, wrap);
            lampNodes[l.id] = { wrap: wrap, flash: l.flash || "" };
          });
        })();

        function setLamp(id, on) {
          var n = lampNodes[id];
          if (!n) return;
          n.wrap.setAttribute("opacity", on ? "1" : "0");
          n.wrap.setAttribute("class", on && n.flash ? n.flash : "");
        }

        (function buildFuel() {
          var g = svg.querySelector("#bajaFuelBars");
          for (var i = 0; i < 8; i++) {
            el("rect", { id: "fuelBar" + (7 - i), x: "466", y: String(122 + i * 22), width: "20", height: "17", rx: "3", fill: "transparent", stroke: CREAM, "stroke-opacity": "0.28", "stroke-width": "1.4" }, g);
          }
        })();

        function setFuel(frac) {
          var filled = Math.round(clamp(frac, 0, 1) * 8);
          var alert = frac <= 0.15;
          for (var i = 0; i < 8; i++) {
            var r = svg.querySelector("#fuelBar" + i);
            var on = i < filled;
            r.setAttribute("fill", on ? BLOOD : "transparent");
            r.setAttribute("stroke", on ? BLOOD : CREAM);
            r.setAttribute("stroke-opacity", on ? "1" : "0.28");
            r.setAttribute("class", alert ? "lamp-park" : "");
          }
          var jerry = svg.querySelector("#bajaJerry");
          jerry.setAttribute("class", alert ? "lamp-park" : "");
          var body = svg.querySelector("#jerryBody");
          body.setAttribute("fill", alert ? BLOOD : "transparent");
          body.setAttribute("fill-opacity", alert ? "1" : "0");
          body.setAttribute("stroke", alert ? BLOOD : CREAM);
          Array.prototype.forEach.call(jerry.querySelectorAll("[stroke]"), function (p) {
            p.setAttribute("stroke", alert ? BLOOD : CREAM);
          });
        }

        function buildTicks(k) {
          var g = svg.querySelector("#bajaTicks");
          while (g.firstChild) g.removeChild(g.firstChild);
          var i, a, p1, p2, lab, t, hot;
          for (i = 0; i <= k * 2; i++) {
            a = START + (i / (k * 2)) * SWEEP;
            if (i % 2 === 1) {
              p1 = polar(CX, CY, R - 18, a);
              p2 = polar(CX, CY, R - 8, a);
              el("line", { x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, stroke: "#b8b6b0", "stroke-width": "1.15" }, g);
            }
          }
          for (i = 0; i <= k; i++) {
            a = START + (i / k) * SWEEP;
            p1 = polar(CX, CY, R - 28, a);
            p2 = polar(CX, CY, R - 8, a);
            lab = polar(CX, CY, R - 48, a);
            hot = i >= k - 1;
            el("line", { x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, stroke: "#d8d5ce", "stroke-width": "2.1" }, g);
            t = el("text", { x: lab.x, y: lab.y, "text-anchor": "middle", "dominant-baseline": "middle", fill: hot ? BLOOD : "#ffffff", "font-size": "18", "font-weight": "700", class: "tabular" }, g);
            t.textContent = String(i);
          }
          svg.querySelector("#bajaTrack").setAttribute("d", arcD(CX, CY, SWEEP_R, START, START + SWEEP));
        }
        buildTicks(tachK);

        function setNeedle(pct) {
          var ang = START + clamp(pct, 0, 1) * SWEEP;
          svg.querySelector("#bajaNeedle").setAttribute("transform", "rotate(" + ang + " 0 0)");
        }

        function setSweep(pct) {
          var ang = START + clamp(pct, 0, 1) * SWEEP;
          svg.querySelector("#bajaSweep").setAttribute("d", arcD(CX, CY, SWEEP_R, START, ang));
        }

        function tickNeedle(rpm) {
          var now = performance.now();
          var dt = Math.min(0.05, (now - lastNeedleT) / 1000);
          lastNeedleT = now;
          laggedRpm += (rpm - laggedRpm) * (1 - Math.exp(-dt / 0.12));
          var bounce = 0;
          if (rpm >= limiterRpm - 50) {
            var period = Math.max(0.07, limiterCutSec);
            bounce = Math.sin((now / 1000) * ((Math.PI * 2) / period)) * (tachMax * 0.011);
          }
          setNeedle(tachMax > 0 ? (laggedRpm + bounce) / tachMax : 0);
          setSweep(tachMax > 0 ? (rpm + bounce) / tachMax : 0);
        }

        function paintTrip() {
          var miles = Math.max(0, (tripMeters - tripBaseMeters) * MI);
          setReadout("bajaTrip", miles, "MI", miles >= 1000 ? 0 : 1, false);
        }

        function setReadout(id, value, unit, digits, hot) {
          var n = svg.querySelector("#" + id);
          if (!n) return;
          if (value == null || isNaN(value)) {
            n.textContent = "—";
            n.setAttribute("fill", MUTED);
            return;
          }
          n.textContent = "";
          n.setAttribute("fill", hot ? BLOOD : CREAM);
          n.appendChild(document.createTextNode(Number(value).toFixed(digits)));
          var ts = document.createElementNS(NS, "tspan");
          ts.setAttribute("font-size", "12");
          ts.setAttribute("dx", "6");
          ts.setAttribute("fill", MUTED);
          ts.setAttribute("font-weight", "600");
          ts.textContent = unit;
          n.appendChild(ts);
        }

        function paintGear(gear, rpm) {
          var gearNode = svg.querySelector("#bajaGear");
          if (gear === "0") gear = "N";
          else if (gear === "-1") gear = "R";
          gearNode.textContent = gear;
          gearNode.setAttribute("font-size", gear.length > 1 ? "36" : "58");
          var onLimiter = rpm >= limiterRpm - 220;
          var approaching = !onLimiter && rpm >= limiterRpm - 1000;
          if (onLimiter) {
            gearNode.setAttribute("fill", BLOOD);
            gearNode.style.fill = BLOOD;
            gearNode.setAttribute("class", "tabular gear-limit");
            gearNode.style.setProperty("--limit-period", Math.max(0.08, limiterCutSec * 2) + "s");
          } else if (approaching) {
            gearNode.setAttribute("fill", ORANGE);
            gearNode.style.fill = ORANGE;
            gearNode.setAttribute("class", "tabular");
            gearNode.style.removeProperty("--limit-period");
          } else {
            var col = gear === "R" || gear === "-1" ? BLOOD : CREAM;
            gearNode.setAttribute("fill", col);
            gearNode.style.fill = col;
            gearNode.setAttribute("class", "tabular");
            gearNode.style.removeProperty("--limit-period");
          }
        }

        function layoutDrive() {
          var g = svg.querySelector("#bajaDrive");
          var nodes = Array.prototype.slice.call(g.children);
          var n = nodes.length;
          nodes.forEach(function (node, i) {
            var x = CX - ((n - 1) * 52) / 2 + i * 52;
            node.setAttribute("transform", "translate(" + x + " " + DRIVE_Y + ")");
          });
        }

        function ensureIgnition() {
          var g = svg.querySelector("#bajaDrive");
          var existing = g.querySelector('[data-id="ignition"]');
          if (!hasEngine) {
            if (existing) existing.remove();
            layoutDrive();
            return;
          }
          if (existing) return;
          var btn = el("g", { "data-id": "ignition", class: "hit" }, g);
          el("circle", { r: "20", fill: BLOOD, "fill-opacity": "0.92", stroke: BLOOD, "stroke-width": "1.6" }, btn);
          el("circle", { r: "7.4", fill: "none", stroke: "#050506", "stroke-width": "1.8" }, btn);
          el("path", { d: "M0 -11.5 V-3", fill: "none", stroke: "#050506", "stroke-width": "2.2", "stroke-linecap": "round" }, btn);
          var title = el("title", {}, btn);
          title.textContent = "Ignition";
          btn.addEventListener("mousedown", function () {
            bngApi.activeObjectLua("electrics.toggleIgnitionLevelOnDown()");
          });
          btn.addEventListener("mouseup", function () {
            bngApi.activeObjectLua("electrics.toggleIgnitionLevelOnUp()");
          });
          g.insertBefore(btn, g.firstChild);
          layoutDrive();
        }

        function paintIgnition() {
          var btn = svg.querySelector('#bajaDrive [data-id="ignition"]');
          if (!btn) return;
          var on = ignitionLevel > 0;
          var c = btn.querySelector("circle");
          c.setAttribute("fill", on ? BLOOD : OFF_FILL);
          c.setAttribute("fill-opacity", on ? "0.92" : "0.35");
          c.setAttribute("stroke", on ? BLOOD : OUTER);
          btn.setAttribute("class", "hit" + (ignitionLevel === 1 ? " lamp-park" : ""));
        }

        function deviceColor(value) {
          if (value == null || value === "") return null;
          if (typeof value === "number") {
            value = Math.max(0, value).toString(16);
          }
          value = String(value).replace(/^#/, "");
          if (/^[0-9a-f]{3}$/i.test(value)) {
            value = value.charAt(0) + value.charAt(0) + value.charAt(1) + value.charAt(1) + value.charAt(2) + value.charAt(2);
          }
          return /^[0-9a-f]{6}$/i.test(value) ? "#" + value : null;
        }

        function refreshDeviceButtons() {
          try {
            bngApi.activeObjectLua("extensions.ui_simplePowertrainControl.updateButtons()");
          } catch (e) {}
        }

        function paintDeviceButtons() {
          var buttons = Array.prototype.slice.call(svg.querySelectorAll('#bajaDrive > g:not([data-id="ignition"])'));
          var activeIndex = 0;
          buttons.forEach(function (button) {
            if (!button._bajaActive) return;
            var activeCircle = button.querySelector("circle");
            var activeColor = activeIndex === 0 ? "#d4a017" : BLOOD;
            activeCircle.setAttribute("fill", activeColor);
            activeCircle.setAttribute("fill-opacity", "0.92");
            activeCircle.setAttribute("stroke", activeColor);
            activeIndex += 1;
          });
          buttons.forEach(function (button) {
            if (button._bajaActive) return;
            var inactiveCircle = button.querySelector("circle");
            inactiveCircle.setAttribute("fill", OFF_FILL);
            inactiveCircle.setAttribute("fill-opacity", "0.35");
            inactiveCircle.setAttribute("stroke", OUTER);
          });
        }

        function upsertDevice(data) {
          var g = svg.querySelector("#bajaDrive");
          if (data.remove) {
            var gone = g.querySelector('[data-id="' + data.id + '"]');
            if (gone) gone.remove();
            layoutDrive();
            return;
          }
          var btn = g.querySelector('[data-id="' + data.id + '"]');
          if (!btn) {
            btn = el("g", { "data-id": data.id, class: "hit" }, g);
            el("circle", { r: "20", fill: OFF_FILL, "fill-opacity": "0.35", stroke: OUTER, "stroke-width": "1.6" }, btn);
            var tx = el("text", { x: "0", y: "4", "text-anchor": "middle", fill: CREAM, "font-size": "9", "font-weight": "700" }, btn);
            tx.textContent = (data.tooltip || data.id || "").slice(0, 4).toUpperCase();
            var title = el("title", {}, btn);
            title.textContent = data.tooltip || data.id;
            btn.addEventListener("click", function (event) {
              event.preventDefault();
              event.stopPropagation();
              if (!this._bajaOnClick) return;
              this._bajaActive = !this._bajaActive;
              this._bajaTouched = true;
              paintDeviceButtons();
              bngApi.activeObjectLua(this._bajaOnClick);
              refreshDeviceButtons();
              setTimeout(refreshDeviceButtons, 80);
              setTimeout(refreshDeviceButtons, 220);
            });
          }
          btn._bajaOnClick = data.onClick || "";
          var label = btn.querySelector("text");
          if (label && data.tooltip) label.textContent = String(data.tooltip).slice(0, 4).toUpperCase();
          var ring = deviceColor(data.color);
          var c = btn.querySelector("circle");
          var active = !!ring && ring.toLowerCase() !== "#343434";
          if (!btn._bajaTouched) btn._bajaActive = active;
          paintDeviceButtons();
          layoutDrive();
        }

        function applyUnitLabel() {
          try {
            var u = UiUnits.speed(0);
            if (u && u.unit) svg.querySelector("#bajaUnit").textContent = String(u.unit).toUpperCase();
          } catch (e) {}
        }

        function requestEngineMeta() {
          try {
            bngApi.activeObjectLua(
              [
                "local eng = powertrain and (powertrain.getDevice('mainEngine') or powertrain.getDevice('frontMotor') or powertrain.getDevice('rearMotor'))",
                "local cut, lim = 0.12, nil",
                "if eng then",
                "  if type(eng.revLimiterCutTime) == 'number' then cut = eng.revLimiterCutTime end",
                "  if type(eng.revLimiterHoldDuration) == 'number' and type(eng.revLimiterCutTime) ~= 'number' then cut = eng.revLimiterHoldDuration end",
                "  if electrics and electrics.values and electrics.values.twoStep and type(eng.twoStepCutTime) == 'number' then cut = eng.twoStepCutTime end",
                "  lim = eng.revLimiterRPM or eng.maxRPM",
                "end",
                "guihooks.trigger('bajaEngineMeta', {cutTime=cut, limiterRPM=lim})",
              ].join("\n")
            );
          } catch (e) {}
        }

        function loadTrip() {
          try {
            bngApi.activeObjectLua('extensions.load("simpleTripApp")');
          } catch (e) {}
        }

        bngApi.engineLua("settings.notifyUI()");
        loadTrip();
        requestEngineMeta();
        scope.$on("SettingsChanged", applyUnitLabel);
        scope.$on("bajaEngineMeta", function (event, data) {
          if (!data) return;
          if (typeof data.cutTime === "number" && data.cutTime > 0.02) limiterCutSec = data.cutTime;
          if (typeof data.limiterRPM === "number" && data.limiterRPM > 500) limiterRpm = data.limiterRPM;
        });
        scope.$on("tripData", function (event, data) {
          if (data && typeof data.totalDistance === "number") {
            tripMeters = data.totalDistance;
            tripFromEvent = true;
            paintTrip();
          }
        });

        scope.$on("streamsUpdate", function (event, streams) {
          if (!streams.electrics) return;
          var e = streams.electrics;
          var speedMs = e.airspeed;
          if (isNaN(speedMs)) speedMs = e.wheelspeed || 0;
          var converted = null;
          try {
            converted = UiUnits.speed(speedMs);
          } catch (err) {}
          var speedVal = converted && converted.val != null ? Math.round(converted.val) : Math.round(speedMs * 3.6);
          if (converted && converted.unit) svg.querySelector("#bajaUnit").textContent = String(converted.unit).toUpperCase();
          svg.querySelector("#bajaSpeed").textContent = String(speedVal);

          var rpm = e.rpmTacho;
          if (rpm == null) rpm = e.rpm;
          var maxRpm = tachMax;
          if (streams.engineInfo) {
            if (streams.engineInfo[4] != null) rpm = streams.engineInfo[4];
            if (streams.engineInfo[1] != null && streams.engineInfo[1] > 1000) maxRpm = streams.engineInfo[1];
          }
          rpm = rpm || 0;
          var k = Math.max(4, Math.round(maxRpm / 1000));
          if (k !== tachK) {
            tachK = k;
            tachMax = k * 1000;
            buildTicks(tachK);
          }
          if (limiterRpm < 500 || Math.abs(limiterRpm - maxRpm) > 4000) limiterRpm = maxRpm;
          tickNeedle(rpm);

          var gear = "N";
          if (streams.engineInfo && streams.engineInfo[5] != null && streams.engineInfo[5] !== "") {
            gear = String(streams.engineInfo[5]);
          } else if (e.gear) gear = String(e.gear);
          else if (e.gearIndex != null) {
            if (e.gearIndex < 0) gear = "R";
            else if (e.gearIndex === 0) gear = "N";
            else gear = String(e.gearIndex);
          }
          paintGear(gear, rpm);

          var fuel = typeof e.fuel === "number" ? e.fuel : 0;
          setFuel(fuel);

          var waterC = readTempC(e.watertemp);
          var oilC = readTempC(e.oiltemp);
          var waterShow = waterC,
            oilShow = oilC,
            tUnit = "°C";
          try {
            if (waterC != null && UiUnits.temperature) {
              var wt = UiUnits.temperature(waterC);
              if (wt) {
                waterShow = wt.val;
                tUnit = "°" + (wt.unit || "C");
              }
            }
            if (oilC != null && UiUnits.temperature) {
              var ot = UiUnits.temperature(oilC);
              if (ot) oilShow = ot.val;
            }
          } catch (err2) {}
          setReadout("bajaWater", waterShow, tUnit, 0, waterC != null && waterC >= 108);
          setReadout("bajaOil", oilShow, tUnit, 0, oilC != null && oilC >= 132);

          if (!tripFromEvent && e.odometer != null && isFinite(e.odometer)) {
            tripMeters = e.odometer;
          }
          paintTrip();

          var fi = streams.forcedInductionInfo;
          var hasFi = !!(fi && isFinite(Number(fi.boost)) && isFinite(Number(fi.maxBoost)));
          layoutLeft(hasFi ? 4 : 3);
          if (hasFi) {
            var boostShow = fi.boost;
            var boostUnit = "BAR";
            try {
              if (UiUnits.pressure) {
                var bp = UiUnits.pressure(fi.boost);
                if (bp) {
                  boostShow = bp.val;
                  boostUnit = String(bp.unit || "BAR").toUpperCase();
                }
              }
            } catch (err3) {}
            setReadout("bajaBoost", boostShow, boostUnit, 1, fi.boost >= fi.maxBoost * 0.9);
          }

          var volt = readVolt(e);
          setLamp("signalL", e.signal_L > 0.4);
          setLamp("signalR", e.signal_R > 0.4);
          setLamp("highbeam", e.highbeam > 0.5);
          setLamp("parkingbrake", e.parkingbrake > 0.5);
          setLamp("engine", !!e.checkengine);
          setLamp("oil", !!e.oil || e.lowpressure > 0.5);
          setLamp("battery", volt != null && volt < 12);
          setLamp("coolant", waterC != null && waterC >= 108);

          ignitionLevel = e.ignitionLevel || 0;
          if (streams.powertrainDeviceData && streams.powertrainDeviceData.devices) {
            var d = streams.powertrainDeviceData.devices;
            hasEngine = !!(d.mainEngine || d.frontMotor || d.rearMotor);
          }
          ensureIgnition();
          paintIgnition();

          var now = performance.now();
          if (now - lastMetaAt > 800) {
            lastMetaAt = now;
            requestEngineMeta();
          }
        });

        scope.$on("ChangePowerTrainButtons", function (event, data) {
          if (!data || !data.id) return;
          upsertDevice(data);
        });

        function resetDrive() {
          var g = svg.querySelector("#bajaDrive");
          while (g.firstChild) g.removeChild(g.firstChild);
          hasEngine = false;
          devices = [];
          tripMeters = 0;
          tripBaseMeters = 0;
          tripFromEvent = false;
          loadTrip();
          requestEngineMeta();
          bngApi.activeObjectLua("extensions.ui_simplePowertrainControl.updateButtons()");
        }
        scope.$on("VehicleChange", resetDrive);
        scope.$on("VehicleFocusChanged", resetDrive);

        try {
          bngApi.activeObjectLua("extensions.ui_simplePowertrainControl.updateButtons()");
        } catch (e3) {}
      },
    };
  },
]);
