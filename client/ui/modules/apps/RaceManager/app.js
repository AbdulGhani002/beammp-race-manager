angular.module("beamng.apps")

// Drag a panel by its heading, resize it from the bottom right corner, and
// remember where it was put. He asked for this after using it: a window that
// sits where the mod decided is fine until it covers the bit of road you are
// looking at.
//
// Position is kept per panel in localStorage, so it survives a rejoin. Panels
// are clamped back on screen when they load, otherwise a window dragged off
// the edge on a wide monitor is gone for good on a narrow one.
.directive("rmDrag", [function () {
  return {
    restrict: "A",
    link: function (scope, element, attrs) {
      var node = element[0];
      var key = "rm.panel." + (attrs.rmDrag || "panel");
      var MIN_W = 320, MIN_H = 160, EDGE = 24;

      function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

      function place(box) {
        var maxX = window.innerWidth - EDGE;
        var maxY = window.innerHeight - EDGE;
        node.style.left = clamp(box.x, -MIN_W + EDGE, maxX) + "px";
        node.style.top = clamp(box.y, 0, maxY) + "px";
        node.style.transform = "none";
        node.style.right = "auto";
        node.style.bottom = "auto";
        if (box.w) node.style.width = Math.max(MIN_W, box.w) + "px";
        if (box.h) node.style.height = Math.max(MIN_H, box.h) + "px";
      }

      function remember(box) {
        try { localStorage.setItem(key, JSON.stringify(box)); } catch (e) { }
      }

      var saved = null;
      try { saved = JSON.parse(localStorage.getItem(key)); } catch (e) { }
      if (saved && typeof saved.x === "number") place(saved);

      function beginDrag(startEvent, mode) {
        startEvent.preventDefault();
        var rect = node.getBoundingClientRect();
        var ox = startEvent.clientX, oy = startEvent.clientY;
        var box = { x: rect.left, y: rect.top, w: rect.width, h: rect.height };

        function onMove(e) {
          var dx = e.clientX - ox, dy = e.clientY - oy;
          if (mode === "move") {
            place({ x: box.x + dx, y: box.y + dy, w: box.w, h: box.h });
          } else {
            place({ x: box.x, y: box.y, w: box.w + dx, h: box.h + dy });
          }
        }

        function onUp() {
          document.removeEventListener("mousemove", onMove);
          document.removeEventListener("mouseup", onUp);
          var r = node.getBoundingClientRect();
          remember({ x: r.left, y: r.top, w: r.width, h: r.height });
        }

        document.addEventListener("mousemove", onMove);
        document.addEventListener("mouseup", onUp);
      }

      var handle = node.querySelector("h2") || node.querySelector(".rm-players-head");
      if (handle) {
        handle.classList.add("rm-handle");
        handle.addEventListener("mousedown", function (e) { beginDrag(e, "move"); });
      }

      var grip = document.createElement("div");
      grip.className = "rm-grip";
      grip.title = "Drag to resize";
      grip.addEventListener("mousedown", function (e) { beginDrag(e, "resize"); });
      node.appendChild(grip);

      // put it back where the css wanted it
      scope.rmResetPanel = function () {
        try { localStorage.removeItem(key); } catch (e) { }
        node.style.left = ""; node.style.top = ""; node.style.width = "";
        node.style.height = ""; node.style.transform = ""; node.style.right = "";
        node.style.bottom = "";
      };
    }
  };
}])

