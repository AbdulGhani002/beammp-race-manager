"""Checks the interface against itself.

    python tools/check_ui.py

Three things have gone wrong in this project that a person reading the code
did not catch, and all three are the same shape: the template names something
that is not there.

  - a model bound inside ng-if, written to a child scope the controller
    never sees
  - a field read from the snapshot that the lua never put in it, so the
    player list opened on the click and vanished on the next push
  - a click calling a function that was never added to the scope

None of them fail loudly. The panel just quietly does nothing, and you find
out in the game. So they are checked here instead.
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "client", "ui", "modules", "apps", "RaceManager")
LUA = os.path.join(ROOT, "client", "lua", "ge", "extensions", "raceManager")

VOID = {"img", "br", "hr", "input", "link", "meta", "source", "col"}

problems = []
checks = [0]


def read(path):
    return io.open(path, encoding="utf-8").read()


def check(cond, what):
    checks[0] += 1
    if not cond:
        problems.append(what)


def tags_balance(html):
    stack = []
    for close, name, attrs, selfclose in re.findall(
            r"<(/?)([a-zA-Z][\w-]*)([^>]*?)(/?)>", html):
        n = name.lower()
        if n in VOID or selfclose:
            continue
        if close:
            if stack and stack[-1] == n:
                stack.pop()
            else:
                return "mismatched </%s>" % n
        else:
            stack.append(n)
    if stack:
        return "never closed: " + ", ".join(stack)
    return None


def scope_functions(js):
    return set(re.findall(r"\$scope\.(\w+)\s*=\s*function", js))


def scope_values(js):
    return set(re.findall(r"\$scope\.(\w+)\s*=(?!=)", js))


def unquoted(expr):
    """the expression with its string literals taken out, so a translation
    key like 'opt.courses' is not read as a scope name"""
    return re.sub(r"'[^']*'", "''", expr)


def template_calls(html):
    """Every function the template calls, from any angular attribute. A call
    on $event is angular's, not the scope's."""
    out = set()
    for attr in re.findall(r'ng-(?:click|if|disabled|class|change|keydown|options|repeat|model)="([^"]*)"', html):
        for name in re.findall(r"(?<![.\w$])([a-zA-Z_]\w*)\s*\(", unquoted(attr)):
            out.add(name)
    for expr in re.findall(r"\{\{([^}]*)\}\}", html):
        for name in re.findall(r"(?<![.\w$])([a-zA-Z_]\w*)\s*\(", unquoted(expr)):
            out.add(name)
    return out


def template_loop_vars(html):
    """the names ng-repeat brings into being"""
    return set(re.findall(r'ng-repeat="\(?\s*([a-zA-Z_]\w*)', html))


def template_roots(html):
    """Top level scope names the template reads, so a typo shows up."""
    out = set()
    blob = " ".join(re.findall(r'ng-\w+="([^"]*)"', html))
    blob += " " + " ".join(re.findall(r"\{\{([^}]*)\}\}", html))
    blob = unquoted(blob)
    # not $event: angular puts that one there itself
    for name in re.findall(r"(?<![.\w$])([a-zA-Z_]\w*)\s*\.", blob):
        out.add(name)
    for name in re.findall(r'ng-model="([a-zA-Z_]\w*)(?:\.|")', blob + ' ng-model="x"'):
        out.add(name)
    return out


def lua_functions(path):
    return set(re.findall(r"function\s+M\.(\w+)", read(path)))


def snapshot_fields(uilua):
    return set(re.findall(r"snap\.(\w+)", uilua))


def main():
    html = read(os.path.join(APP, "app.html"))
    js = read(os.path.join(APP, "app.js"))
    css = read(os.path.join(APP, "app.css"))
    uilua = read(os.path.join(LUA, "ui.lua"))

    bad = tags_balance(html)
    check(bad is None, "app.html tags: %s" % bad)

    # 1. every function the template calls is on the scope
    fns = scope_functions(js)
    builtin = {
        "filter", "number", "json", "date", "lowercase", "uppercase",
        "join", "toFixed", "indexOf", "charAt", "substring", "trim", "split",
    }
    for name in sorted(template_calls(html)):
        if name in builtin:
            continue
        check(name in fns, "app.html calls %s() which is not on the scope" % name)

    # 2. every top level name the template reads exists on the scope
    known = scope_functions(js) | scope_values(js) | template_loop_vars(html) | {
        "s", "b", "p", "t", "l", "e", "d", "sec", "$event", "Math",
    }
    for name in sorted(template_roots(html)):
        if name in known or len(name) <= 2:
            continue
        check(name in known, "app.html reads %s which the controller never sets" % name)

    # 3. every field read off the snapshot is one the lua actually sends
    fields = snapshot_fields(uilua)
    for name in sorted(set(re.findall(r"\bs\.(\w+)", html))):
        check(name in fields, "app.html reads s.%s which ui.lua never puts in the snapshot" % name)

    # 4. every lua function the controller calls exists in that module
    for module, fn in re.findall(r'call\(\s*"raceManager_(\w+)"\s*,\s*"(\w+)"', js):
        path = os.path.join(LUA, module + ".lua")
        check(os.path.exists(path), "app.js calls into raceManager_%s which has no file" % module)
        if os.path.exists(path):
            check(fn in lua_functions(path),
                  "app.js calls raceManager_%s.%s which is not defined there" % (module, fn))

    # a helper that forwards its first argument as the lua function name hides
    # that name from the check above, because the name lives in the html.
    # cap('openTrack') is exactly the kind of button that reads fine and does
    # nothing.
    bridges = re.findall(
        r'[$]scope[.](\w+)\s*=\s*function\s*[(](\w+)[^)]*[)]\s*[{]\s*'
        r'call[(]\s*"raceManager_(\w+)"\s*,\s*\2\b',
        js)
    for helper, _param, module in bridges:
        path = os.path.join(LUA, module + ".lua")
        known = lua_functions(path) if os.path.exists(path) else set()
        names = set(re.findall(helper + r"[(]\s*['\"](\w+)['\"]", html))
        check(len(names) > 0,
              "app.js defines %s() but the html never calls it" % helper)
        for fn in sorted(names):
            check(fn in known,
                  "app.html calls %s('%s'), which raceManager_%s does not define"
                  % (helper, fn, module))

    for fn in sorted(set(re.findall(r'\bui\(\s*"(\w+)"', js))):
        check(fn in lua_functions(os.path.join(LUA, "ui.lua")),
              "app.js calls ui.%s which is not defined in ui.lua" % fn)

    # 5. anything two way bound has to sit behind a dot, or ng-if hides it on
    #    a child scope and the controller never sees what was typed
    for model in re.findall(r'ng-model="([^"]+)"', html):
        check("." in model, 'ng-model="%s" has no dot, so a child scope will swallow it' % model)

    # 5b. the same trap on a click: "chOpen = c.id" inside ng-repeat or ng-if
    #     writes a copy on the child scope, and the controller never sees it.
    #     His challenge detail never opened for exactly this reason.
    for expr in re.findall(r'ng-click="([^"]*)"', html):
        for name in re.findall(r"(?:^|[;\s])([a-zA-Z_]\w*)\s*=(?!=)", expr):
            check(False, 'ng-click="%s" assigns %s on a child scope; call a function instead' % (expr[:60], name))

    # 6. no native select. it does not open in the game's interface layer, and
    #    the panel just sits there when you click it. None of the 116 apps that
    #    ship with the game use one either.
    check("<select" not in html,
          "app.html has a native <select>, which does not open in the game")

    # 7. every image the page asks for is actually shipped
    for src in sorted(set(re.findall(r'src="/ui/modules/apps/RaceManager/([^"]+)"', html))):
        check(os.path.exists(os.path.join(APP, src)), "app.html asks for %s which is not there" % src)

    # 8. the trigger fields. A value the engine does not know leaves the test
    #    doing whatever it falls back to, and a checkpoint you drive through
    #    quietly does nothing. "Race Corners" sat here for weeks and appears in
    #    no lua and no level in the game. These are the values the 170 triggers
    #    shipped with the game actually use.
    triggers = read(os.path.join(LUA, "triggers.lua"))
    allowed = {
        "triggerType": {"Box", "Sphere"},
        "triggerMode": {"Overlaps", "Contains"},
        # every trigger in the game uses "Bounding box". "Race Corners" is not
        # a value, it is one I invented, which is the whole reason for this.
        "triggerTestType": {"Bounding box"},
        "luaFunction": {"onBeamNGTrigger"},
    }
    for field, value in re.findall(r'setField\("(\w+)",\s*0,\s*"([^"]+)"\)', triggers):
        if field in allowed:
            check(value in allowed[field],
                  'triggers.lua sets %s to "%s", which the game never uses' % (field, value))
    check('"luaFunction"' in triggers,
          "triggers.lua never sets luaFunction, so the engine calls nothing")

    # Yaw sends the box's local x along the way you drive, so the width has to
    # be the y of the scale and the depth the x. They were the other way round,
    # which built a three metre slot down the road instead of a gate across it
    # and is why driving through a checkpoint so often did nothing. The shape is
    # worked out once in gateBox now, and both the volume and the posts read it
    # from there, so this checks it stayed that way.
    check(re.search(r"obj:setScale\(vec3\(along,\s*across,", triggers) is not None,
          "triggers.lua scales the gate volume with the width along the road")
    # a gate is centred on the capture car's line, which is rarely the middle
    # of the track. drop this call and gates quietly go back to only counting
    # near wherever the course builder happened to be driving.
    build = re.search(r"function M\.build\(.*?\nend\n", triggers, re.S)
    check(build is not None and "fitSpans(" in build.group(0),
          "M.build does not fit the gates to the track, so gates sit off centre again")

    for fn in ("spawnGate", "drawGate"):
        body = re.search(r"local function %s\(.*?\n(.*?)\nend\n" % fn, triggers, re.S)
        check(body is not None and "gateBox(cp" in body.group(1),
              "%s does not build its gate from gateBox, so the volume and the "
              "posts can drift apart again" % fn)

    # A pit is a place you sit in for the length of a repair, not a line you
    # cross. Built to a gate's three metres it fired enter and exit in the same
    # tenth of a second, so parking in one registered nothing at all.
    pit_d = re.search(r"DEFAULT_PIT\s*=\s*\{[^}]*d\s*=\s*(\d+)", triggers)
    check(pit_d is not None,
          "triggers.lua has no pit size of its own, so a pit is a gate again")
    check(pit_d is None or int(pit_d.group(1)) >= 15,
          "the pit box is too short to stop inside, so being in the pit flickers")
    check('spawnGate(pits[i], i, PIT_PREFIX, "pit")' in triggers,
          "pits are spawned without their own kind, so they get a gate's depth")

    # Leaving one pit box while still inside another used to report the car out
    # of the pit, so a lane with a box at each end never held.
    check("inPits" in triggers and "M.pitCrossed(" in triggers,
          "triggers.lua tracks the pit with a flag again, so overlapping pit "
          "boxes cancel each other")

    # Every press has to make a noise. The bar was silent unless a job started
    # inside a run, so pressing a button on an empty server felt like nothing
    # had happened at all.
    for fn in ("bottomClick", "lightPick"):
        body = re.search(r"\$scope\.%s = function \(.*?\n(.*?)\n      \};" % fn, js, re.S)
        check(body is not None and "pressClick()" in body.group(1),
              "%s does not play the press sound, so the button is silent" % fn)

    click = os.path.join(APP, "sounds", "click.mp3")
    check(os.path.exists(click), "sounds/click.mp3 is missing, so a press is silent")
    if os.path.exists(click):
        check(os.path.getsize(click) > 200,
              "sounds/click.mp3 is empty, so a press is silent")

    # The sound used to be cut the moment the job ended. Outside a run the
    # server starts and finishes a job in the same breath, so that killed the
    # pattern before a note of it was heard.
    sfs = re.search(r"function soundsForState\(data\) \{(.*?)\n      \}", js, re.S)
    check(sfs is not None and "if (!which) return;" in sfs.group(1),
          "soundsForState stops the sound when a job ends again, so nothing is "
          "heard outside a run")
    check(sfs is not None and "FREE_SOUND_SECS" in sfs.group(1),
          "a job with no hold gets no sound window, so free driving is silent")

    # The client asked the car for a flat before every spare press. The server
    # only wants one during a run and out on the course, so the check refused
    # presses the server would have allowed.
    # The Stella is his app, and he resizes it. The dash box around it is
    # mine, and it has to be the same size or the instrument is drawn at a
    # fraction of itself in the corner. That is exactly what a 1280x720 box
    # around a 362x240 device looked like on his screen.
    import json as _json
    stella_json = _json.loads(read("client/ui/modules/apps/BajaStella/app.json"))
    want_w = stella_json.get("css", {}).get("width", "")
    want_h = stella_json.get("css", {}).get("height", "")
    scale = re.search(r"\.rm-stella-scale \{(.*?)\}", css, re.S)
    check(scale is not None, "the Stella dash box is gone from app.css")
    if scale:
        got_w = re.search(r"width:\s*([0-9]+px)", scale.group(1))
        got_h = re.search(r"height:\s*([0-9]+px)", scale.group(1))
        check(got_w is not None and got_w.group(1) == want_w,
              "the Stella dash box is %s wide but his app.json says %s"
              % (got_w.group(1) if got_w else "?", want_w))
        check(got_h is not None and got_h.group(1) == want_h,
              "the Stella dash box is %s tall but his app.json says %s"
              % (got_h.group(1) if got_h else "?", want_h))

    # His own sheet draws the device: its border, its shadow, its screen. The
    # overrides here were for a photograph that is no longer used, and forcing
    # them onto the drawn one takes his screen apart.
    stella_css = re.findall(r"\.rm-stella [^{]*\{[^}]*\}", css)
    check(not any("st-lcd" in r or "box-shadow" in r for r in stella_css),
          "app.css overrides the Stella's own styling again, which was only "
          "ever needed for the photograph")

    # The things he asked for after the first full test, each one a line
    # that can quietly come back.
    check('rm-move="top"' in html and 'rm-move="bottom"' in html,
          "a bar lost its rm-move, so it cannot be dragged")
    check("stop the car to use these" not in html,
          "the bottom bar says stop the car again, and grows to say it")
    check('ng-if="raceRunning() && dash.clock"' in html,
          "the clock over the road is back on without being asked for")
    check("topLabel(b)" in html and "$scope.topLabel" in js,
          "the Race button no longer turns into End race during a run")
    # He looked for the zones and did not find them, because they only showed
    # once a course was on show. They are on screen for staff from the start.
    check('<div class="rm-group rm-zones" ng-if="s.isAdmin">' in html,
          "the speed zones hide until a course is shown again, which is where he lost them")
    # and he took hold of a button, which is nearly all of a bar, so a press
    # that travels drags the bar and a press that stays put is the click
    check("var SLACK = " in js and 'node.addEventListener("click"' in js,
          "a bar no longer drags from a press on a button, and a button is "
          "nearly all there is of a bar")
    # The Stella and the speed zones, the way he described them: the limit in
    # flashing yellow about 100 m before, steady red inside, flashing red over,
    # and gone after. His extension had yellow inside and never spelt the number.
    bs = read("client/lua/ge/extensions/bajaStella.lua")
    bridge = read("client/lua/ge/extensions/raceManager/stella.lua")
    stella_ui = read("client/ui/modules/apps/BajaStella/app.js")
    check('setLed("yellow", true, limitPattern(zone))' in bs,
          "a zone ahead no longer flashes the limit in yellow on the Stella")
    check('setLed("red", lastExceeding and true or false, limitPattern(zone))' in bs,
          "inside a zone the Stella no longer sits red with the limit, flashing when over")
    check("warnDistance = 100," in bridge and "limitMph = mph," in bridge,
          "the bridge no longer warns at a hundred metres with the limit in mph")
    check("p.indexOf('limit:') === 0" in stella_ui and "function digitRows" in stella_ui,
          "the Stella dots no longer spell the limit")
    check('ng-show="szActive || szWarning"' in stella_ui,
          "the Stella screen no longer shows the limit for a zone ahead")
    # and the race panel says what zones a course has, so nobody drives one
    # expecting a penalty it cannot give
    check("rm-track-zones" in html and "No speed zones on this course" in html,
          "the race panel no longer says which speed zones a course has")
    check("zones = type(t.zones) == \"table\" and t.zones or {}," in read("server/RaceManager/07_tracks.lua"),
          "the course list no longer carries the zones, so the race panel cannot show them")
    # The game's encoder sends an empty list as {}. Anything that calls an
    # array method on a list from the snapshot has to go through list() first,
    # or the first zone on a course is never sent, which is what happened.
    check("function list(x) { return Array.isArray(x) ? x : []; }" in js,
          "the list() guard for empty lists from the game is gone")
    for bad in re.findall(r"\(\$scope\.s\.\w+ \|\| \[\]\)\.(?:forEach|filter|map|slice)\(", js):
        check(False, "app.js calls an array method on a snapshot list without list(): " + bad)
    for bad in re.findall(r"\b(?:sh|l|e|t|p)\.\w+\.(?:slice|forEach|filter|map)\(", js):
        check(False, "app.js calls an array method on a list from the game without list(): " + bad)
    check("$scope.zoneProblem" in js and 'ng-disabled="zoneProblem()"' in html,
          "the zone form no longer refuses a zone that runs nowhere")
    # A hold locks the gearbox. The car that was locked is let go by id, a
    # server that goes quiet lets it go after a grace, and leaving the level
    # forgets it. An engine that revs with a car that will not move is what a
    # leak here looks like from the seat.
    svc_hold = read("client/lua/ge/extensions/raceManager/service.lua")
    check("local frozenId" in svc_hold and "be:getObjectByID(frozenId)" in svc_hold,
          "the hold no longer remembers which car it locked")
    check("local GRACE = " in svc_hold and "if left < -GRACE then" in svc_hold,
          "a hold the server never finishes keeps the car locked again")
    check("function M.onLevelUnloaded" in svc_hold
          and "raceManager_service.onLevelUnloaded()" in read(os.path.join(LUA, "main.lua")),
          "leaving the level no longer forgets a hold")
    # call() takes one value and spreads a list. A fourth argument is dropped
    # on the floor, which is how "Ask to join" went out as an invite.
    for m in re.finditer(r'call\(\s*"raceManager_\w+"\s*,\s*"\w+"\s*,(.*?)\);', js):
        args, depth, commas = m.group(1), 0, 0
        for ch in args:
            if ch in "([{": depth += 1
            elif ch in ")]}": depth -= 1
            elif ch == "," and depth == 0: commas += 1
        check(commas == 0, "app.js passes more than one value to call(): " + m.group(0).strip()[:80])
    # A user whose app sat in a small box in the middle of the screen had the
    # bars walk off with every restore. His build measures positions from the
    # app's own box, pins the box to the whole screen from inside the page,
    # nudges every bar back into view, and does not write a position down
    # while the box is a partial one. The game side is asked to mend the
    # layout file as well, so the box is right next time too.
    for name in ("rmDrag", "rmSpot", "rmMove"):
        body = re.search(r'\.directive\("%s"[\s\S]*?\n\}\]\)' % name, js)
        check(body is not None and "getBoundingClientRect().left" not in body.group(0)
              and "offsetLeft" in body.group(0),
              "%s measures from the screen instead of the app's box again" % name)
    move = re.search(r'\.directive\("rmMove"[\s\S]*?\n\}\]\)', js)
    check(move is not None and "hostW < window.innerWidth * 0.85" in move.group(0),
          "a bar position is written down while the app's box is a partial one again")
    check("function fitAllUi()" in js and 'scope.$on("rmFitScreen"' in js,
          "the box is no longer pinned to the whole screen from the page, or the bars no longer fitted after it")
    check("function watchBox()" in js and 'call("raceManager_layout", "arm", [wEm, hEm])' in js
          and "askForWholeScreen();" in js.split("function watchBox()")[1].split("var boxTimer")[0],
          "the app no longer asks for the whole screen back, in em, when its box is not the screen")
    uilua = read(os.path.join(LUA, "ui.lua"))
    check("function M.resetWindows()" in uilua and "raceManager_uifix.restore()" in uilua
          and 'guihooks.trigger("rmResetAsked"' in uilua and "rmResetAsked" in js,
          "!resetui no longer reaches the screen")
    uifix = read(os.path.join(LUA, "uifix.lua"))
    check("M._pendingRestoreAt" not in uifix and "function M.fit()" in uifix
          and "M.fit()" in uifix.split("function M.onUpdate")[1],
          "a join or a finished layout edit wipes everybody's saved positions again")
    check('if (data && data.fit) { fitAllUi(); return; }' in js,
          "the soft fit from the game side is treated as a full reset again")
    check("restoreUiLayout(true);" in js.split("$scope.resetPanels = function")[1].split("};")[0],
          "the Put the windows back button no longer resets the bars and the Stella too")
    check("rm-bar-grip" not in html and "rm-bar-grip" not in css,
          "a bar has a special handle on it again, and he asked for none: "
          "wherever a bar is taken hold of, it moves")
    check('if (tag === "input" || tag === "select") return;' in js
          and 'tag === "button"' not in js.split("var SLACK")[0].split("rmMove")[-1],
          "a press on a bar button is refused as a drag again")
    # his rule: courses from another map are not shown at all, and the list
    # says so when that leaves it empty
    check('t in trackList() track by t.id' in html and "No course on this map" in html,
          "the course list no longer says why it is empty on a map with no course")
    # The root is click-through so the world under it gets the mouse, and the
    # bars inherited that. Only their buttons could be pressed; the grip, the
    # badge and the gaps were nothing to the mouse. Two seconds of his
    # recording are the cursor on the grip and the bar staying put.
    check(re.search(r"\.rm-top,\s*\.rm-bottom\s*\{[^}]*pointer-events:\s*auto", css) is not None,
          "the bars are click-through again, so there is nothing to take hold of "
          "but the buttons")
    check("$scope.zoneAdd" in js and 'cap("setZones"' in js,
          "the speed zone tools are gone from the screen")

    # The Stella is in English. His own strings were Spanish and his i18n
    # only covers the labels, not the messages the car sends up.
    for path in ("client/lua/ge/extensions/bajaStella.lua",
                 "client/ui/modules/apps/BajaStella/app.js"):
        body = read(path)
        check(re.search(r"[\u00e1\u00e9\u00ed\u00f3\u00fa\u00f1\u00c1\u00c9\u00cd\u00d3\u00da\u00d1]", body) is None
              and not re.search(r"Veh[ií]culo|Adelantar|ADELANTAR|Confirmar|Asistencia", body),
              "%s has Spanish in it again" % path.split("/")[-1])

    # Hello used to stop for good after a fixed number of tries, and on a big
    # map every one of them went out before the session existed. Then nothing
    # came up on his screen at all. It slows down; it never stops.
    mainlua = read("client/lua/ge/extensions/raceManager/main.lua")
    check("GIVE_UP_AFTER" not in mainlua and "SLOW_EVERY" in mainlua,
          "main.lua gives up on hello again, which on a big map is before the map is up")
    laylua = read("client/lua/ge/extensions/raceManager/layout.lua")
    check("GIVE_UP" not in laylua and "onAServer" in laylua,
          "layout.lua gives up or only knows the layout named beammp again")

    svc = read("client/lua/ge/extensions/raceManager/service.lua")

    # A spare is a part swap. The first version let air back into a puncture
    # and only rebuilt for a tire past saving, and on his screen that was a
    # button that played its sounds and did nothing.
    job = re.search(r"local function doJob\(which, full\)(.*?)\nend\n", svc, re.S)
    check(job is not None and re.search(r'if which == "spare" then\s*return fitSpare\(', job.group(1)),
          "the spare job no longer swaps the part, so pressing it changes nothing you can see")
    check("setGroupPressure" not in svc,
          "service.lua lets air back into a tire again instead of fitting a spare")

    ask = re.search(r"local function askFlat\(\)(.*?)\nend\n", svc, re.S)
    check(ask is not None and "isRunning()" in ask.group(1) and "inPit()" in ask.group(1),
          "askFlat demands a flat tire whatever the race state, so the spare "
          "button does nothing on an empty server")
    check(ask is not None and "(wheels and wheels.wheels)" in ask.group(1),
          "the flat check reads through wheels without checking it is there, "
          "so a car without it never answers and the press dies silently")

    # The gate has to cover the line the capture car drove. Sliding it onto the
    # road's middle and leaving it there put gates beside the course.
    fitroad = re.search(r"function M\.fitRoad\(.*?\n(.*?)\nend\n", triggers, re.S)
    check(fitroad is not None and "math.min(0," in fitroad.group(1)
          and "math.max(0," in fitroad.group(1),
          "fitRoad no longer grows around the line that was driven, so a gate "
          "can end up beside the course again")

    # Every call("raceManager_x", "fn") in the interface has to land on a
    # function that exists. The re-rack button called one that was never
    # written and did nothing at all when pressed, which no test could see:
    # the lua suites load the server plugin and never touch client lua.
    targets = set(re.findall(
        r'call\(\s*"(raceManager_[a-z]+)"\s*,\s*"([A-Za-z_]\w*)"', js))

    # The bar does not name its function inline, it looks one up by button, so
    # the names in that table have to be read out of it. That table is exactly
    # where the missing one hid.
    table = re.search(
        r'var fn = \{(.*?)\}\[b\.key\];\s*if \(fn\) call\("(raceManager_[a-z]+)"',
        js, re.S)
    if table:
        for name in re.findall(r':\s*"([A-Za-z_]\w*)"', table.group(1)):
            targets.add((table.group(2), name))
    check(table is not None,
          "the bottom bar's button to lua table could not be read, so the "
          "names in it are no longer being checked")

    for mod, fn in sorted(targets):
        path = "client/lua/ge/extensions/raceManager/%s.lua" % mod.split("_", 1)[1]
        if not os.path.exists(path):
            check(False, "%s is called but there is no %s" % (mod, path))
            continue
        lua = io.open(path, encoding="utf-8").read()
        has = (re.search(r"function\s+M\.%s(?![A-Za-z0-9_])" % re.escape(fn), lua) or
               re.search(r"M\.%s\s*=" % re.escape(fn), lua))
        check(has is not None,
              "app.js calls %s.%s, which the lua does not define" % (mod, fn))

    print("%d checks" % checks[0])
    if problems:
        for p in problems:
            print("  FAIL  " + p)
        print("%d problem(s)" % len(problems))
        sys.exit(1)
    print("interface is consistent with itself")


main()
