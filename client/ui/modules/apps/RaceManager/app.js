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

      // How tall this window would be if nothing was holding it in. Measured
      // by letting it go and reading it back, because the content changes as
      // courses are added and a number written down here would go stale.
      function contentHeight() {
        var was = node.style.height;
        node.style.height = "auto";
        var h = node.scrollHeight;
        node.style.height = was;
        return h;
      }

      function place(box) {
        var maxX = window.innerWidth - EDGE;
        var maxY = window.innerHeight - EDGE;
        node.style.left = clamp(box.x, -MIN_W + EDGE, maxX) + "px";
        node.style.top = clamp(box.y, 0, maxY) + "px";
        node.style.transform = "none";
        node.style.right = "auto";
        node.style.bottom = "auto";
        if (box.w) node.style.width = Math.max(MIN_W, box.w) + "px";

        // A window dragged shorter than its content is not a smaller window,
        // it is the same window with the heading scrolled off the top and a
        // bar down the side. That is what he saw on the race picker, and it
        // came back every time because the size was remembered. Pulling the
        // corner up now stops where the content ends. The css max-height still
        // has the last word on a genuinely long list.
        if (box.h) {
          node.style.height = Math.max(MIN_H, contentHeight(), box.h) + "px";
        }
      }

      function remember(box) {
        try { localStorage.setItem(key, JSON.stringify(box)); } catch (e) { }
      }

      var saved = null;
      try { saved = JSON.parse(localStorage.getItem(key)); } catch (e) { }
      if (saved && typeof saved.x === "number") place(saved);

      // What is in a window arrives after it is built: courses land when the
      // server answers, lobby rows come and go. So the fit is checked on every
      // digest rather than once, and a window that would clip grows instead.
      // Nothing is written back, so a bad size on disk heals every time it
      // opens rather than being made permanent by a measurement taken early.
      function unclip() {
        if (!node.style.height) return;
        var room = window.innerHeight * 0.72;
        if (room < MIN_H) return;              // no viewport to measure against
        var need = contentHeight();
        if (need > node.clientHeight + 1) {
          node.style.height = Math.min(Math.max(need, MIN_H), room) + "px";
        }
      }
      scope.$watch(function () { return node.scrollHeight; }, unclip);

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
                   capture: {}, perf: {}, config: {}, race: {}, service: {} };
      $scope.panel = null;
      // ng-if and ng-repeat each make a child scope, so a bare string model is
      // written on the child and the parent never sees it. Anything two way
      // bound has to sit behind a dot.
      $scope.form = { name: "", code: "" };
      $scope.recovering = false;
      $scope.speed = 0;
      $scope.newTrack = { name: "", kind: "race", circuit: true, overwrite: false };
      $scope.entry = { track: null, mode: "controller", laps: 1, raceClass: null };
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
        else if (($scope.s.race || {}).results) $scope.closeResults();
        else if ($scope.panel) $scope.panel = null;
        else if ($scope.s.rosterOpen) ui("setRosterOpen", false);
        else return;
        $scope.$applyAsync();
      }
      document.addEventListener("keydown", onKey);

      $scope.$on("$destroy", function () {
        stopSounds();
        StreamsManager.remove(streams);
        document.removeEventListener("keydown", onKey);
        ui("setRosterOpen", false);
      });

      $scope.$on("streamsUpdate", function (_, s) {
        if (!s || !s.electrics) return;
        var mph = Math.round(Math.abs(s.electrics.wheelspeed || 0) * 2.2369363);
        if (mph !== $scope.speed) {
          $scope.speed = mph;
          // Nobody clicks anything while they are driving, so the menu just
          // rode along over the road. Moving off is the answer to it.
          if (mph >= 1 && $scope.s.lights) ui("closeLights");
          $scope.$applyAsync();
        }
      });

      // open the capture window once when a capture starts, and not again.
      // state arrives up to ten times a second, so reopening it whenever the
      // panel is closed means the close button can never win.
      // ------------------------------------------------------------ sounds
      // The bar's jobs make a noise while the car is held, and only in a race:
      // he asked for it on the clock, not while people mess about in free roam.
      // Steps are chained on the end of the one before rather than fired off a
      // stopwatch, so the pattern still lines up if a clip is swapped for a
      // longer one. The deadline cuts it off when the hold is up, which is what
      // makes "a few times if the hold allows" follow the hold.
      var SOUND_URL = "/ui/modules/apps/RaceManager/sounds/";
      var soundBank = {};
      var soundChain = null;

      function clip(name) {
        var a = soundBank[name];
        if (!a) {
          a = new Audio(SOUND_URL + name + ".mp3");
          a.preload = "auto";
          soundBank[name] = a;
        }
        return a;
      }

      // A press has to make a noise the moment it happens, whether or not
      // anything comes of it. Without this the bar was silent unless a job
      // started inside a run, and every press felt like nothing had happened.
      // Kept out of the bank on purpose so a job starting cannot cut it off.
      var clickSound = null;

      function pressClick() {
        try {
          if (!clickSound) {
            clickSound = new Audio(SOUND_URL + "click.mp3");
            clickSound.preload = "auto";
          }
          clickSound.pause();
          clickSound.currentTime = 0;
          var p = clickSound.play();
          if (p && p.catch) p.catch(function () {});
        } catch (e) {}
      }

      function stopSounds() {
        if (soundChain) { soundChain.dead = true; soundChain = null; }
        for (var k in soundBank) {
          try { soundBank[k].pause(); soundBank[k].currentTime = 0; } catch (e) {}
        }
      }

      function runSounds(steps, endsAt) {
        stopSounds();
        if (!steps || !steps.length) return;
        var chain = { dead: false, i: 0 };
        soundChain = chain;

        function next() {
          if (chain.dead || chain.i >= steps.length) return;
          if (endsAt && Date.now() >= endsAt) return;
          var step = steps[chain.i++];
          var a = clip(step.name);

          // Each step moves the chain on exactly once, on whichever comes
          // first: the clip ending, the clip refusing to play, or a timer the
          // length of the clip. Waiting only on ended left the whole pattern
          // stalled after one note whenever a clip could not be played, and
          // one drill on its own is what an unattached sound sounds like.
          var moved = false;
          function advance() {
            if (moved || chain.dead) return;
            moved = true;
            setTimeout(next, step.gap || 0);
          }

          try {
            a.pause();
            a.currentTime = 0;
            a.playbackRate = step.rate || 1;
            a.onended = advance;
            var p = a.play();
            if (p && p.catch) p.catch(advance);
          } catch (e) { advance(); }

          var secs = (a.duration && isFinite(a.duration)) ? a.duration : 1;
          setTimeout(advance, (secs / (step.rate || 1)) * 1000 + 120);
        }
        next();
      }

      // six bursts for six wheel nuts, a bottle glugging slower than life, and
      // a repair that drills once then hammers and ratchets until time is up
      function jobSounds(which) {
        var steps = [], i;
        if (which === "spare") {
          for (i = 0; i < 6; i++) steps.push({ name: "drill", gap: 380 });
          return steps;
        }
        if (which === "fuel") return [{ name: "fuel", rate: 0.8 }];
        if (which === "repair") {
          steps.push({ name: "drill", gap: 300 });
          for (i = 0; i < 8; i++) {
            steps.push({ name: "hammer", gap: 260 });
            steps.push({ name: "ratchet", gap: 420 });
          }
          return steps;
        }
        return null;   // reposition and re-rack are quiet for now
      }

      var soundJob = null;

      // Outside a run a job is instant, so there is no hold for the pattern to
      // follow and it gets a short window of its own instead. Hearing the
      // tools on an empty server is worth more than keeping them to races.
      var FREE_SOUND_SECS = 4;

      function soundsForState(data) {
        var job = (data && data.service) || {};
        var which = job.which || null;
        if (which === soundJob) return;
        soundJob = which;

        // The job finishing is not a reason to cut the sound: outside a run
        // the server starts and finishes it in the same breath, and stopping
        // here killed the pattern before a note of it was heard. A new job
        // stops the old one, and the deadline stops the rest.
        if (!which) return;

        var secs = (job.hold || 0) > 0 ? job.hold : FREE_SOUND_SECS;
        runSounds(jobSounds(which), Date.now() + secs * 1000);
      }

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

          soundsForState(data);

          var race = (data && data.race) || {};
          if ((race.state === "armed" || race.state === "running") &&
              $scope.panel === "race") $scope.panel = null;

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
        copilot: "CoPilot and Chase arrive in phase 6.",
        challenges: "Challenges arrive in phase 6."
      };

      $scope.buttons = [
        { key: "race",       label: "Race" },
        { key: "records",    label: "Records" },
        { key: "team",       label: "Team" },
        { key: "copilot",    label: "CoPilot" },
        { key: "challenges", label: "Challenges" },
        { key: "options",    label: "Options" },
        { key: "discord",    label: "Discord" }
      ];

      $scope.open = function (key) {
        $scope.panel = ($scope.panel === key) ? null : key;
        if ($scope.panel === "team") call("raceManager_race", "teamGet");
        if ($scope.panel === "records") {
          var id = $scope.recPick.track ||
                   ($scope.s.tracks[0] && $scope.s.tracks[0].id);
          if (id) $scope.recordsFor(id);
        }
      };

      // ------------------------------------------------------------ classes

      // His classes, grouped into the two divisions he announces them under.
      // Built once off the list the server sent: ng-repeat over a freshly
      // made array every digest never settles.
      var classFrom = null, classGroups = [];

      $scope.classGroups = function () {
        var list = ($scope.s.config && $scope.s.config.classes) || [];
        if (list !== classFrom) {
          classFrom = list;
          var groups = [], seen = {};
          for (var i = 0; i < list.length; i++) {
            var name = list[i] && list[i].name;
            if (!name) continue;
            var div = list[i].division || "Other";
            if (!seen[div]) {
              seen[div] = { name: div, classes: [] };
              groups.push(seen[div]);
            }
            seen[div].classes.push(name);
          }
          classGroups = groups;
        }
        return classGroups;
      };

      $scope.anyClasses = function () { return $scope.classGroups().length > 0; };

      // pressing the one you are already in takes you back out of it
      $scope.pickClass = function (name) {
        $scope.entry.raceClass = ($scope.entry.raceClass === name) ? null : name;
      };

      // ------------------------------------------------------------ records

      $scope.recPick = { track: null, raceClass: null };

      $scope.recordsFor = function (id) {
        if (id !== $scope.recPick.track) $scope.recPick.raceClass = null;
        $scope.recPick.track = id;
        ui("getRecords", [id, $scope.recPick.raceClass]);
      };

      // the board only offers a class once somebody has raced one here
      $scope.recordsClassFilter = function (name) {
        $scope.recPick.raceClass = ($scope.recPick.raceClass === name) ? null : name;
        ui("getRecords", [$scope.recPick.track, $scope.recPick.raceClass]);
      };

      $scope.recordClasses = function () {
        var r = $scope.s.records;
        return (r && r.classes) || [];
      };

      $scope.recordsReady = function () {
        var r = $scope.s.records;
        return !!(r && r.id === $scope.recPick.track);
      };

      var MODE_LABEL = { controller: "Controller", wheel: "Wheel" };

      // Built once per payload. Handing ng-repeat a new array of new objects
      // every digest never settles: angular gives up after ten passes and
      // leaves whatever it had not reached showing raw braces.
      var modesFrom = null, modesCache = [];

      $scope.recordModes = function () {
        var r = $scope.s.records;
        if (!r || !r.modes) return [];
        if (r !== modesFrom) {
          modesFrom = r;
          var out = [];
          for (var k in r.modes) {
            if (Object.prototype.hasOwnProperty.call(r.modes, k)) {
              out.push({ key: k, label: MODE_LABEL[k] || k, board: r.modes[k] });
            }
          }
          out.sort(function (a, b) { return a.key < b.key ? -1 : 1; });
          modesCache = out;
        }
        return modesCache;
      };

      $scope.recordsAny = function () {
        return $scope.recordModes().length > 0;
      };

      // whole days are enough for a record book
      $scope.ago = function (at) {
        if (!at) return "";
        var days = Math.floor((Date.now() / 1000 - at) / 86400);
        if (days <= 0) return "today";
        if (days === 1) return "yesterday";
        if (days < 30) return days + "d ago";
        var months = Math.floor(days / 30);
        if (months < 12) return months + "mo ago";
        return Math.floor(months / 12) + "y ago";
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
        { key: "reposition", label: "Reposition", hold: "reposition", pen: "recovery" },
        { key: "spare",      label: "Spare tire", hold: "spareTire",  pen: "flatTire" },
        { key: "repair",     label: "Repair",     hold: "repair",     pen: "repair" },
        { key: "fuel",       label: "Fuel +25%",  hold: "fuel",       pen: null },
        { key: "rerack",     label: "Re-rack",    hold: "rerack",     pen: null, pit: true },
        { key: "lights",     label: "Lights",     hold: null,         pen: null }
      ];

      // Re-rack is only worth offering where it works, so the bar grows a
      // button in the pit and loses it on the way out. The list is cached
      // because ng-repeat compares what it is handed and a fresh array every
      // digest never settles.
      var barCache = null, barPit = null;
      $scope.barButtons = function () {
        var pit = (($scope.s.race || {}).inPit) ? 1 : 0;
        if (pit !== barPit || !barCache) {
          barPit = pit;
          barCache = $scope.bottom.filter(function (b) { return !b.pit || pit === 1; });
        }
        return barCache;
      };

      // how many changes are left before the pit. the server counts them, so
      // an empty rack is known before the button is pressed rather than after
      // a thirty second wait.
      $scope.sparesLeft = function () {
        var n = ($scope.s.service || {}).spares;
        return typeof n === "number" ? n : null;
      };

      $scope.bottomLabel = function (b) {
        if (b.key !== "spare") return b.label;
        var n = $scope.sparesLeft();
        return n === null ? b.label : b.label + " " + n;
      };

      $scope.outOfSpares = function (b) {
        return b.key === "spare" && $scope.sparesLeft() === 0;
      };

      // the host can change any of these on the server without anybody
      // reinstalling, so the button reads them rather than stating them
      $scope.bottomNote = function (b) {
        if ($scope.outOfSpares(b)) return "The rack is empty. Pit and re-rack.";
        var c = $scope.s.config || {};
        var h = (c.holds || {})[b.hold];
        var p = b.pen && (c.penalties || {})[b.pen];
        var bits = [];
        if (h) bits.push(h + " sec hold");
        if (p) bits.push(p + " sec penalty");
        if (b.key === "rerack") bits.push("fills the rack");
        return bits.length ? bits.join(", ") + ", in a run" : "";
      };

      // ------------------------------------------------------------- holds

      var HOLD_LABEL = {
        reposition: "Repositioning", spare: "Fitting the spare",
        repair: "Repairing", fuel: "Fuelling", rerack: "Re-racking"
      };

      $scope.holding = function () {
        var v = $scope.s.service || {};
        return !!v.which && (v.hold || 0) > 0;
      };

      $scope.holdLabel = function () {
        return HOLD_LABEL[($scope.s.service || {}).which] || "Working";
      };

      $scope.holdLeft = function () {
        return Math.max(0, Math.ceil(($scope.s.service || {}).left || 0));
      };

      $scope.holdPct = function () {
        var v = $scope.s.service || {};
        if (!v.hold) return 0;
        var gone = (v.hold - (v.left || 0)) / v.hold * 100;
        return gone < 0 ? 0 : (gone > 100 ? 100 : Math.round(gone));
      };

      $scope.lightItems = [
        { key: "headlights", label: "Headlights" },
        { key: "lightbar",   label: "Lightbar" },
        { key: "fog",        label: "Fog lights" },
        { key: "siren",      label: "Siren" },
        { key: "hazards",    label: "Hazards" },
        { key: "horn",       label: "Horn" },
        { key: "flash",      label: "Flash" }
      ];

      // It used to stay open so lights could be flicked in pairs, and it read
      // as a menu that would not go away. It shuts on the one you picked; the
      // button opens it again if you want another.
      $scope.lightPick = function (l) {
        pressClick();
        call("raceManager_bottombar", "light", l.key);
        ui("closeLights");
      };

      // ------------------------------------------------------------- team
      // Two drivers in the same car model, one result. Every rule about it
      // lives on the server; this only shows what it says and asks.
      $scope.myTeam = function () { return ($scope.s.team || {}).team || null; };
      $scope.teamOffer = function () { return ($scope.s.team || {}).offer || null; };

      // anybody else on the server who is not you. the server refuses the
      // rest, so this does not try to guess who is eligible.
      $scope.teamable = function () {
        var out = [], list = $scope.s.roster || [];
        for (var i = 0; i < list.length; i++) {
          if (list[i].id !== $scope.s.me.id) out.push(list[i]);
        }
        return out;
      };

      $scope.teamAsk = function (p, kind) {
        call("raceManager_race", "teamOffer", p.id, kind);
      };
      $scope.teamAccept  = function () { call("raceManager_race", "teamAccept"); };
      $scope.teamDecline = function () { call("raceManager_race", "teamDecline"); };
      $scope.teamLeave   = function () { call("raceManager_race", "teamLeave"); };

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
        pressClick();
        // reaching past the open menu for another button means you are done
        // with it, so it goes rather than sitting there over the road
        if (b.key !== "lights" && $scope.s.lights) ui("closeLights");
        var fn = {
          reposition: "reposition", spare: "spareTire", repair: "repair",
          fuel: "fuel", rerack: "rerack", lights: "lights"
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
        no_such_race:    "That race is gone.",
        already_started: "That race has already started.",
        already_in_one:  "You are already in a race. Leave it first.",
        not_invited:     "That race is invite only.",
        not_the_host:    "Only the host can do that.",
        no_lobby:        "You are not in a race.",
        course_in_use:   "There is already a race on that course.",
        no_such_player:  "That player is gone.",
        no_such_track:   "That course is gone.",
        course_too_short: "That course has too few checkpoints to race.",
        bad_mode:        "Pick controller or wheel.",
        bad_laps:        "Between one and ninety nine laps.",
        not_a_circuit:   "That course is point to point, so it is one lap.",
        already_running: "You are already on a run. End it first.",
        no_such_class:   "That class is not on the list. Pick another.",
        wrong_car_for_class: "Your car is not allowed in that class.",
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

      // What each penalty was for. The clock used to be handed one number and
      // call all of them cuts, so pressing Reposition once read as a second
      // cut. Kept in this order because a cut is the one you argue about.
      var PENALTY_WORD = {
        missed_gate: ["cut", "cuts"],
        speeding:    ["speeding", "speeding"],
        recovery:    ["reposition", "repositions"],
        flatTire:    ["tire change", "tire changes"],
        repair:      ["repair", "repairs"]
      };
      var PENALTY_ORDER = ["missed_gate", "speeding", "recovery", "flatTire", "repair"];

      var penFrom = null, penText = "";

      $scope.penaltyWords = function () {
        var r = $scope.s.race || {};
        var by = r.penaltyBy;
        if (!r.penalties) return "";
        if (by === penFrom) return penText;
        penFrom = by;

        var parts = [], counted = 0, i, k, n;
        for (i = 0; i < PENALTY_ORDER.length; i++) {
          k = PENALTY_ORDER[i];
          n = by && by[k];
          if (n) {
            counted += n;
            parts.push(n + " " + PENALTY_WORD[k][n === 1 ? 0 : 1]);
          }
        }
        // anything the server started charging that this build has no word for
        var rest = r.penalties - counted;
        if (rest > 0) parts.push(rest + (rest === 1 ? " penalty" : " penalties"));

        penText = parts.join(", ");
        return penText;
      };

      // ------------------------------------------------------------- lobby

      $scope.lobbyCreate = function (open) {
        call("raceManager_race", "createLobby",
          [$scope.entry.track, $scope.entry.mode, $scope.entry.laps, !!open,
           $scope.entry.raceClass]);
      };
      $scope.lobbyJoin  = function (id) { call("raceManager_race", "joinLobby", id); };
      $scope.lobbyLeave = function () { call("raceManager_race", "leaveLobby"); };
      $scope.lobbyStart = function () { call("raceManager_race", "startLobby"); };
      $scope.lobbyInvite = function (pid) { call("raceManager_race", "inviteLobby", pid); };

      // everyone on the server who is not already in the race
      $scope.invitable = function () {
        var l = $scope.s.race.lobby;
        if (!l) return [];
        var inRace = {};
        (l.members || []).forEach(function (m) { inRace[m.id] = true; });
        return ($scope.s.roster || []).filter(function (p) { return !inRace[p.id]; });
      };

      $scope.raceIdle = function () {
        var st = ($scope.s.race || {}).state;
        return !st || st === "idle";
      };

      // armed says a race exists, not that it has begun. nothing is drawn
      // over the road until the clock is running.
      $scope.raceRunning = function () {
        return ($scope.s.race || {}).state === "running";
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
        ui("armRace", [$scope.entry.track, $scope.entry.mode, laps,
                       $scope.entry.raceClass]);
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