.directive("raceManager", [function () {
  return {
    templateUrl: "/ui/modules/apps/RaceManager/app.html",
    replace: true,
    restrict: "EA",
    scope: true,

    controller: ["$scope", "$timeout", function ($scope, $timeout) {

      // everything drawn comes from here. the server owns it, this only mirrors.
      $scope.s = { ready: false, needsName: false, me: {}, roster: [], tracks: [],
                   capture: {}, perf: {}, config: {}, race: {} };
      $scope.panel = null;
      // ng-if and ng-repeat each make a child scope, so a bare string model is
      // written on the child and the parent never sees it. Anything two way
      // bound has to sit behind a dot.
      $scope.form = { name: "", code: "" };
      $scope.recovering = false;
      $scope.speed = 0;
      $scope.newTrack = { name: "", kind: "race", circuit: true, overwrite: false };
      $scope.entry = { track: null, mode: "controller", laps: 1 };
      $scope.opened = null;
      $scope.openedLap = null;
      $scope.sectors = [];

      // engineLua takes a lua expression, not json, so values have to go over
      // as a lua table literal. JSON.stringify already produces a string
      // literal lua accepts, which is the only fiddly part.
      function luaVal(v) {
        if (v === null || v === undefined) return "nil";
        if (typeof v === "boolean") return v ? "true" : "false";
        if (typeof v === "number") return isFinite(v) ? String(v) : "0";
        if (typeof v === "string") return JSON.stringify(v);
        if (Array.isArray(v)) return "{" + v.map(luaVal).join(",") + "}";
        var parts = [];
        for (var k in v) {
          if (Object.prototype.hasOwnProperty.call(v, k)) {
            parts.push("[" + JSON.stringify(k) + "]=" + luaVal(v[k]));
          }
        }
        return "{" + parts.join(",") + "}";
      }

      function call(module, fn, value) {
        var expr = "extensions." + module + "." + fn + "(";
        if (value !== undefined) {
          // a js array at the top level means several arguments, not one table
          expr += Array.isArray(value) ? value.map(luaVal).join(",") : luaVal(value);
        }
        bngApi.engineLua(expr + ")");
      }

      function ui(fn, value) { call("raceManager_ui", fn, value); }
      $scope.cap = function (fn, value) { call("raceManager_capture", fn, value); };

      // the car has to be stopped for the bottom bar. electrics is already
      // streamed to the ui by the game, so reading it here costs us no lua.
      var streams = ["electrics"];
      StreamsManager.add(streams);

      // Escape shuts the top thing that is open, so there is one way out of
      // everything on screen and not just the panels with a close button.
      function onKey(e) {
        if (e.key !== "Escape" && e.keyCode !== 27) return;
        if ($scope.s.lights) ui("closeLights");
        else if ($scope.panel) $scope.panel = null;
        else if ($scope.s.rosterOpen) ui("setRosterOpen", false);
        else return;
        $scope.$applyAsync();
      }
      document.addEventListener("keydown", onKey);

      $scope.$on("$destroy", function () {
        StreamsManager.remove(streams);
        document.removeEventListener("keydown", onKey);
        ui("setRosterOpen", false);
      });

      $scope.$on("streamsUpdate", function (_, s) {
        if (!s || !s.electrics) return;
        var mph = Math.round(Math.abs(s.electrics.wheelspeed || 0) * 2.2369363);
        if (mph !== $scope.speed) {
          $scope.speed = mph;
          $scope.$applyAsync();
        }
      });

      // open the capture window once when a capture starts, and not again.
      // state arrives up to ten times a second, so reopening it whenever the
      // panel is closed means the close button can never win.
      var capturePanelShown = false;

      $scope.$on("rmState", function (_, data) {
        $scope.$applyAsync(function () {
          $scope.s = data || $scope.s;

          var capturing = data && data.capture && data.capture.active;
          if (!capturing) capturePanelShown = false;

          if (capturing && !capturePanelShown && $scope.panel === null) {
            $scope.panel = "capture";
            capturePanelShown = true;
          }

          var race = (data && data.race) || {};
          if (race.state === "running" && $scope.panel === "race") $scope.panel = null;

          // default the course picker to something real rather than an empty
          // select the Go button refuses to work with
          if (!$scope.entry.track && data && data.tracks && data.tracks.length) {
            $scope.entry.track = data.tracks[0].id;
          }
        });
      });

      ui("requestState");

      // which phase each unfinished button lands in. the shell says so rather
      // than looking broken.
      $scope.SOON = {
        records: "Records arrive in phase 5.",
        copilot: "CoPilot and Chase arrive in phase 6.",
        challenges: "Challenges arrive in phase 6.",
        team: "Team arrives in phase 4.",
        bottom: "The bottom bar buttons become live in phase 3."
      };

      $scope.buttons = [
        { key: "race",       label: "Race" },
        { key: "records",    label: "Records" },
        { key: "copilot",    label: "CoPilot" },
        { key: "challenges", label: "Challenges" },
        { key: "team",       label: "Team" },
        { key: "options",    label: "Options" },
        { key: "discord",    label: "Discord" }
      ];

      $scope.open = function (key) {
        $scope.panel = ($scope.panel === key) ? null : key;
      };

      // the game is fullscreen and keeps focus, so a browser opened from here
      // lands behind it. the panel shows the link so the button is never a
      // dead end.
      $scope.launchDiscord = function () { ui("openDiscord"); };

      // the host is always discord.gg, so only the code is worth reading out
      $scope.inviteCode = function () {
        var url = ($scope.s.config && $scope.s.config.discordUrl) || "";
        var m = url.match(/discord\.gg\/([^\/?#\s]+)/i);
        return m ? "/" + m[1] : url;
      };

      // clipboard is the one route out of here that does not depend on a
      // browser hook the build may not have
      // the clipboard call answers outside angular's own cycle, so the label
      // has to ask for a redraw or it sits there saying copy link
      var copied = 0;
      $scope.copyLabel = function () { return copied > 0 ? "Copied" : "Copy link"; };
      function saidCopied() {
        copied = 1;
        $scope.$applyAsync();
        $timeout(function () { copied = 0; }, 2500);
      }
      $scope.copyInvite = function () {
        var url = ($scope.s.config && $scope.s.config.discordUrl) || "";
        if (!url) return;
        try {
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(url).then(saidCopied, function () {
              fallback(url, saidCopied);
            });
            return;
          }
        } catch (e) { }
        fallback(url, saidCopied);
      };

      function fallback(text, done) {
        try {
          var box = document.createElement("textarea");
          box.value = text;
          box.style.position = "fixed";
          box.style.opacity = "0";
          document.body.appendChild(box);
          box.select();
          document.execCommand("copy");
          document.body.removeChild(box);
          done();
        } catch (e) { }
      }

      // how far round the lap, so a thirty gate course is not just a number.
      // the server counts the gates: working it back from the next one emptied
      // the bar the moment all thirty were done, because the next one is the
      // line again.
      $scope.lapProgress = function () {
        var r = $scope.s.race || {};
        if (!r.gates) return 0;
        var pct = ((r.done || 0) / r.gates) * 100;
        return pct < 0 ? 0 : (pct > 100 ? 100 : Math.round(pct));
      };

      $scope.close = function () { $scope.panel = null; };

      // same child scope trap: an inline assignment in the template writes to
      // whichever scope the click happened in, not this one
      $scope.setPanel = function (p) { $scope.panel = p; };
      $scope.setRecovering = function (v) { $scope.recovering = !!v; };

      $scope.bottom = [
        { key: "reposition", label: "Reposition", note: "1 min penalty" },
        { key: "spare",      label: "Spare tire", note: "30 sec hold, 30 sec penalty" },
        { key: "repair",     label: "Repair",     note: "1 min hold, 30 sec penalty" },
        { key: "fuel",       label: "Fuel +25%",  note: "20 sec hold, no penalty" },
        { key: "lights",     label: "Lights",     note: "" }
      ];

      $scope.lightItems = ["Headlights", "Lightbar", "Fog lights", "Siren", "Hazards", "Horn", "Flash"];

      $scope.lightPick = function (which) {
        call("raceManager_state", "notice", which + ": arrives in phase 3");
        ui("closeLights");
      };

      $scope.closeLights = function () { ui("closeLights"); };

      // Only the light menu gets the catch-all layer. It is the one thing that
      // pops up over the road and has nothing else to shut it. The player list
      // and the panels are meant to be left open while you drive, and a layer
      // eating clicks the whole time they are up would be worse than what it
      // fixed. Escape closes those.
      $scope.anythingOpen = function () { return !!$scope.s.lights; };

      $scope.dismiss = function () { ui("closeLights"); };

      $scope.stopped = function () { return $scope.speed < 1; };

      // the key and the button go through the same lua, so the two cannot
      // disagree about whether the submenu is open
      $scope.bottomClick = function (b) {
        var fn = {
          reposition: "reposition", spare: "spareTire", repair: "repair",
          fuel: "fuel", lights: "lights"
        }[b.key];
        if (fn) call("raceManager_bottombar", fn);
      };


      // ------------------------------------------------------------- racing

      var PENALTY = {
        missed_gate: "Missed checkpoint",
        recovery:    "Recovery",
        flatTire:    "Spare tire",
        repair:      "Repair"
      };

      var PROBLEM = {
        no_such_track:   "That course is gone.",
        course_too_short: "That course has too few checkpoints to race.",
        bad_mode:        "Pick controller or wheel.",
        bad_laps:        "Between one and ninety nine laps.",
        not_a_circuit:   "That course is point to point, so it is one lap.",
        already_running: "You are already on a run. End it first.",
        no_session:      "The server has not finished recognising you yet."
      };

      // round first, then split off the minutes. taking the minutes from the
      // raw value and rounding the seconds on their own put 4:60.0 on screen,
      // because 59.98 to one decimal is 60.0.
      function fmt(sec, places) {
        if (typeof sec !== "number" || !isFinite(sec)) return "—";
        var neg = sec < 0;
        if (neg) sec = -sec;
        var unit = Math.pow(10, places);
        var ticks = Math.round(sec * unit);
        var m = Math.floor(ticks / (60 * unit));
        var rest = (ticks - m * 60 * unit) / unit;
        var body = m > 0
          ? m + ":" + (rest < 10 ? "0" : "") + rest.toFixed(places)
          : rest.toFixed(places);
        return (neg ? "-" : "") + body;
      }

      $scope.clock = function (sec) { return fmt(sec, 3); };

      // the big one redraws ten times a second, so it shows tenths. three
      // decimals flickering at that rate is unreadable and looks broken.
      $scope.bigClock = function (sec) { return fmt(sec, 1); };

      // he asked for penalties on the table, not hidden inside a row
      $scope.penaltySeconds = function (e) {
        var list = (e && e.penalties) || [];
        var total = 0;
        for (var i = 0; i < list.length; i++) total += list[i].seconds || 0;
        return total;
      };

      // penalties are whole seconds, so no decimals
      $scope.penaltyClock = function (sec) { return fmt(sec, 0); };

      $scope.raceIdle = function () {
        var st = ($scope.s.race || {}).state;
        return !st || st === "idle";
      };

      $scope.raceActive = function () {
        var st = ($scope.s.race || {}).state;
        return st === "armed" || st === "running";
      };

      // A native select does not open in the game's interface layer. None of
      // the 116 apps that ship with the game use one, and the one that needs a
      // picker reaches for angular material instead. So these are buttons: they
      // work, they match the rest of the panel, and they are easier to hit with
      // a controller than a dropdown would have been.
      //
      // Written through functions rather than bound with ng-model because
      // ng-if makes a child scope, and a bare assignment lands on the child.
      $scope.pickTrack = function (id) { $scope.entry.track = id; };
      $scope.pickMode  = function (m)  { $scope.entry.mode = m; };
      $scope.pickKind  = function (k)  { $scope.newTrack.kind = k; };

      $scope.chosen = function () {
        var list = $scope.s.tracks || [];
        for (var i = 0; i < list.length; i++) {
          if (list[i].id === $scope.entry.track) return list[i];
        }
        return null;
      };

      // the gates spawn at coordinates that only mean anything on the map they
      // were captured on. arming somewhere else puts them under the world.
      $scope.wrongLevel = function () {
        var t = $scope.chosen();
        return !!(t && t.level && $scope.s.level && t.level !== $scope.s.level);
      };

      $scope.raceProblem = function () {
        var why = ($scope.s.race || {}).problem;
        if (!why) return "";
        return PROBLEM[why] || why;
      };

      $scope.arm = function () {
        if (!$scope.entry.track) return;
        var t = $scope.chosen();
        var laps = (t && !t.circuit) ? 1 : Math.max(1, parseInt($scope.entry.laps, 10) || 1);
        ui("armRace", [$scope.entry.track, $scope.entry.mode, laps]);
      };

      $scope.endRace = function () { ui("endRace"); };

      $scope.raceAgain = function () {
        $scope.opened = null;
        $scope.openedLap = null;
        ui("restartRace");
      };

      $scope.closeResults = function () {
        $scope.opened = null;
        $scope.openedLap = null;
        ui("closeResults");
      };

      // child scope again: a click inside ng-repeat writes to the row's own
      // scope, so the toggle has to be a call on this one
      $scope.expand = function (name) {
        $scope.opened = ($scope.opened === name) ? null : name;
        $scope.openedLap = null;
      };

      $scope.lapKey = function (e, l) { return e.name + ":" + l.lap; };

      $scope.isBestLap = function (e, l) {
        return !!(e.bestLap && e.bestLap.lap === l.lap);
      };

      // worked out once, on the click, and kept. building it inside ng-repeat
      // would hand angular a new array every digest and never settle.
      $scope.expandLap = function (e, l) {
        var key = $scope.lapKey(e, l);
        if ($scope.openedLap === key) {
          $scope.openedLap = null;
          $scope.sectors = [];
          return;
        }

        var gates = ($scope.s.race.results || {}).gates || 0;
        var secs = l.sectors || [];
        var best = e.bestSector || null;
        var out = [];

        // the lua table is indexed from one and arrives here indexed from
        // zero, so the sector into gate g sits at g - 1
        for (var g = 2; g <= gates + 1; g++) {
          var v = secs[g - 1];
          var have = typeof v === "number";
          out.push({
            label: g <= gates
              ? "Gate " + (g - 1) + " to " + g
              : "Gate " + gates + " to the line",
            text: have ? fmt(v, 3) : "—",
            best: have && !!best && best.lap === l.lap && best.gate === g
          });
        }

        $scope.openedLap = key;
        $scope.sectors = out;
      };

      $scope.penaltyText = function (p, showLap) {
        var text = PENALTY[p.reason] || p.reason;
        if (p.gate) text += " " + p.gate;
        if (showLap && p.lap) text += ", lap " + p.lap;
        return text;
      };

      $scope.nameOk = function () {
        var n = ($scope.form.name || "").trim();
        var cfg = $scope.s.config || {};
        return n.length >= (cfg.nameMinLen || 3) && n.length <= (cfg.nameMaxLen || 20);
      };

      $scope.submitName = function () {
        if (!$scope.nameOk()) return;
        ui("setName", $scope.form.name.trim());
      };

      $scope.codeOk = function () {
        return ($scope.form.code || "").replace(/[^a-zA-Z0-9]/g, "").length === 6;
      };

      $scope.submitRecover = function () {
        if (!$scope.codeOk()) return;
        ui("recoverName", $scope.form.code.trim());
      };

      $scope.dismissCode = function () { ui("dismissCode"); };

      // a window dragged somewhere silly on one monitor is hard to find on
      // another, so there is a way back
      $scope.resetPanels = function () {
        try {
          var kill = [];
          for (var i = 0; i < localStorage.length; i++) {
            var k = localStorage.key(i);
            if (k && k.indexOf("rm.panel.") === 0) kill.push(k);
          }
          for (var j = 0; j < kill.length; j++) localStorage.removeItem(kill[j]);
        } catch (e) { }
        $scope.panel = null;
      };

      $scope.nameProblem = function () {
        var map = {
          too_short: "That name is too short.",
          too_long: "That name is too long.",
          bad_chars: "Letters, numbers, spaces, dot, dash and underscore only.",
          taken: "Somebody already uses that name.",
          already_named: "Your name is already set.",
          bad_code: "A code is six characters.",
          no_match: "No name is held by that code.",
          still_connected: "Whoever holds that name is on the server right now.",
          already_yours: "That is already you."
        };
        return map[$scope.s.nameError] || null;
      };

      $scope.togglePlayers = function () {
        ui("setRosterOpen", !$scope.s.rosterOpen);
        $scope.s.rosterOpen = !$scope.s.rosterOpen;
      };

      $scope.pingClass = function (p) {
        if (p === undefined || p === null || p < 0) return "unknown";
        if (p < 60) return "good";
        if (p < 140) return "fair";
        return "poor";
      };

      $scope.startCapture = function () {
        var t = $scope.newTrack;
        if (!t.name || t.name.trim().length < 2) return;
        $scope.cap("begin", {
          name: t.name.trim(),
          id: t.name.trim(),
          kind: t.kind,
          circuit: !!t.circuit,
          overwrite: !!t.overwrite
        });
      };

      $scope.captureProblem = function () {
        var map = {
          not_allowed: "You need to be an admin to capture a course.",
          already_exists: "A course with that name exists. Tick replace to overwrite it.",
          too_close: "That is on top of the last checkpoint. Drive on a bit.",
          bad_pos: "Could not read the car position.",
          no_vehicle: "Get in a car first.",
          need_two_checkpoints: "A course needs at least two checkpoints.",
          nothing_to_undo: "There is nothing to undo.",
          too_many: "That course is full.",
          bad_id: "Give the course a longer name.",
          bad_level: "The map has not finished loading.",
          no_draft: "No capture is running."
        };
        var e = ($scope.s.capture || {}).lastError;
        return map[e] || (e ? String(e) : null);
      };

      $scope.demoteSelf = function () { ui("demoteSelf"); };
      $scope.exitServer = function () { ui("exitServer"); };
      $scope.clearToast = function () { ui("clearToast"); };

      // ng-repeat over the one message, so track by seq can restart the bar
      $scope.toasts = function () {
        var t = $scope.s.toast;
        return t ? [t] : [];
      };

      $scope.startPerf = function (label) {
        call("raceManager_perf", "start", label);
      };
    }]
  };
}]);
