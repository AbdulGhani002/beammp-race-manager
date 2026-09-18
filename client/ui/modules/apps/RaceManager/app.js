// Where a thing is drawn, in the coordinates its left and top are set in:
// its box's corner taken off the screen position. offsetLeft and offsetTop
// know nothing of the css transform that centres a bar, and a nudge worked
// out from them threw the bottom bar half its width to the right on every
// load, because the bar sat four pixels closer to the edge than the nudge
// allowed.
function rmDrawnAt(node) {
  var r = node.getBoundingClientRect();
  var host = node.offsetParent || node.parentElement;
  var h = host ? host.getBoundingClientRect() : { left: 0, top: 0 };
  return { x: r.left - h.left, y: r.top - h.top, rect: r };
}

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

      function place(box, clampToView) {
        // Positions are relative to the Race Manager host. Always clamp to the
        // visible viewport so a wide-monitor save cannot park a panel off-screen
        // on a smaller display.
        var x = box.x, y = box.y;
        var vw = window.innerWidth || 1280;
        var vh = window.innerHeight || 720;
        if (clampToView !== false) {
          var maxX = vw - EDGE;
          var maxY = vh - EDGE;
          x = clamp(x, -MIN_W + EDGE, maxX);
          y = clamp(y, 0, maxY);
        }
        node.style.left = x + "px";
        node.style.top = y + "px";
        node.style.transform = "none";
        node.style.right = "auto";
        node.style.bottom = "auto";
        if (box.w) node.style.width = Math.min(Math.max(MIN_W, box.w), vw - EDGE) + "px";

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
      if (saved && typeof saved.x === "number") place(saved, true);

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
        var ox = startEvent.clientX, oy = startEvent.clientY;
        // from where the window is drawn: a window still centred by the css
        // transform has an offsetLeft half its width to the right of that,
        // and the first drag used to jump it there
        var at = rmDrawnAt(node);
        var box = { x: at.x, y: at.y, w: node.offsetWidth, h: node.offsetHeight };

        function onMove(e) {
          var dx = e.clientX - ox, dy = e.clientY - oy;
          if (mode === "move") {
            place({ x: box.x + dx, y: box.y + dy, w: box.w, h: box.h }, true);
          } else {
            place({ x: box.x, y: box.y, w: box.w + dx, h: box.h + dy }, true);
          }
        }

        function onUp() {
          document.removeEventListener("mousemove", onMove);
          document.removeEventListener("mouseup", onUp);
          remember({ x: node.offsetLeft, y: node.offsetTop, w: node.offsetWidth, h: node.offsetHeight });
        }

        document.addEventListener("mousemove", onMove);
        document.addEventListener("mouseup", onUp);
      }

      var handle = node.querySelector("h2") || node.querySelector(".rm-players-head")
                   || node.querySelector(".rm-bar-handle");
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
      scope.$on("rmReset", scope.rmResetPanel);
    }
  };
}])

// Somebody else's app, mounted inside this one. The game only loads an app's
// script when that app is placed on a layout, so placing it here means
// loading it here, by the same call the game makes, and then compiling its
// element into the slot. The script is the author's, untouched, so their
// next version drops straight in.
.directive("rmMount", ["$ocLazyLoad", "$compile", "$injector", "$q",
  function ($ocLazyLoad, $compile, $injector, $q) {
  return {
    restrict: "A",
    link: function (scope, element, attrs) {
      var src = attrs.rmMount;
      var directive = attrs.rmDirective;
      // the element the app registers, given as a name so no markup has to
      // live inside an attribute
      var dom = "<" + attrs.rmTag + "></" + attrs.rmTag + ">";
      var node = element[0];
      var child = null;

      // what the game falls back to when the lazy loader will not have it
      function viaScriptTag() {
        return $q(function (resolve, reject) {
          if (document.querySelector("script[src=\"" + src + "\"]")) { resolve(); return; }
          var tag = document.createElement("script");
          tag.src = src;
          tag.async = false;
          tag.onload = function () { resolve(); };
          tag.onerror = function () { reject("failed to load " + src); };
          document.head.appendChild(tag);
        });
      }

      function loaded() {
        if ($injector.has(directive + "Directive")) return $q.when();
        return $ocLazyLoad.load(src, { cache: false, reconfig: true, rerun: true })
          .catch(viaScriptTag)
          .then(function () {
            if (!$injector.has(directive + "Directive")) {
              return $q.reject("nothing called " + directive + " came out of " + src);
            }
          });
      }

      loaded().then(function () {
        child = scope.$new();
        var el = $compile(dom)(child);
        node.appendChild(el[0]);
      }, function (err) {
        console.error("[RaceManager] could not mount " + directive + ": " + err);
        node.classList.add("rm-mount-failed");
      });

      scope.$on("$destroy", function () {
        if (child) { try { child.$destroy(); } catch (e) { } }
      });
    }
  };
}])

// Where a thing that drags itself was left. The Stella moves its own box on
// mousedown, so this only writes the spot down and puts it back next time.
.directive("rmSpot", [function () {
  return {
    restrict: "A",
    link: function (scope, element, attrs) {
      var node = element[0];
      var key = "rm.panel." + attrs.rmSpot;
      var EDGE = 12;

      function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

      function place(x, y) {
        var vw = window.innerWidth || 1280;
        var vh = window.innerHeight || 720;
        var w = node.offsetWidth || 362;
        var h = node.offsetHeight || 240;
        x = clamp(x, EDGE - w + 40, vw - 40);
        y = clamp(y, 0, vh - 40);
        // Must clear bottom/right or the box collapses when top is set.
        node.style.left = x + "px";
        node.style.top = y + "px";
        node.style.right = "auto";
        node.style.bottom = "auto";
        node.style.transform = "none";
      }

      function resetDefault() {
        node.style.left = "";
        node.style.top = "";
        node.style.right = "";
        node.style.bottom = "";
        node.style.transform = "";
      }

      function isOffScreen() {
        var r = node.getBoundingClientRect();
        var vw = window.innerWidth || 1280;
        var vh = window.innerHeight || 720;
        if (r.width < 1 || r.height < 1) return true;
        var visW = Math.min(r.right, vw) - Math.max(r.left, 0);
        var visH = Math.min(r.bottom, vh) - Math.max(r.top, 0);
        return visW < 40 || visH < 40;
      }

      function fit() {
        if (isOffScreen()) {
          try { localStorage.removeItem(key); } catch (e) { }
          resetDefault();
          return;
        }
        var at = rmDrawnAt(node);
        var r = at.rect;
        var vw = window.innerWidth || 1280;
        var vh = window.innerHeight || 720;
        var dx = 0, dy = 0;
        if (r.left < 0) dx = -r.left;
        if (r.right > vw) dx = vw - r.right;
        if (r.top < 0) dy = -r.top;
        if (r.bottom > vh) dy = vh - r.bottom;
        if (dx || dy) place(at.x + dx, at.y + dy);
      }

      var saved = null;
      try { saved = JSON.parse(localStorage.getItem(key)); } catch (e) { }
      if (saved && typeof saved.x === "number" && typeof saved.y === "number") {
        place(saved.x, saved.y);
        setTimeout(fit, 50);
        setTimeout(fit, 400);
      }

      node.addEventListener("mousedown", function () {
        function done() {
          document.removeEventListener("mouseup", done);
          try {
            localStorage.setItem(key, JSON.stringify({
              x: node.offsetLeft, y: node.offsetTop
            }));
          } catch (e) { }
          fit();
        }
        document.addEventListener("mouseup", done);
      });

      window.addEventListener("resize", fit);
      scope.$on("$destroy", function () {
        window.removeEventListener("resize", fit);
      });
      scope.$on("rmReset", function () {
        try { localStorage.removeItem(key); } catch (e) { }
        resetDefault();
      });
      scope.$on("rmFitScreen", fit);
    }
  };
}])

