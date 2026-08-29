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


def template_calls(html):
    """Every function the template calls, from any angular attribute."""
    out = set()
    for attr in re.findall(r'ng-(?:click|if|disabled|class|change|keydown|options|repeat|model)="([^"]*)"', html):
        for name in re.findall(r"\b([a-zA-Z_]\w*)\s*\(", attr):
            out.add(name)
    for expr in re.findall(r"\{\{([^}]*)\}\}", html):
        for name in re.findall(r"\b([a-zA-Z_]\w*)\s*\(", expr):
            out.add(name)
    return out


def template_roots(html):
    """Top level scope names the template reads, so a typo shows up."""
    out = set()
    blob = " ".join(re.findall(r'ng-\w+="([^"]*)"', html))
    blob += " " + " ".join(re.findall(r"\{\{([^}]*)\}\}", html))
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
    known = scope_functions(js) | scope_values(js) | {
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
    # a gate met off square is a narrower hole than its width says, so corners
    # are widened to put the gap back. drop this call and every corner quietly
    # goes back to being scored from the middle only.
    build = re.search(r"function M\.build\(.*?\nend\n", triggers, re.S)
    check(build is not None and "fitTurns(" in build.group(0),
          "M.build does not fit the gates to the turns, so corner gates narrow again")

    for fn in ("spawnGate", "drawGate"):
        body = re.search(r"local function %s\(.*?\n(.*?)\nend\n" % fn, triggers, re.S)
        check(body is not None and "gateBox(cp)" in body.group(1),
              "%s does not build its gate from gateBox, so the volume and the "
              "posts can drift apart again" % fn)

    print("%d checks" % checks[0])
    if problems:
        for p in problems:
            print("  FAIL  " + p)
        print("%d problem(s)" % len(problems))
        sys.exit(1)
    print("interface is consistent with itself")


main()
