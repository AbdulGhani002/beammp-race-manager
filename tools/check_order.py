#!/usr/bin/env python3
"""A local in lua is only visible below where it is written.

A function defined above one it calls parses perfectly and then dies the first
time the button is pressed, with "attempt to call global X (a nil value)". That
shipped once. Nothing else here can see it: the lua tests only load the server
plugin, and check_ui only reads names the interface binds to.

    python tools/check_order.py
"""

import io
import os
import re
import sys

ROOTS = ["client/lua/ge/extensions/raceManager"]

# file scope only, so a local inside a function body is not mistaken for one
DECL_FUNC = re.compile(r"^local\s+function\s+([A-Za-z_]\w*)")
DECL_VARS = re.compile(r"^local\s+([A-Za-z_][\w\s,]*?)\s*(?:=|$)")
WORD = re.compile(r"[A-Za-z_]\w*")


def strip_noise(line):
    """Drop comments and string bodies so names inside them are not counted."""
    line = re.sub(r"--\[\[.*?\]\]", " ", line)
    line = re.sub(r"--.*$", "", line)
    line = re.sub(r'"[^"]*"', '""', line)
    line = re.sub(r"'[^']*'", "''", line)
    return line


def check(path):
    text = io.open(path, encoding="utf-8").read()

    # a long string spanning lines holds vehicle lua, not ours
    text = re.sub(r"\[\[.*?\]\]", "[[]]", text, flags=re.S)
    lines = text.split("\n")

    declared = {}
    for i, raw in enumerate(lines, 1):
        line = strip_noise(raw)
        m = DECL_FUNC.match(line)
        if m:
            declared.setdefault(m.group(1), i)
            continue
        m = DECL_VARS.match(line)
        if m:
            for name in m.group(1).split(","):
                name = name.strip()
                if name:
                    declared.setdefault(name, i)

    problems = []
    for i, raw in enumerate(lines, 1):
        line = strip_noise(raw)
        if DECL_FUNC.match(line) or DECL_VARS.match(line):
            continue
        for name in set(WORD.findall(line)):
            at = declared.get(name)
            if at is not None and i < at:
                problems.append(
                    "%s:%d uses %s, which is not declared until line %d"
                    % (os.path.relpath(path).replace("\\", "/"), i, name, at))
    return problems


def main():
    files, problems = 0, []
    for root in ROOTS:
        for name in sorted(os.listdir(root)):
            if name.endswith(".lua"):
                files += 1
                problems += check(os.path.join(root, name))

    print("%d client lua files checked for use before declaration" % files)
    if not problems:
        print("every local is written above the code that uses it")
        return 0
    for p in problems:
        print("  FAIL  " + p)
    print("%d problem(s)" % len(problems))
    return 1


if __name__ == "__main__":
    sys.exit(main())