// A bar is dragged from wherever it is taken hold of, and where it ends up is
// remembered the way the Stella's spot is. No handle to find and no corner
// to resize from: a bar is as wide as what is on it.
.directive("rmMove", [function () {
  return {
    restrict: "A",
    link: function (scope, element, attrs) {
      var node = element[0];
      var key = "rm.bar." + attrs.rmMove;
      var EDGE = 16;

      function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

      function viewSize() {
        return {
          w: window.innerWidth || document.documentElement.clientWidth || 1280,
          h: window.innerHeight || document.documentElement.clientHeight || 720
        };
      }

      // Clear absolute coords so CSS (left:50% + translateX) centers the bar again.
      function resetCenter() {
        node.style.left = "";
        node.style.top = "";
        node.style.right = "";
        node.style.bottom = "";
        node.style.transform = "";
      }

      function put(x, y, clampToView) {
        var vs = viewSize();
        var w = node.offsetWidth || 200;
        var h = node.offsetHeight || 40;
        if (clampToView) {
          // Keep at least EDGE px of the bar visible on every side.
          x = clamp(x, EDGE - w + EDGE, vs.w - EDGE);
          y = clamp(y, 0, vs.h - EDGE);
        }
        node.style.left = x + "px";
        node.style.top = y + "px";
        node.style.right = "auto";
        node.style.bottom = "auto";
        node.style.transform = "none";
      }

      function isMostlyOffScreen() {
        var r = node.getBoundingClientRect();
        var vs = viewSize();
        if (r.width < 1 || r.height < 1) return false;
        var visibleW = Math.min(r.right, vs.w) - Math.max(r.left, 0);
        var visibleH = Math.min(r.bottom, vs.h) - Math.max(r.top, 0);
        return visibleW < r.width * 0.4 || visibleH < r.height * 0.4;
      }

      function fitToScreen() {
        if (isMostlyOffScreen()) {
          try { localStorage.removeItem(key); } catch (e) { }
          resetCenter();
          return;
        }
        // Nudge fully into view if partially clipped. Where the css puts a
        // bar is inside the screen already, so a bar at its default is left
        // exactly as it is.
        var at = rmDrawnAt(node);
        var r = at.rect;
        var vs = viewSize();
        var dx = 0, dy = 0;
        if (r.left < 0) dx = -r.left;
        if (r.right > vs.w) dx = vs.w - r.right;
        if (r.top < 0) dy = -r.top;
        if (r.bottom > vs.h) dy = vs.h - r.bottom;
        if (dx || dy) {
          put(at.x + dx, at.y + dy, true);
        }
      }

      var saved = null;
      try { saved = JSON.parse(localStorage.getItem(key)); } catch (e) { }
      if (saved && typeof saved.x === "number" && typeof saved.y === "number") {
        put(saved.x, saved.y, true);
        // After layout settles, verify and re-center if still wrong.
        setTimeout(fitToScreen, 50);
        setTimeout(fitToScreen, 400);
      }

      // The whole bar takes hold, buttons included. Nearly all of a bar is
      // buttons, with five pixels between them and six around, and that
      // sliver was all there was to grab. A press that travels is a drag and
      // the button under it does not fire. A press that stays put is a click.
      var SLACK = 5;
      var dragged = false;

      node.addEventListener("click", function (e) {
        if (!dragged) return;
        dragged = false;
        e.stopPropagation();
        e.preventDefault();
      }, true);

      node.addEventListener("mousedown", function (e) {
        if (e.button !== 0) return;
        var t = e.target;
        while (t && t !== node) {
          var tag = (t.tagName || "").toLowerCase();
          if (tag === "input" || tag === "select") return;
          t = t.parentNode;
        }
        e.preventDefault();
        // from where the bar is drawn, for the same reason as a window
        var at = rmDrawnAt(node);
        var startX = at.x, startY = at.y;
        var mx = e.clientX, my = e.clientY;
        var sx = e.clientX, sy = e.clientY;
        var moving = false;
        dragged = false;
        function move(ev) {
          if (!moving) {
            if (Math.abs(ev.clientX - sx) < SLACK && Math.abs(ev.clientY - sy) < SLACK) return;
            moving = true;
            dragged = true;
          }
          put(startX + (ev.clientX - mx), startY + (ev.clientY - my), true);
        }
        function done() {
          document.removeEventListener("mousemove", move);
          document.removeEventListener("mouseup", done);
          if (!moving) return;
          // Do not remember positions while the HUD editor has the app in a
          // partial box — that is what made bars vanish after leaving edit.
          try {
            var root = document.querySelector(".rm-root");
            var host = root && root.parentElement;
            var hostW = host ? host.clientWidth : window.innerWidth;
            var hostH = host ? host.clientHeight : window.innerHeight;
            if (hostW < window.innerWidth * 0.85 || hostH < window.innerHeight * 0.85) {
              return;
            }
            localStorage.setItem(key, JSON.stringify({
              x: node.offsetLeft, y: node.offsetTop }));
          } catch (er) { }
        }
        document.addEventListener("mousemove", move);
        document.addEventListener("mouseup", done);
      });

      function onResize() { fitToScreen(); }
      window.addEventListener("resize", onResize);
      scope.$on("$destroy", function () {
        window.removeEventListener("resize", onResize);
      });

      scope.$on("rmReset", function () {
        try { localStorage.removeItem(key); } catch (e) { }
        resetCenter();
      });
      scope.$on("rmFitScreen", function () { fitToScreen(); });
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

      // Fit every bar/panel to the current viewport (fixes off-screen positions
      // from a different resolution or a partial app host).
      function fitAllUi() {
        try {
          var root = document.querySelector(".rm-root");
          if (root) {
            root.style.position = "absolute";
            root.style.left = "0";
            root.style.top = "0";
            root.style.right = "0";
            root.style.bottom = "0";
            root.style.width = "100%";
            root.style.height = "100%";
            root.style.maxWidth = "100vw";
            root.style.maxHeight = "100vh";
            root.style.transform = "none";
            root.style.overflow = "visible";
          }
          // Host app cell from BeamNG layout — pin full screen if it drifted
          // (this was the "UI off to the right" case).
          var host = root && root.parentElement;
          for (var i = 0; host && i < 5; i++) {
            var st = window.getComputedStyle(host);
            if (st.position === "absolute" || st.position === "fixed") {
              var left = parseFloat(st.left) || 0;
              var top = parseFloat(st.top) || 0;
              var drifted = Math.abs(left) > 2 || Math.abs(top) > 2
                || (st.width && st.width !== "100%" && parseFloat(st.width) < window.innerWidth * 0.9);
              if (drifted || true) {
                host.style.left = "0px";
                host.style.top = "0px";
                host.style.right = "0px";
                host.style.bottom = "0px";
                host.style.width = "100%";
                host.style.height = "100%";
                host.style.maxWidth = "100vw";
                host.style.maxHeight = "100vh";
                host.style.transform = "none";
                host.style.margin = "0";
              }
              break;
            }
            host = host.parentElement;
          }
        } catch (e) { }
        // After the host is pinned, clamp bars / Stella into the viewport.
        $scope.$broadcast("rmFitScreen");
      }
      function clearUiStorage() {
        try {
          var kill = [];
          for (var i = 0; i < localStorage.length; i++) {
            var k = localStorage.key(i);
            if (!k) continue;
            if (k.indexOf("rm.bar.") === 0 || k.indexOf("rm.panel.") === 0) kill.push(k);
          }
          kill.forEach(function (k) { localStorage.removeItem(k); });
        } catch (e) { }
      }

      function restoreUiLayout(hard) {
        if (hard !== false) clearUiStorage();
        // Reset every bar / panel / Stella to CSS defaults
        $scope.$broadcast("rmReset");
        // Ensure instruments are visible
        try {
          $scope.dash = $scope.dash || { tacho: true, stella: true, clock: false };
          $scope.dash.tacho = true;
          $scope.dash.stella = true;
          localStorage.setItem("rm.dash", JSON.stringify($scope.dash));
        } catch (e) { }
        $scope.s = $scope.s || {};
        $scope.s.rosterOpen = true;
        try { ui("setRosterOpen", true); } catch (e) { }
        $timeout(function () {
          fitAllUi();
          $scope.$broadcast("rmFitScreen");
          $scope.$applyAsync();
        }, 50);
        $timeout(fitAllUi, 400);
        $timeout(fitAllUi, 1000);
      }

      $scope.restoreUiLayout = function () { restoreUiLayout(true); };

      function onRestoreEvent(data) {
        // fit: the box pinned and every bar nudged into view, nothing
        // forgotten. That is what a join and the end of a layout edit ask
        // for; a wipe there lost everybody's positions every time.
        if (data && data.fit) { fitAllUi(); return; }
        var hard = true;
        if (data && data.hard === false) hard = false;
        restoreUiLayout(hard);
      }
      // the same reset, asked from the game side when the chat command could
      // not reach his restore
      $scope.$on("rmResetAsked", function () { restoreUiLayout(true); });

      // From Lua guihooks / CustomEvent / window message
      try {
        $scope.$on("RaceManagerRestoreUi", function (_, data) { onRestoreEvent(data || {}); });
      } catch (e) { }
      function onWinRestore(ev) {
        var d = (ev && ev.detail) || (ev && ev.data) || {};
        if (ev && ev.data && ev.data.type === "RaceManagerRestoreUi") d = ev.data;
        onRestoreEvent(d);
      }
      window.addEventListener("RaceManagerRestoreUi", onWinRestore);
      window.addEventListener("message", function (ev) {
        if (ev && ev.data && (ev.data.type === "RaceManagerRestoreUi" || ev.data.action === "restoreUi")) {
          onRestoreEvent(ev.data);
        }
      });

      $timeout(fitAllUi, 0);
      $timeout(fitAllUi, 300);
      $timeout(fitAllUi, 1200);
      // Keep fitting for a while after load — covers post-edit layout swaps
      var fitTicks = 0;
      var fitTimer = setInterval(function () {
        fitAllUi();
        fitTicks++;
        if (fitTicks > 40) clearInterval(fitTimer); // ~20s at 500ms
      }, 500);
      window.addEventListener("resize", fitAllUi);
      $scope.$on("$destroy", function () {
        window.removeEventListener("resize", fitAllUi);
        window.removeEventListener("RaceManagerRestoreUi", onWinRestore);
        clearInterval(fitTimer);
      });

      // everything drawn comes from here. the server owns it, this only mirrors.
      $scope.s = { ready: false, needsName: false, me: {}, roster: [], tracks: [],
                   capture: {}, perf: {}, config: {}, race: {}, service: {} };
      $scope.speed = 0;
      $scope.panel = null;
      // ng-if and ng-repeat each make a child scope, so a bare string model is
      // written on the child and the parent never sees it. Anything two way
      // bound has to sit behind a dot.
      $scope.form = { name: "", code: "" };
      $scope.recovering = false;
      $scope.speed = 0;
      $scope.newTrack = { name: "", kind: "race", circuit: true, overwrite: false };
      $scope.entry = { track: null, mode: "controller", laps: 1, raceClass: null, official: false, officialName: "" };

      // The instruments on the dash, on unless switched off. A choice about
      // your own screen, so it lives with the window positions and never
      // goes near the server.
      var DASH_KEY = "rm.dash";
      // The clock over the road is off unless asked for. He would rather the
      // penalties turn up on the results than sit on the screen during a run.
      $scope.dash = { tacho: true, stella: true, clock: false };
      try {
        var savedDash = JSON.parse(localStorage.getItem(DASH_KEY));
        if (savedDash && typeof savedDash === "object") {
          if (typeof savedDash.tacho === "boolean") $scope.dash.tacho = savedDash.tacho;
          if (typeof savedDash.stella === "boolean") $scope.dash.stella = savedDash.stella;
          if (typeof savedDash.clock === "boolean") $scope.dash.clock = savedDash.clock;
        }
      } catch (e) { }

      $scope.dashToggle = function (which) {
        $scope.dash[which] = !$scope.dash[which];
        try { localStorage.setItem(DASH_KEY, JSON.stringify($scope.dash)); } catch (e) { }
      };
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

      // The app's box is meant to be the whole screen, and the game side puts
      // it there when the level loads. A layout edited afterwards, or a game
      // that restored some other layout, can leave it a smaller box in the
      // middle with the bars stuck inside it. fitAllUi pins the box from in
      // here, which is what you see; this asks the game side to mend the
      // layout file as well, so it is right next time too. Once a minute at
      // most, so an open layout editor is not fought with.
      // The game keeps its layout in em, and only the page knows how big
      // the screen is in em: its width and height over the root font size,
      // which is what the interface scale sets. Those go with the ask, so
      // the layout is written at exactly the screen, whatever the scale.
      function askForWholeScreen() {
        var fontPx = 16;
        try { fontPx = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16; } catch (e) { }
        var wEm = Math.round(window.innerWidth / fontPx * 100) / 100;
        var hEm = Math.round(window.innerHeight / fontPx * 100) / 100;
        if (!(wEm > 0) || !(hEm > 0)) { call("raceManager_layout", "arm"); return; }
        call("raceManager_layout", "arm", [wEm, hEm]);
      }
      $scope.askForWholeScreen = askForWholeScreen;

      var boxAskedAt = 0;
      function watchBox() {
        var root = document.querySelector(".rm-root");
        if (!root) return;
        var b = root.getBoundingClientRect();
        if (!(b.width > 0) || !(window.innerWidth > 0)) return;
        var off = Math.abs(b.left) > 4 || Math.abs(b.top) > 4
               || Math.abs(b.width - window.innerWidth) > 4
               || Math.abs(b.height - window.innerHeight) > 4;
        if (!off) return;
        var now = Date.now();
        if (now - boxAskedAt < 60000) return;
        boxAskedAt = now;
        askForWholeScreen();
      }
      var boxTimer = setInterval(watchBox, 3000);
      $scope.$on("$destroy", function () { clearInterval(boxTimer); });

      // the car has to be stopped for the bottom bar. electrics is already
      // streamed to the ui by the game, so reading it here costs us no lua.
      var streams = ["electrics"];
      StreamsManager.add(streams);

      // Escape shuts the top thing that is open, so there is one way out of
      // everything on screen and not just the panels with a close button.
      function onKey(e) {
        if (e.key !== "Escape" && e.keyCode !== 27) return;
        // Player list is toggled only by the Players button — Escape never closes it.
        if ($scope.s.lights) ui("closeLights");
        else if (($scope.s.race || {}).results) $scope.closeResults();
        else if ($scope.panel) $scope.panel = null;
        else return;
        $scope.$applyAsync();
      }
      document.addEventListener("keydown", onKey);

      $scope.$on("$destroy", function () {
        stopSounds();
        StreamsManager.remove(streams);
        document.removeEventListener("keydown", onKey);
        // Leave rosterOpen alone — list stays open across app reloads unless toggled.
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
          if (!data) return;
          // Always keep the player list open.
          data.rosterOpen = true;
          // New roster array reference so ng-repeat always refreshes on joins.
          if (data.roster && !Array.isArray(data.roster)) {
            var arr = [];
            angular.forEach(data.roster, function (row) { if (row) arr.push(row); });
            data.roster = arr;
          } else if (Array.isArray(data.roster)) {
            data.roster = data.roster.map(function (row) {
              return row ? {
                id: row.id, name: row.name, level: row.level, guest: !!row.guest,
                speed: row.speed, ping: row.ping, role: row.role, model: row.model,
                queued: !!row.queued
              } : row;
            });
          } else {
            data.roster = [];
          }
          $scope.s = data;
          $scope.rosterStamp = (data.rosterSeq || 0) + ":" + (data.roster.length || 0);

          var capturing = data && data.capture && data.capture.active;
          if (!capturing) capturePanelShown = false;

          if (capturing && !capturePanelShown && $scope.panel === null) {
            $scope.panel = "capture";
            capturePanelShown = true;
          }

          soundsForState(data);

          var toast = data && data.toast && (data.toast.text || data.toast.msg || data.toast);
          if (typeof toast === "string") {
            if (/challenge posted/i.test(toast) || /challenge changed/i.test(toast)) {
              $scope.chForm = null;
              $scope.chFormBusy = false;
              $scope.chFormError = "";
            } else if ($scope.chFormBusy && /did not work|not posted|not saved|only admin|pick a course|tier|daily challenges|weekly challenges/i.test(toast)) {
              $scope.chFormBusy = false;
              $scope.chFormError = toast;
            }
          }

          var race = (data && data.race) || {};
          if ((race.state === "armed" || race.state === "running") &&
              $scope.panel === "race") $scope.panel = null;

          // Top of the current-map list (most gates). Never keep a course
          // from another map selected just because it arrived first.
          var here = $scope.trackList() || [];
          var stillHere = false;
          if ($scope.entry.track) {
            for (var ti = 0; ti < here.length; ti++) {
              if (here[ti].id === $scope.entry.track) { stillHere = true; break; }
            }
          }
          if ((!stillHere || !$scope.entry.track) && here.length) {
            $scope.entry.track = here[0].id;
          }
        });
      });

      ui("requestState");

      // ------------------------------------------------------------ language
      // Two languages, kept small: the bars, the panel titles and the new
      // panels. Everything not in the table stays English, which is what he
      // said he could live with. Spanish because his Stella came in it.
      var LANG_KEY = "rm.lang";
      var WORDS = {
        en: {
          race: "Race", records: "Records", team: "Team", copilot: "CoPilot",
          challenges: "Challenges", options: "Options", discord: "Discord", players: "Players",
          "players.ontrack": "On track", "board.live": "Live",
          endrace: "End race", close: "close", back: "Back", accept: "Accept", nothanks: "No thanks",
          nobody: "Nobody else is on the server yet.", edit: "Edit", delete: "Delete",
          remove: "Remove", save: "Save", name: "Name", course: "Course", lap: "lap", laps: "laps",
          now: "Now", on: "On", off: "Off", drivingwith: "Driving with", controller: "Controller",
          wheel: "Wheel", language: "Language", tracking: "XP and challenge tracking",
          "language_note": "The whole Race Manager switches to this language.",
          "opt.courses": "Course tools",
          "opt.capture": "Checkpoint capture",
          "opt.staff": "Drivers and staff",
          "opt.staff.note": "Click a driver. Staff and admins can mark courses and post challenges. Only you can change roles or clear records. Admins cannot demote anyone.",
          "opt.launchall": "Launch a challenge for everyone", "opt.launchall.note": "Picks a live challenge and starts an attempt for every connected driver right now.", "opt.nolivechallenges": "No live challenges right now.", "opt.launchall.go": "Launch everyone",
          "opt.nodrivers": "No named drivers yet.",
          "opt.player": "Player",
          "opt.makestaff": "Staff",
          "opt.makeadmin": "Admin",
          "opt.kick": "Kick", "opt.racekick": "Kick from race",
          "opt.ban": "Ban",
          "opt.clearrec": "Clear records",
          "opt.framerate": "Frame rate",
          "opt.dash": "Dash",
          "opt.windows": "Windows",
          "opt.resetwindows": "Put the windows back",
          "opt.demote": "Demote myself",
          "opt.leave": "Leave server",
          "opt.unranked": "unranked, results are not recorded",
          "level": "level",
          "tracking_note": "Off means a run counts for nothing: no XP, no challenge time. For practice.",
          "cp.watching": "Watching", "cp.stop": "Stop watching",
          "cp.camera": "You are in their car. C changes the camera: CoPilot from the seat, Chase from behind.",
          "cp.waiting": "Their car has not loaded here yet. A moment.",
          "cp.watchers": "Watching you", "cp.sendhome": "Send them back to their cars",
          "cp.asks": "wants to watch you", "cp.invites": "invited you to watch them",
          "cp.hint": "Invite somebody to ride with you, or ask to watch a driver. Both sides have to say yes. TAB does not switch cars here; this does.",
          "cp.who": "Somebody on the server", "cp.invite": "Invite", "cp.request": "Ask to watch",
          "cp.invite.tip": "Come and watch me", "cp.request.tip": "May I watch you",
          "ch.hint": "Daily and weekly time attacks. Beat a time on the ladder and the XP is yours, once, with the difference paid when you climb higher. Teams cannot enter.",
          "ch.trackingoff": "Your tracking is off under Options, so you cannot enter one.",
          "ch.none": "Nothing posted yet.", "ch.new": "Post a challenge", "ch.daily": "daily",
          "ch.weekly": "weekly", "ch.classes": "Classes", "ch.anyclass": "Any class",
          "ch.ladder": "The ladder", "ch.under": "Under", "ch.yours": "Your best", "ch.rung": "tier",
          "ch.norung": "outside the ladder", "ch.board": "The board", "ch.noone": "Nobody has finished it yet.",
          "ch.enteras": "Enter as", "ch.enter": "Enter and go to the grid", "ch.endnow": "End it now",
          "ch.change": "Change the challenge", "ch.post": "Post a challenge", "ch.kind": "Daily or weekly",
          "ch.classes.note": "none picked means any class", "ch.ladder.note": "a time as 1:32.43 and the XP it pays",
          "ch.addrung": "Add a tier", "ch.start": "Starts", "ch.in1h": "In 1 hour", "ch.in6h": "In 6 hours",
          "ch.in24h": "Tomorrow", "ch.postit": "Post it",
          "ch.live": "live", "ch.scheduled": "starts in", "ch.ended": "ended", "ch.left": "left",
          "ch.pickclass": "Pick the class you are entering as.", "ch.notlive": "This one is not live.",
          "ch.needtracking": "Turn tracking on under Options first.",
          "ch.p.name": "It needs a name.", "ch.p.track": "Pick a course.", "ch.p.tiers": "Give it at least one tier.",
          "ch.p.time": "A tier's time reads like 0:01:32.43 (hours:minutes:seconds).", "ch.p.xp": "XP is a whole number, zero or more.",
          "ch.daily.title": "Daily challenges", "ch.weekly.title": "Weekly challenges", "ch.nonekind": "None right now.",
          "ch.when": "When", "ch.description": "Description", "ch.description.note": "a few lines, shown under the name",
          "ch.ends": "ends in",
          "ch.style": "Style", "ch.style.laptime": "Lap Time", "ch.style.speed": "Top Speed",
          "ch.style.gforce": "G-Force", "ch.style.damage": "Damage & Distance",
          "ch.style.longjump": "Long Jump", "ch.style.distance": "Distance",
          "ch.ladder.note.laptime": "a time as 0:01:32.43 (hours:minutes:seconds) and the XP it pays",
          "ch.ladder.note.speed": "an mph to reach and the XP it pays",
          "ch.ladder.note.gforce": "a peak g to hit and the XP it pays",
          "ch.ladder.note.damage": "a damage/distance score to beat and the XP it pays",
          "ch.ladder.note.longjump": "a distance or height in feet and the XP it pays",
          "ch.ladder.note.distance": "a distance in miles and the XP it pays",
          "ch.timelimit": "Time limit", "ch.timelimit.none": "This style has no time limit; the run's own finish line ends it.",
          "ch.timelimit.optional": "Optional. Leave blank for no cap.",
          "ch.timelimit.required": "Required for this style. Reads as hours:minutes:seconds, e.g. 0:00:30.00.",
          "ch.measure": "Measure", "ch.measure.distance": "Distance", "ch.measure.height": "Height",
          "ch.p.timelimit": "The time limit reads like 0:00:30.00 and has to be between five seconds and one hour.",
          "ch.p.value": "A tier's value has to be above zero.",
          "ch.atleast": "At least",
          "ch.roam": "Course", "ch.roam.free": "Free roam", "ch.roam.course": "Use a course",
          "ch.roam.free.note": "No course picked: the attempt starts wherever the driver is the moment they enter, and ends on the time limit or when they choose to stop.",
          "ch.roam.free.tag": "Free roam — drive anywhere",
          "ch.roam.notimelimit": "No time limit — stop when you're ready",
          "ch.chud.peak": "Peak", "ch.chud.next": "Next:", "ch.chud.pts": "pts",
          "ch.chud.damage": "damage", "ch.chud.airborne": "AIRBORNE", "ch.chud.bestft": "ft best",
          "ch.chud.high": "high", "ch.chud.stop": "Stop attempt",
          "ch.cr.suspect": "The clock could not vouch for part of this attempt, so it was not scored.",
          "ch.cr.noscore": "Nothing to score from that attempt.",
          "ch.cr.score": "Score", "ch.cr.previous": "Previous best", "ch.cr.attempt": "Attempt",
          "ch.cr.others": "Your other challenges", "ch.cr.again": "Go again", "ch.cr.close": "Close",
          "ch.cr.improved": "New personal best!",
          "ch.cr.completionxp": "for finishing", "ch.cr.ladderxp": "from the ladder",
          "ch.cr.ladderdecay": "(repeats pay a little less each time)",
          "ch.cr.ladderused": "this challenge's ladder has nothing left to pay you — still yours to run, just not for more XP",
          "ch.cr.level": "Level",
          "ch.cr.jumps": "Jumps this attempt", "ch.cr.jumpdist": "Distance", "ch.cr.jumphigh": "Height", "ch.cr.jumpscore": "Score",
        },
        es: {
          race: "Carrera", records: "Récords", team: "Equipo", copilot: "Copiloto",
          challenges: "Retos", options: "Opciones", discord: "Discord", players: "Pilotos",
          "players.ontrack": "En pista", "board.live": "En vivo",
          endrace: "Terminar", close: "cerrar", back: "Volver", accept: "Aceptar", nothanks: "No, gracias",
          nobody: "Todavía no hay nadie más en el servidor.", edit: "Editar", delete: "Borrar",
          remove: "Quitar", save: "Guardar", name: "Nombre", course: "Circuito", lap: "vuelta", laps: "vueltas",
          now: "Ahora", on: "Sí", off: "No", drivingwith: "Conduces con", controller: "Mando",
          wheel: "Volante", language: "Idioma", tracking: "Registro de XP y retos",
          "language_note": "Todo el Race Manager cambia a este idioma.",
          "opt.courses": "Herramientas de circuito",
          "opt.capture": "Captura de checkpoints",
          "opt.staff": "Pilotos y staff",
          "opt.staff.note": "Pulsa un piloto. Staff y admin pueden marcar circuitos y publicar retos. Solo tú cambias roles o borras récords. Un admin no puede bajar a nadie.",
          "opt.launchall": "Lanzar un reto para todos", "opt.launchall.note": "Elige un reto activo y empieza un intento para cada piloto conectado ahora mismo.", "opt.nolivechallenges": "No hay retos activos ahora mismo.", "opt.launchall.go": "Lanzar a todos",
          "opt.nodrivers": "Aún no hay pilotos con nombre.",
          "opt.player": "Piloto",
          "opt.makestaff": "Staff",
          "opt.makeadmin": "Admin",
          "opt.kick": "Expulsar", "opt.racekick": "Expulsar de la carrera",
          "opt.ban": "Banear",
          "opt.clearrec": "Borrar récords",
          "opt.framerate": "Fotogramas",
          "opt.dash": "Cuadro",
          "opt.windows": "Ventanas",
          "opt.resetwindows": "Volver a colocar las ventanas",
          "opt.demote": "Quitarme el cargo",
          "opt.leave": "Salir del servidor",
          "opt.unranked": "sin rango, los resultados no se guardan",
          "level": "nivel",
          "tracking_note": "En No, una carrera no cuenta para nada: ni XP ni tiempo de reto. Para practicar.",
          "cp.watching": "Viendo a", "cp.stop": "Dejar de ver",
          "cp.camera": "Estás en su coche. C cambia la cámara: Copiloto desde el asiento, Persecución desde atrás.",
          "cp.waiting": "Su coche aún no ha cargado aquí. Un momento.",
          "cp.watchers": "Te están viendo", "cp.sendhome": "Devolverlos a sus coches",
          "cp.asks": "quiere verte", "cp.invites": "te invita a verle",
          "cp.hint": "Invita a alguien a ir contigo, o pide ver a un piloto. Los dos tienen que decir que sí. TAB no cambia de coche aquí; esto sí.",
          "cp.who": "Alguien en el servidor", "cp.invite": "Invitar", "cp.request": "Pedir ver",
          "cp.invite.tip": "Ven a verme", "cp.request.tip": "¿Puedo verte?",
          "ch.hint": "Contrarrelojes diarias y semanales. Baja de un tiempo de la escalera y el XP es tuyo, una vez, con la diferencia al subir. Los equipos no entran.",
          "ch.trackingoff": "Tienes el registro apagado en Opciones, así que no puedes entrar.",
          "ch.none": "Aún no hay nada.", "ch.new": "Publicar un reto", "ch.daily": "diario",
          "ch.weekly": "semanal", "ch.classes": "Clases", "ch.anyclass": "Cualquier clase",
          "ch.ladder": "La escalera", "ch.under": "Menos de", "ch.yours": "Tu mejor", "ch.rung": "nivel",
          "ch.norung": "fuera de la escalera", "ch.board": "La tabla", "ch.noone": "Nadie lo ha terminado aún.",
          "ch.enteras": "Entrar como", "ch.enter": "Entrar e ir a la parrilla", "ch.endnow": "Terminarlo ya",
          "ch.change": "Cambiar el reto", "ch.post": "Publicar un reto", "ch.kind": "Diario o semanal",
          "ch.classes.note": "sin elegir, cualquier clase", "ch.ladder.note": "un tiempo como 1:32.43 y el XP que paga",
          "ch.addrung": "Añadir nivel", "ch.start": "Empieza", "ch.in1h": "En 1 hora", "ch.in6h": "En 6 horas",
          "ch.in24h": "Mañana", "ch.postit": "Publicar",
          "ch.live": "en marcha", "ch.scheduled": "empieza en", "ch.ended": "terminado", "ch.left": "quedan",
          "ch.pickclass": "Elige la clase con la que entras.", "ch.notlive": "Este no está en marcha.",
          "ch.needtracking": "Enciende el registro en Opciones primero.",
          "ch.p.name": "Necesita un nombre.", "ch.p.track": "Elige un circuito.", "ch.p.tiers": "Dale al menos un nivel.",
          "ch.p.time": "El tiempo de un nivel se escribe 0:01:32.43 (horas:minutos:segundos).", "ch.p.xp": "El XP es un número entero, cero o más.",
          "ch.daily.title": "Retos diarios", "ch.weekly.title": "Retos semanales", "ch.nonekind": "Ninguno ahora mismo.",
          "ch.when": "Cuándo", "ch.description": "Descripción", "ch.description.note": "unas líneas, bajo el nombre",
          "ch.ends": "termina en",
          "ch.style": "Estilo", "ch.style.laptime": "Tiempo por vuelta", "ch.style.speed": "Velocidad máxima",
          "ch.style.gforce": "Fuerza G", "ch.style.damage": "Daño y distancia",
          "ch.style.longjump": "Salto de longitud", "ch.style.distance": "Distancia",
          "ch.ladder.note.laptime": "un tiempo como 0:01:32.43 (horas:minutos:segundos) y el XP que paga",
          "ch.ladder.note.speed": "un mph a alcanzar y el XP que paga",
          "ch.ladder.note.gforce": "un pico de g a alcanzar y el XP que paga",
          "ch.ladder.note.damage": "una puntuación de daño/distancia a superar y el XP que paga",
          "ch.ladder.note.longjump": "una distancia o altura en pies y el XP que paga",
          "ch.ladder.note.distance": "una distancia en millas y el XP que paga",
          "ch.timelimit": "Límite de tiempo", "ch.timelimit.none": "Este estilo no tiene límite de tiempo; la propia meta del recorrido lo termina.",
          "ch.timelimit.optional": "Opcional. Déjalo en blanco para no poner límite.",
          "ch.timelimit.required": "Obligatorio para este estilo. Se escribe horas:minutos:segundos, por ejemplo 0:00:30.00.",
          "ch.measure": "Medida", "ch.measure.distance": "Distancia", "ch.measure.height": "Altura",
          "ch.p.timelimit": "El límite de tiempo se escribe 0:00:30.00 y debe estar entre cinco segundos y una hora.",
          "ch.p.value": "El valor de un nivel tiene que ser mayor que cero.",
          "ch.atleast": "Al menos",
          "ch.roam": "Circuito", "ch.roam.free": "Recorrido libre", "ch.roam.course": "Usar un circuito",
          "ch.roam.free.note": "Sin circuito elegido: el intento empieza donde esté el piloto en el momento de entrar, y termina con el límite de tiempo o cuando decida parar.",
          "ch.roam.free.tag": "Recorrido libre — conduce donde quieras",
          "ch.roam.notimelimit": "Sin límite de tiempo — para cuando quieras",
          "ch.chud.peak": "Pico", "ch.chud.next": "Siguiente:", "ch.chud.pts": "pts",
          "ch.chud.damage": "daño", "ch.chud.airborne": "EN EL AIRE", "ch.chud.bestft": "pies mejor",
          "ch.chud.high": "de alto", "ch.chud.stop": "Terminar intento",
          "ch.cr.suspect": "El reloj no pudo dar fe de parte de este intento, así que no se puntuó.",
          "ch.cr.noscore": "Nada que puntuar de ese intento.",
          "ch.cr.score": "Puntuación", "ch.cr.previous": "Mejor anterior", "ch.cr.attempt": "Intento",
          "ch.cr.others": "Tus otros retos", "ch.cr.again": "Otra vez", "ch.cr.close": "Cerrar",
          "ch.cr.improved": "¡Nuevo récord personal!",
          "ch.cr.completionxp": "por terminar", "ch.cr.ladderxp": "de la escalera",
          "ch.cr.ladderdecay": "(las repeticiones pagan un poco menos cada vez)",
          "ch.cr.ladderused": "la escalera de este reto ya no tiene más para pagarte — sigue siendo tuya para correr, solo que sin más XP",
          "ch.cr.level": "Nivel",
          "ch.cr.jumps": "Saltos de este intento", "ch.cr.jumpdist": "Distancia", "ch.cr.jumphigh": "Altura", "ch.cr.jumpscore": "Puntaje",
        }
      };
      $scope.lang = "en";
      try { if (WORDS[localStorage.getItem(LANG_KEY)]) $scope.lang = localStorage.getItem(LANG_KEY); } catch (e) { }
      $scope.t = function (key) {
        var d = WORDS[$scope.lang] || WORDS.en;
        return d[key] != null ? d[key] : (WORDS.en[key] != null ? WORDS.en[key] : key);
      };
      $scope.setLang = function (l) {
        if (!WORDS[l]) return;
        $scope.lang = l;
        try { localStorage.setItem(LANG_KEY, l); } catch (e) { }
      };

      $scope.buttons = [
        { key: "race",       labelKey: "race" },
        { key: "records",    labelKey: "records" },
        { key: "team",       labelKey: "team" },
        { key: "copilot",    labelKey: "copilot" },
        { key: "challenges", labelKey: "challenges" },
        { key: "options",    labelKey: "options" },
        { key: "discord",    labelKey: "discord" }
      ];

      $scope.open = function (key) {
        // while a race is on, the Race button is the End race button. the
        // window it would open only had that one button in it anyway.
        if (key === "race" && $scope.raceActive()) { $scope.endRace(); return; }
        $scope.panel = ($scope.panel === key) ? null : key;
        if ($scope.panel === "team") call("raceManager_race", "teamGet");
        if ($scope.panel === "copilot") {
          call("raceManager_copilot", "get");
          ui("keepRoster");
        }
        if ($scope.panel === "challenges") { $scope.chOpen = null; $scope.chForm = null; ui("challengesGet"); }
        if ($scope.panel === "options" && $scope.s && $scope.s.isStaff) {
          // the drivers-and-staff list and the challenge launcher both
          // live in Options now (staff and up, not just the owner), but
          // this fetch was still gated to isOwner and only ever asked for
          // the driver list -- the challenge launcher's picker had nothing
          // to show unless the Challenges tab happened to have been opened
          // first in the same session, which is why "launch a challenge
          // for everyone" could look empty or broken with no error at all.
          bngApi.engineLua(
            "pcall(function() " +
            "local u = extensions.raceManager_ui; " +
            "if u and type(u.getDrivers) == 'function' then u.getDrivers() end; " +
            "end)"
          );
          ui("challengesGet");
        }
        if ($scope.panel === "records") {
          $scope.recOpen = false;
          $scope.drvOpen = false;
          bngApi.engineLua(
            "pcall(function() " +
            "local u = extensions.raceManager_ui; " +
            "if u and type(u.getDrivers) == 'function' then u.getDrivers(); return end; " +
            "if extensions.raceManager_net then extensions.raceManager_net.send('profile.list', {}) end; " +
            "end)"
          );
          var last = $scope.lastRace();
          if (last && last.track && !$scope.recPick.track) $scope.recordsFor(last.track);
          else if ($scope.recPick.track) $scope.recordsFor($scope.recPick.track);
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

      $scope.recOpen = false;
      $scope.recDetail = null;
      $scope.drvOpen = false;
      $scope.drvLocal = null;

      $scope.lastRace = function () {
        var r = $scope.s.race || {};
        return r.lastResults || r.results || null;
      };

      $scope.resultForName = function (name, key) {
        var last = $scope.lastRace();
        if (!last || !last.finished) return null;
        var i, e;
        for (i = 0; i < last.finished.length; i++) {
          e = last.finished[i];
          if ((name && e.name === name) || (key && e.key === key)) return e;
        }
        return null;
      };

      $scope.modeLabel = function (m) {
        if (m === "wheel") return "Wheel";
        if (m === "controller") return "Controller";
        return m || "";
      };

      $scope.driverRows = function () {
        var seen = {};
        var byName = {};
        var out = [];
        function add(d) {
          if (!d || !d.name) return;
          var key = String(d.key || d.id || d.name);
          var existing = byName[d.name];
          if (existing) {
            // a driver known from before (profile.list, no live session)
            // and the same driver currently connected (roster.delta, has a
            // live pid) can both show up here; whichever passes first
            // wins the row, but a pid from either pass is worth keeping --
            // it's what a "kick from race" action needs, and only the
            // roster ever has one
            if (d.id != null && existing.pid == null) existing.pid = d.id;
            return;
          }
          if (seen[key]) return;
          seen[key] = true;
          var row = {
            key: d.key || d.id || d.name,
            name: d.name,
            level: d.level || 1,
            xp: d.xp || 0,
            role: d.role || "player",
            pid: d.id != null ? d.id : null
          };
          byName[d.name] = row;
          out.push(row);
        }
        angular.forEach($scope.s.drivers || [], add);
        angular.forEach($scope.s.roster || [], add);
        out.sort(function (a, b) { return (b.xp || 0) - (a.xp || 0); });
        return out;
      };

      function mergeRun(base, extra) {
        var out = angular.extend({}, base || {});
        if (!extra) return out;
        var k;
        for (k in extra) {
          if (Object.prototype.hasOwnProperty.call(extra, k) && extra[k] != null && extra[k] !== "") {
            out[k] = extra[k];
          }
        }
        return out;
      }

      $scope.openRecordRow = function (mode, row) {
        if (!row) return;
        $scope.drvOpen = false;
        $scope.recOpen = true;
        var fromLast = $scope.resultForName(row.name, row.key);
        $scope.recDetail = mergeRun({
          name: row.name,
          mode: (mode && mode.label) || row.mode,
          pos: row.pos,
          corrected: row.corrected,
          clean: row.clean,
          class: row.class,
          at: row.at,
          vehicle: row.vehicle,
          laps: row.laps,
          key: row.key,
          trackName: ($scope.s.records && $scope.s.records.id) ? null : null
        }, fromLast);
        if (!$scope.recDetail.trackName && $scope.lastRace()) {
          $scope.recDetail.trackName = $scope.lastRace().trackName;
        }
      };
      $scope.recShown = function () { return $scope.recDetail; };
      $scope.recBack = function () { $scope.recOpen = false; $scope.recDetail = null; };

      $scope.openResultRecord = function (e) {
        if (!e) return;
        $scope.panel = "records";
        $scope.drvOpen = false;
        $scope.recOpen = true;
        $scope.recDetail = angular.extend({
          trackName: ($scope.lastRace() || {}).trackName,
          mode: e.mode
        }, e);
        if (e.track || ($scope.lastRace() && $scope.lastRace().track)) {
          $scope.recordsFor(e.track || $scope.lastRace().track);
        }
      };

      $scope.openDriver = function (key, name) {
        $scope.recOpen = false;
        $scope.drvOpen = true;
        $scope.drvLocal = { key: key, name: name || key, pending: true };
        ui("getProfile", { key: key, name: name || key });
      };
      $scope.drvBack = function () { $scope.drvOpen = false; $scope.drvLocal = null; };
      $scope.drvShown = function () {
        var p = $scope.s.profile;
        var loc = $scope.drvLocal;
        var out = loc || p;
        if (p && loc) {
          var same = (p.key && loc.key && String(p.key) === String(loc.key))
                  || (p.name && loc.name && String(p.name) === String(loc.name));
          out = same ? mergeRun(loc, p) : (p.missing ? loc : mergeRun(loc, p));
        } else if (p) {
          out = p;
        }
        if (!out) return null;
        if (out.xpNeed == null || out.xpNeed === 0) {
          var xp = Number(out.xp) || 0;
          out.xpNeed = 750;
          out.xpInto = xp;
          out.xpPct = Math.max(0, Math.min(100, Math.floor((xp / 750) * 100)));
        }
        if (out.miles != null || out.xpNeed) out.pending = false;
        return out;
      };

      $scope.openPlayer = function (p) {
        if (!p) return;
        if ($scope.isQueued(p)) {
          // Apply their BeamMP spawn queue without dropping CoPilot if we are watching them.
          ui("takePlayerQueue", { id: p.id });
          p.queued = false;
          return;
        }
        $scope.panel = "records";
        $scope.recOpen = false;
        $scope.drvOpen = true;
        $scope.drvLocal = {
          key: p.key || p.id, name: p.name, level: p.level,
          xp: p.xp || 0, pending: true
        };
        ui("queuePlayerThenProfile", { id: p.id, key: p.key, name: p.name });
        ui("getProfile", { key: p.key || p.id, id: p.id, name: p.name });
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
        // one value, spread when it is a list. two bare arguments dropped the
        // second, so "Ask to join" went out as an invite for a whole phase.
        call("raceManager_race", "teamOffer", [p.id, kind]);
      };
      // ------------------------------------------------------------ copilot
      $scope.copilotOffer = function () { return ($scope.s.copilot || {}).offer || null; };
      $scope.copilotWatchers = function () { return list(($scope.s.copilot || {}).watchers); };
      $scope.copilotAsk = function (p, kind) { call("raceManager_copilot", "offer", [p.id, kind]); };
      $scope.copilotAccept  = function () { call("raceManager_copilot", "accept"); };
      $scope.copilotDecline = function () { call("raceManager_copilot", "decline"); };
      $scope.copilotStop    = function () { call("raceManager_copilot", "stop"); };

      // ---------------------------------------------------------- challenges
      $scope.chOpen = null;
      $scope.chForm = null;
      $scope.chClass = null;

      $scope.challengeList = function () { return list($scope.s.challenges); };

      // A click inside ng-repeat lands on the row's own scope, so a bare
      // "chOpen = c.id" set a copy nobody read and the detail never opened.
      // These write to the controller's scope.
      $scope.chShow = function (id) { $scope.chOpen = id; $scope.chClass = null; };
      $scope.chBack = function () { $scope.chOpen = null; };
      $scope.chPickClass = function (k) { $scope.chClass = k; };
      $scope.chCancelForm = function () { $scope.chForm = null; };

      // the daily rows and the weekly rows, each cached on the board they
      // came from: a fresh array every digest never settles
      var rowsFrom = null, rowsCache = { daily: [], weekly: [] };
      $scope.chRows = function (kind) {
        var all = list($scope.s.challenges);
        if (all !== rowsFrom) {
          rowsFrom = all;
          rowsCache = { daily: [], weekly: [] };
          for (var i = 0; i < all.length; i++) {
            var k = all[i].kind === "weekly" ? "weekly" : "daily";
            rowsCache[k].push(all[i]);
          }
        }
        return rowsCache[kind] || [];
      };
      $scope.chClasses = function (c) {
        var k = list(c && c.classes);
        return k.length ? k.join(", ") : $scope.t("ch.anyclass");
      };
      $scope.chMeta = function (c) {
        if (!c) return "";
        return $scope.chStyleLabel(c.style || "laptime") + " \u00b7 " + $scope.chClasses(c);
      };

      $scope.chShown = function () {
        var l = list($scope.s.challenges);
        for (var i = 0; i < l.length; i++) if (l[i].id === $scope.chOpen) return l[i];
        return null;
      };

      function spanText(secs) {
        var h = Math.floor(secs / 3600);
        if (h >= 48) return Math.floor(h / 24) + " d";
        if (h >= 1) return h + " h";
        return Math.max(1, Math.floor(secs / 60)) + " min";
      }
      $scope.chWhen = function (c) {
        if (!c) return "";
        if (c.state === "live") return $scope.t("ch.ends") + " " + spanText(c.secondsLeft);
        if (c.state === "scheduled") return $scope.t("ch.scheduled") + " " + spanText(c.startsIn);
        return $scope.t("ch.ended");
      };
      $scope.chChip = function (r) {
        if (!r) return "";
        if (r.suspect) return "challenge, marked";
        if (!r.tier) return "challenge: outside the ladder";
        return "challenge tier " + r.tier + (r.gained ? ", +" + r.gained + " XP" : "");
      };

      // the tooltip behind a race result row's XP total: placement and the
      // flat finishing bonus are two different amounts (see 17_xp.lua's
      // RM.xp.forRace), shown apart here so the number in the column isn't
      // the only place that says where it came from
      $scope.raceXpTitle = function (e) {
        if (!e) return "";
        var bits = [];
        if (e.xp) bits.push(e.xp + " for finishing " + ordinal(e.pos));
        if (e.completionXp) bits.push("+" + e.completionXp + " for finishing the race");
        return bits.join(", ") || "";
      };
      function ordinal(n) {
        n = parseInt(n, 10) || 0;
        var s = ["th", "st", "nd", "rd"], v = n % 100;
        return n + (s[(v - 20) % 10] || s[v] || s[0]);
      }

      $scope.chProblem = function () {
        var c = $scope.chShown();
        if (!c) return "";
        if (c.state !== "live") return $scope.t("ch.notlive");
        if (!$scope.s.me.tracking) return $scope.t("ch.needtracking");
        if (list(c.classes).length && list(c.classes).indexOf($scope.chClass) < 0) return $scope.t("ch.pickclass");
        return "";
      };
      $scope.chEnter = function () {
        var c = $scope.chShown();
        if (!c || $scope.chProblem()) return;
        var klass = list(c.classes).length ? $scope.chClass : null;
        if (c.track) {
          ui("armRace", [c.track, $scope.entry.mode, c.laps, klass, c.id]);
        } else {
          // free roam: no course, no grid -- the clock starts the moment
          // the server hears this
          ui("armChallenge", [c.id, $scope.entry.mode, klass]);
        }
        $scope.panel = null;
      };

      // ---------------------------------------------------- the challenge HUD
      // the challenge currently on the clock, cross-referenced from the run
      // state (s.race.challenge) against the board (s.challenges) the same
      // way telemetry.lua itself decides whether to be measuring anything
      $scope.chActive = function () {
        var r = $scope.s && $scope.s.race;
        if (!r || !r.challenge) return null;
        var all = ($scope.s && $scope.s.challenges) || [];
        for (var i = 0; i < all.length; i++) if (all[i].id === r.challenge) return all[i];
        return null;
      };
      $scope.chRemaining = function () {
        var c = $scope.chActive();
        if (!c || !c.timeLimit) return null;
        var left = c.timeLimit - (($scope.s.race || {}).elapsed || 0);
        return left > 0 ? left : 0;
      };
      // "the value this attempt would score right now", mirroring
      // RM.challenges.valueFor server side (22_challenges.lua) closely
      // enough for a live preview -- the server's own copy is what
      // actually gets scored at the end.
      $scope.chLiveValue = function () {
        var c = $scope.chActive();
        var live = $scope.s && $scope.s.challengeLive;
        if (!c || !live) return null;
        if (c.style === "speed") return live.peakSpeedMph;
        if (c.style === "gforce") return live.peakG;
        if (c.style === "distance") return (live.distanceM || 0) / 1609.344;
        if (c.style === "damage") {
          var miles = (live.distanceM || 0) / 1609.344;
          return miles * (1 + (live.damageTaken || 0) / 1000);
        }
        if (c.style === "longjump") return live.bestJump ? live.bestJump.scoreFt : null;
        return null;
      };
      // the easiest tier not yet cleared, so the HUD can say what is next
      $scope.chLiveNextTier = function () {
        var c = $scope.chActive();
        if (!c) return null;
        var v = $scope.chLiveValue();
        var tiers = list(c.tiers).slice().sort(function (a, b) { return a.time - b.time; });
        for (var i = 0; i < tiers.length; i++) {
          if (v == null || v < tiers[i].time) return tiers[i];
        }
        return null;
      };
      $scope.chLiveNextTierText = function () {
        var t = $scope.chLiveNextTier();
        var c = $scope.chActive();
        if (!t || !c) return "";
        return $scope.chValueText(t.time, c.style) + " (" + t.xp + " XP)";
      };
      $scope.chLiveProgressPct = function () {
        var t = $scope.chLiveNextTier();
        var v = $scope.chLiveValue();
        if (!t || !t.time) return 0;
        var pct = ((v || 0) / t.time) * 100;
        return Math.max(0, Math.min(100, pct));
      };

      // ------------------------------------------------- challenge results
      $scope.chClearFinished = function () { ui("clearChallengeFinished"); };
      $scope.chAgain = function () {
        var cf = $scope.s.challengeFinished;
        $scope.chClearFinished();
        if (!cf || !cf.challenge) return;
        var all = list($scope.s.challenges);
        var c = null;
        for (var i = 0; i < all.length; i++) {
          if (all[i].id === cf.challenge.id) { c = all[i]; break; }
        }
        if (!c) return;
        // repeating a challenge is the whole point of a ladder with tiers
        // to climb -- when there's no class to pick, re-arm right here,
        // the same call chEnter() makes, instead of sending the driver
        // back through the detail screen just to press the same button
        // they already pressed once
        if (!list(c.classes).length) {
          if (c.track) {
            ui("armRace", [c.track, $scope.entry.mode, c.laps, null, c.id]);
          } else {
            ui("armChallenge", [c.id, $scope.entry.mode, null]);
          }
          return;
        }
        $scope.chOpen = c.id;
        $scope.panel = "challenges";
      };

      // the form: an admin posting or changing one. A lap-time tier (or a
      // time limit, on any style) is typed as hours:minutes:seconds, e.g.
      // 0:01:32.43 or, for over an hour, 1:15:00.00 -- there is no ceiling
      // at 59 minutes, the hour figure just keeps counting up. Plain
      // minutes:seconds (1:32.43) and bare seconds (92.43) still parse the
      // same as before, so nothing already saved needs re-typing.
      var MAX_TIME_SECONDS = 24 * 3600;
      function parseTime(text) {
        var s = String(text == null ? "" : text).trim().replace(",", ".");
        if (!s) return null;
        var seconds = null;
        var hms = s.match(/^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?$/);
        if (hms) {
          seconds = parseInt(hms[1], 10) * 3600 + parseInt(hms[2], 10) * 60
            + parseInt(hms[3], 10) + (hms[4] ? parseFloat("0." + hms[4]) : 0);
        } else {
          var m = s.match(/^(\d+):(\d{1,2})(?:\.(\d{1,3}))?$/);
          if (m) {
            seconds = parseInt(m[1], 10) * 60 + parseInt(m[2], 10) + (m[3] ? parseFloat("0." + m[3]) : 0);
          } else if (/^\d+(\.\d{1,3})?$/.test(s)) {
            seconds = parseFloat(s);
          }
        }
        if (seconds == null || seconds > MAX_TIME_SECONDS) return null;
        return seconds;
      }
      // always shown as H:MM:SS.hh, hour figure included even at zero, so
      // the format itself says there is no cap at 59 minutes.
      function timeText(sec) {
        var h = Math.floor(sec / 3600), rem = sec - h * 3600;
        var m = Math.floor(rem / 60), r = rem - m * 60;
        return h + ":" + (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r.toFixed(2);
      }

      // Every style beyond lap time scores a plain number in its own unit
      // (mph, g, a damage/distance score, feet, miles) rather than a time,
      // so the ladder is a tier and an XP, same as always, but the tier is
      // typed and shown as that number rather than as a clock.
      var CH_STYLES = [
        { key: "laptime",  unit: "time",  higherBetter: false, timeLimit: "none",     max: 24 * 3600 },
        { key: "speed",    unit: "mph",   higherBetter: true,  timeLimit: "optional", max: 400 },
        { key: "gforce",   unit: "g",     higherBetter: true,  timeLimit: "required", max: 50 },
        { key: "damage",   unit: "score", higherBetter: true,  timeLimit: "required", max: 1000000 },
        { key: "longjump", unit: "ft",    higherBetter: true,  timeLimit: "required", max: 5000 },
        { key: "distance", unit: "mi",    higherBetter: true,  timeLimit: "required", max: 5000 },
      ];
      function styleMeta(key) {
        for (var i = 0; i < CH_STYLES.length; i++) if (CH_STYLES[i].key === key) return CH_STYLES[i];
        return CH_STYLES[0];
      }
      $scope.chStyles = CH_STYLES;
      $scope.chStyleLabel = function (key) { return $scope.t("ch.style." + key); };

      function parseTierValue(text, style) {
        var meta = styleMeta(style);
        if (meta.unit === "time") return parseTime(text);
        var v = parseFloat(String(text == null ? "" : text).trim().replace(",", "."));
        if (isNaN(v) || v <= 0 || v > meta.max) return null;
        return v;
      }
      function tierValueText(v, style) {
        var meta = styleMeta(style);
        if (meta.unit === "time") return timeText(v);
        if (meta.unit === "score") return String(Math.round(v));
        return (Math.round(v * 10) / 10).toString();
      }
      $scope.chTierPlaceholder = function () {
        var meta = $scope.chForm ? styleMeta($scope.chForm.style) : CH_STYLES[0];
        if (meta.unit === "time") return "0:01:32.43";
        if (meta.unit === "mph") return "85";
        if (meta.unit === "g") return "1.8";
        if (meta.unit === "score") return "500";
        if (meta.unit === "ft") return "40";
        return "3.5";
      };
      // switching style resets the ladder to blank tiers in the new unit,
      // rather than leaving old numbers on screen that no longer mean what
      // they say (a "45" left over from a speed challenge reads as 45mph,
      // not as 45 seconds, the moment the style changes to lap time)
      $scope.chSetStyle = function (key) {
        if (!$scope.chForm || $scope.chForm.style === key) return;
        var wasLaptime = $scope.chForm.style === "laptime";
        var isLaptime = key === "laptime";
        $scope.chForm.style = key;
        $scope.chForm.tiers = [{ time: "", xp: 100 }, { time: "", xp: 50 }];
        // the time-limit field only exists for non-lap-time styles, and
        // reads the same h:mm:ss format for every one of them, so a value
        // already typed carries over between them -- it only clears
        // crossing to/from lap time, where the field disappears entirely.
        // (Re-clicking the style already selected is a no-op, above --
        // that alone used to be enough to silently wipe a typed time
        // limit if an admin clicked it again out of habit.)
        if (wasLaptime !== isLaptime) $scope.chForm.timeLimit = "";
        $scope.chForm.useCourse = isLaptime;
        if (isLaptime) $scope.chForm.track = $scope.chForm.track || null;
      };
      $scope.chSetUseCourse = function (on) {
        if (!$scope.chForm) return;
        $scope.chForm.useCourse = !!on;
        if (!on) $scope.chForm.track = null;
      };
      $scope.classNames = function () {
        var out = [], groups = $scope.classGroups();
        for (var i = 0; i < groups.length; i++) out = out.concat(groups[i].classes);
        return out;
      };
      $scope.chNew = function () {
        $scope.chForm = { kind: "daily", style: "laptime", useCourse: true, track: null, laps: 1, classes: [],
                          tiers: [{ time: "", xp: 100 }, { time: "", xp: 75 }, { time: "", xp: 50 }],
                          timeLimit: "",
                          startInHours: 0, name: "", description: "" };
      };
      $scope.chEdit = function (c) {
        var style = c.style || "laptime";
        var tiers = [];
        list(c.tiers).forEach(function (r) { tiers.push({ time: tierValueText(r.time, style), xp: r.xp }); });
        $scope.chForm = { id: c.id, name: c.name, kind: c.kind, style: style,
                          useCourse: style === "laptime" || !!c.track,
                          track: c.track, laps: c.laps,
                          classes: list(c.classes).slice(), tiers: tiers, startInHours: null,
                          timeLimit: c.timeLimit ? timeText(c.timeLimit) : "",
                          description: c.description || "" };
        $scope.chOpen = null;
      };
      $scope.chFormTrack = function () {
        if (!$scope.chForm) return null;
        var l = list($scope.s.tracks);
        for (var i = 0; i < l.length; i++) if (l[i].id === $scope.chForm.track) return l[i];
        return null;
      };
      $scope.chAddTier = function () {
        if ($scope.chForm && $scope.chForm.tiers.length < 20) $scope.chForm.tiers.push({ time: "", xp: 0 });
      };
      $scope.chRemoveTier = function (i) {
        if ($scope.chForm) $scope.chForm.tiers.splice(i, 1);
      };
      $scope.chToggleClass = function (k) {
        var c = $scope.chForm.classes, i = c.indexOf(k);
        if (i >= 0) c.splice(i, 1); else c.push(k);
      };
      $scope.chFormProblem = function () {
        var f = $scope.chForm;
        if (!f) return "";
        if (!(f.name || "").trim() || (f.name || "").trim().length < 2) return $scope.t("ch.p.name");
        var style = f.style || "laptime";
        var needsCourse = style === "laptime" || f.useCourse;
        if (needsCourse && !f.track) return $scope.t("ch.p.track");
        var meta = styleMeta(style);
        var tiers = list(f.tiers);
        if (!tiers.length) return $scope.t("ch.p.tiers");
        for (var i = 0; i < tiers.length; i++) {
          var val = parseTierValue(tiers[i].time, style);
          if (val == null) return meta.unit === "time" ? $scope.t("ch.p.time") : $scope.t("ch.p.value");
          var xp = parseInt(tiers[i].xp, 10);
          if (isNaN(xp) || xp < 0) return $scope.t("ch.p.xp");
        }
        if (meta.timeLimit !== "none") {
          var tl = (f.timeLimit || "").trim();
          if (tl === "") {
            if (meta.timeLimit === "required") return $scope.t("ch.p.timelimit");
          } else {
            var secs = parseTime(tl);
            if (secs == null || secs < 5 || secs > 3600) return $scope.t("ch.p.timelimit");
          }
        }
        return "";
      };
      $scope.chSave = function () {
        var f = $scope.chForm;
        if (!f) return;
        var problem = $scope.chFormProblem();
        if (problem) {
          $scope.chFormError = problem;
          return;
        }
        $scope.chFormError = "";
        var style = f.style || "laptime";
        var needsCourse = style === "laptime" || f.useCourse;
        var t = needsCourse ? $scope.chFormTrack() : null;
        var meta = styleMeta(style);
        var tiers = [];
        list(f.tiers).forEach(function (r) {
          tiers.push({ time: parseTierValue(r.time, style), xp: parseInt(r.xp, 10) || 0 });
        });
        var out = { name: (f.name || "").trim(), kind: f.kind || "daily", style: style,
                    track: needsCourse ? f.track : null,
                    laps: (needsCourse && t && t.circuit) ? Math.max(1, parseInt(f.laps, 10) || 1) : 1,
                    classes: (f.classes && f.classes.length) ? f.classes : null, tiers: tiers,
                    description: (f.description || "").trim() };
        if (meta.timeLimit !== "none" && (f.timeLimit || "").trim() !== "") {
          out.timeLimit = parseTime(f.timeLimit);
        }
        if (f.startInHours != null) out.startInHours = f.startInHours;
        if (f.id) out.id = f.id;
        // JSON string, not a Lua table literal — engineLua used to swallow the post.
        ui(f.id ? "challengeUpdate" : "challengeCreate", JSON.stringify(out));
        $scope.chFormBusy = true;
      };
      $scope.chEndNow = function (id) { ui("challengeEnd", id); $scope.chOpen = null; };
      $scope.chDelete = function (id) { ui("challengeDelete", id); $scope.chOpen = null; };

      // ------------------------------------------------------------ tracking
      $scope.setTracking = function (on) { ui("setTracking", on ? true : false); };

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
        speeding:    "Speeding before gate",
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
        no_session:      "The server has not finished recognising you yet.",
        no_such_challenge: "That challenge is gone.",
        challenge_not_live: "That challenge is not live.",
        challenge_misconfigured: "This challenge is missing its time limit and can't be scored yet — an admin needs to open and re-save it.",
        wrong_course_for_challenge: "That is not the challenge's course.",
        wrong_laps_for_challenge: "The laps are set by the challenge.",
        class_not_in_challenge: "Pick one of the challenge's classes.",
        teams_cannot_enter: "Teams cannot enter a challenge. Break up first.",
        tracking_off:    "Turn XP and challenge tracking on under Options first.",
        guests_cannot_enter: "Guest accounts cannot enter a challenge on this server."
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

      // how a challenge's own number is shown once it is not a lap time:
      // plain value plus its unit, rather than running it through the
      // mm:ss clock formatter that every other time-like number on this
      // screen uses.
      var CH_UNIT_SUFFIX = { mph: " mph", g: " g", score: " pts", ft: " ft", mi: " mi" };
      $scope.chValueText = function (value, style) {
        if (value == null || value === "") return "—";
        var meta = styleMeta(style);
        if (meta.unit === "time") return $scope.clock(value);
        var n = meta.unit === "score" ? Math.round(value) : (Math.round(value * 10) / 10);
        return n + (CH_UNIT_SUFFIX[meta.unit] || "");
      };
      $scope.chRungWord = function (style) {
        return styleMeta(style).higherBetter ? $scope.t("ch.atleast") : $scope.t("ch.under");
      };

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
        var off = !!( $scope.s.isStaff || $scope.s.isAdmin || $scope.s.isOwner ) && !!$scope.entry.official;
        call("raceManager_race", "createLobby",
          [$scope.entry.track, $scope.entry.mode, $scope.entry.laps, !!open,
           $scope.entry.raceClass, off, off ? ($scope.entry.officialName || "") : ""]);
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
        list(l.members).forEach(function (m) { inRace[m.id] = true; });
        return list($scope.s.roster).filter(function (p) { return !inRace[p.id]; });
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

      // on the grid or on the clock. either way there is a race to end.
      $scope.raceActive = function () {
        var st = ($scope.s.race || {}).state;
        return st === "armed" || st === "running";
      };

      $scope.topLabel = function (b) {
        return (b.key === "race" && $scope.raceActive()) ? $scope.t("endrace") : $scope.t(b.key);
      };

      // A native select does not open in the game's interface layer. None of
      // the 116 apps that ship with the game use one, and the one that needs a
      // picker reaches for angular material instead. So these are buttons: they
      // work, they match the rest of the panel, and they are easier to hit with
      // a controller than a dropdown would have been.
      //
      // Written through functions rather than bound with ng-model because
      // ng-if makes a child scope, and a bare assignment lands on the child.
      // The courses on this map first, then the ones built elsewhere, said
      // so. A course belongs to the map it was captured on and a server runs
      // one map at a time. Cached on the list and the level, since a fresh
      // array every digest never settles.
      function levelKey(s) {
        if (!s) return "";
        var p = String(s).replace(/\\/g, "/").toLowerCase();
        var m = p.match(/(?:^|\/)levels\/([^/]+)/) || p.match(/([^/]+)\/info\.json$/);
        if (m) return m[1];
        var parts = p.split("/").filter(Boolean);
        return parts.length ? parts[parts.length - 1] : p;
      }
      function onThisMap(t) {
        var here = levelKey($scope.s.level);
        if (!here || !t || !t.level) return true;
        return levelKey(t.level) === here;
      }

      var listFrom = null, listLevel = null, listCache = [], awayCache = [];
      $scope.trackList = function () {
        var all = list($scope.s.tracks), lvl = $scope.s.level || "";
        if (all !== listFrom || lvl !== listLevel) {
          listFrom = all; listLevel = lvl;
          var here = [], away = [];
          for (var i = 0; i < all.length; i++) {
            (onThisMap(all[i]) ? here : away).push(all[i]);
          }
          var byGates = function (a, b) {
            var ca = Number(a && a.count) || 0, cb = Number(b && b.count) || 0;
            if (cb !== ca) return cb - ca;
            return String((a && a.name) || "").localeCompare(String((b && b.name) || ""));
          };
          here.sort(byGates);
          away.sort(byGates);
          listCache = here;
          awayCache = away;
        }
        return listCache;
      };
      $scope.trackListOther = function () {
        $scope.trackList();
        return awayCache;
      };
      $scope.trackAway = function (t) {
        return !onThisMap(t);
      };
      $scope.anyAway = function () { return false; };

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
        var off = !!( $scope.s.isStaff || $scope.s.isAdmin || $scope.s.isOwner ) && !!$scope.entry.official;
        ui("armRace", [$scope.entry.track, $scope.entry.mode, laps,
                       $scope.entry.raceClass, null, off, off ? ($scope.entry.officialName || "") : ""]);
      };

      $scope.endRace = function () { ui("endRace"); };

      // Speed zones on the course being shown. The whole list goes to the
      // server every time, because a zone is a rule on the course rather than
      // a thing of its own, and the server keeps the one copy.
      $scope.zoneForm = { from: 1, to: 2, mph: 37 };

      // A list the game sends over empty arrives as {}, not []: its encoder
      // cannot tell an empty list from an empty table. So .slice() on the
      // zones of a course that had none yet threw, and the first zone anyone
      // tried to add on any course was never sent. He pressed the button and
      // nothing happened, and the server log never saw a zone saved.
      function list(x) { return Array.isArray(x) ? x : []; }

      function shownZones() {
        var sh = ($scope.s.capture || {}).shown;
        return sh ? list(sh.zones).slice() : [];
      }

      // what is wrong with the zone about to be added, or nothing
      $scope.zoneProblem = function () {
        var sh = ($scope.s.capture || {}).shown;
        if (!sh) return "";
        var from = parseInt($scope.zoneForm.from, 10);
        var to   = parseInt($scope.zoneForm.to, 10);
        var mph  = parseInt($scope.zoneForm.mph, 10);
        var n    = parseInt(sh.count, 10) || 0;
        if (!(from >= 1) || !(to >= 1)) return "Both gates are needed.";
        if (from > n || to > n) return "This course only has " + n + " gates.";
        if (to <= from) return "To gate has to come after From gate. A zone runs from one gate on to a later one.";
        if (!(mph >= 5)) return "The limit has to be at least 5 mph.";
        return "";
      };

      $scope.zoneAdd = function () {
        var sh = ($scope.s.capture || {}).shown;
        if (!sh || $scope.zoneProblem()) return;
        var z = shownZones();
        z.push({ from: parseInt($scope.zoneForm.from, 10),
                 to:   parseInt($scope.zoneForm.to, 10),
                 mph:  parseInt($scope.zoneForm.mph, 10) });
        $scope.cap("setZones", [sh.id, z]);
      };

      $scope.zoneRemove = function (i) {
        var sh = ($scope.s.capture || {}).shown;
        if (!sh) return;
        var z = shownZones();
        z.splice(i, 1);
        $scope.cap("setZones", [sh.id, z]);
      };

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
      // Put the windows back: the bars and the Stella too, and the game asked
      // to give the app the whole screen again. One reset, however it is asked.
      $scope.resetPanels = function () {
        $scope.panel = null;
        restoreUiLayout(true);
        askForWholeScreen();
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
        // Refresh subscription + open — never hide.
        ui("setRosterOpen", true);
        $scope.s.rosterOpen = true;
      };

      $scope.isQueued = function (p) {
        if (!p) return false;
        return p.queued === true || p.queued === 1;
      };

      $scope.takeInvite = function (inv) {
        if (!inv) return;
        ui("takeInvite", inv.id);
      };
      $scope.refuseInvite = function (inv) {
        if (!inv) return;
        ui("refuseInvite", inv.id);
      };

      function fmtBoardTime(sec) {
        sec = Number(sec) || 0;
        if (sec < 0) sec = Math.abs(sec);
        var m = Math.floor(sec / 60);
        var s = sec - m * 60;
        var whole = Math.floor(s);
        var hundred = Math.round((s - whole) * 100);
        if (hundred >= 100) { whole += 1; hundred = 0; }
        if (whole >= 60) { m += 1; whole = 0; }
        var mm = m < 10 ? "0" + m : String(m);
        var ss = whole < 10 ? "0" + whole : String(whole);
        var hh = hundred < 10 ? "0" + hundred : String(hundred);
        return mm + ":" + ss + "." + hh;
      }

      $scope.liveBoard = function () {
        var race = ($scope.s && $scope.s.race) || {};
        var board = race.board;
        if (!board || !board.length) return [];
        if (race.state !== "running" && race.state !== "armed" && race.state !== "finished") return [];
        var queued = {};
        angular.forEach($scope.s.roster || [], function (p) {
          if (p && p.queued) queued[p.id] = true;
        });
        return board.map(function (row) {
          var copy = angular.extend({}, row);
          if (queued[row.id]) copy.queued = true;
          return copy;
        });
      };

      $scope.boardLap = function (p) {
        var race = ($scope.s && $scope.s.race) || {};
        var total = (p && p.laps) || race.laps || 0;
        var lap = (p && p.lap) || 0;
        if (!total) return String(lap || 1);
        return lap + "/" + total;
      };

      $scope.boardClock = function (p) {
        if (!p) return "00:00.00";
        if (p.pos === 1) return fmtBoardTime(p.elapsed);
        if (p.gapLaps && p.gapLaps > 0) return "-" + p.gapLaps + " lap";
        return "-" + fmtBoardTime(p.gap || 0);
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

      $scope.staffPick = null;
      $scope.openStaff = function (d) {
        $scope.staffPick = d ? { key: d.key, name: d.name, role: d.role || "player", pid: d.pid != null ? d.pid : null } : null;
      };
      $scope.staffRole = function (role) {
        if (!$scope.staffPick) return;
        ui("staffRole", [$scope.staffPick.key, role]);
        $scope.staffPick.role = role;
      };
      $scope.staffKick = function () {
        if (!$scope.staffPick) return;
        ui("staffKick", $scope.staffPick.key);
      };
      $scope.staffRaceKick = function () {
        if (!$scope.staffPick || $scope.staffPick.pid == null) return;
        ui("staffRaceKick", $scope.staffPick.pid);
      };
      $scope.launchPick = null;
      $scope.liveChallenges = function () {
        var all = list($scope.s.challenges);
        var out = [];
        for (var i = 0; i < all.length; i++) {
          if (all[i].state === "live") out.push(all[i]);
        }
        return out;
      };
      $scope.staffLaunchAll = function () {
        if (!$scope.launchPick) return;
        ui("staffLaunchAll", $scope.launchPick);
      };
      $scope.staffBan = function () {
        if (!$scope.staffPick) return;
        ui("staffBan", $scope.staffPick.key);
      };
      $scope.staffClear = function () {
        if (!$scope.staffPick) return;
        ui("staffClearRecords", $scope.staffPick.key);
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
