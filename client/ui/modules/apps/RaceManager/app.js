angular.module("beamng.apps")
.directive("raceManager", [function () {
  return {
    templateUrl: "/ui/modules/apps/RaceManager/app.html",
    replace: true,
    restrict: "EA",
    scope: true,

    controller: ["$scope", function ($scope) {

      // everything drawn comes from here. the server owns it, this only mirrors.
      $scope.s = { ready: false, needsName: false, me: {}, roster: [], tracks: [],
                   capture: {}, perf: {}, config: {} };
      $scope.panel = null;
      // ng-if and ng-repeat each make a child scope, so a bare string model is
      // written on the child and the parent never sees it. Anything two way
      // bound has to sit behind a dot.
      $scope.form = { name: "", code: "" };
      $scope.recovering = false;
      $scope.speed = 0;
      $scope.newTrack = { name: "", kind: "race", circuit: true, overwrite: false };

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

      $scope.$on("$destroy", function () {
        StreamsManager.remove(streams);
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
        });
      });

      ui("requestState");

      // which phase each unfinished button lands in. the shell says so rather
      // than looking broken.
      $scope.SOON = {
        race: "Time Trial, Qualifying and Race arrive in phase 2.",
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
      };

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

      $scope.startPerf = function (label) {
        call("raceManager_perf", "start", label);
      };
    }]
  };
}]);
