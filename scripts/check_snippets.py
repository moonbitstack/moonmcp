"""Compile every MoonBit block in README.md and docs/skills/*/SKILL.md against this module's source.

A reader pastes these blocks into a project, so each one has to compile as written. The blocks of
one file are read in order, the way the page reads: a block may use a name that an earlier block of
the same file defined. `<!-- nocheck -->` on the line above a block skips it; a block opened with
```` ```mbt native ```` is checked on the native target only.

The library carries no server, so a block that serves over HTTP names a package that only
`integration/` depends on. Those blocks are built in `integration/`, the module that carries one; the
rest are built here.

Usage: python scripts/check_snippets.py [--moon moon] [file ...]
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ECOSYSTEM = ROOT / "integration"
FENCE = re.compile(r"(<!--\s*nocheck\s*-->[ \t]*\n)?```(mbt|moonbit)([^\n]*)\n(.*?)^```", re.S | re.M)
TOP = re.compile(r"^(pub(\([a-z]+\))? |priv |fn |async fn |test |async test |struct |enum |suberror |impl |trait |typealias |type |extern |#[a-z])", re.M)
NAMED = re.compile(r"^(?:pub(?:\([a-z]+\))? )?(?:async )?fn ([A-Za-z_][A-Za-z0-9_]*)", re.M)
CORE = {"array", "bench", "bigint", "buffer", "builtin", "bytes", "char", "cmp", "coverage", "deque", "double", "encoding", "env", "error", "float", "hashmap", "hashset", "immut", "int", "int16", "int64", "json", "list", "math", "option", "queue", "quickcheck", "random", "rational", "ref", "result", "set", "sorted_map", "sorted_set", "strconv", "string", "test", "tuple", "uint", "uint16", "uint64", "unit"}
NESTED = {"utf8": "encoding/utf8", "utf16": "encoding/utf16"}


def module_info(home):
    text = (home / "moon.mod").read_text(encoding="utf-8")
    name = re.search(r'name\s*=\s*"([^"]+)"', text).group(1)
    source = re.search(r'source\s*=\s*"([^"]+)"', text)
    deps = re.findall(r'"([\w-]+/[\w-]+)@[\d.]+"', text)
    return name, home / (source.group(1) if source else "."), deps


def packages(home):
    """Alias to package path: the module at `home` first, then what its dependencies publish.

    A dependency on this repository's own module is the source tree beside it, not the copy on the
    registry, so its packages are read from `src/`.
    """
    module, src, deps = module_info(home)
    own = module_info(ROOT)[0]
    found = {}
    for pkg in sorted(src.rglob("moon.pkg")):
        rel = pkg.parent.relative_to(src).as_posix()
        if rel.startswith(("_snippet", "snippet_check")) or "examples" in rel.split("/") or "internal" in rel.split("/"):
            continue
        path = module if rel == "." else f"{module}/{rel}"
        found.setdefault(path.rsplit("/", 1)[-1], path)
    for dep in deps:
        found.setdefault(dep.rsplit("/", 1)[-1], dep)
        if dep == own:
            for pkg in sorted((ROOT / "src").rglob("moon.pkg")):
                rel = pkg.parent.relative_to(ROOT / "src").as_posix()
                if rel != "." and "examples" not in rel.split("/") and "internal" not in rel.split("/"):
                    found.setdefault(rel.rsplit("/", 1)[-1], f"{dep}/{rel}")
            continue
        root = home / ".mooncakes" / dep
        if root.is_dir():
            mod = (root / "moon.mod").read_text(encoding="utf-8") if (root / "moon.mod").exists() else ""
            m = re.search(r'source\s*=\s*"([^"]+)"', mod)
            base = root / (m.group(1) if m else ".")
            for pkg in sorted(base.rglob("moon.pkg")):
                rel = pkg.parent.relative_to(base).as_posix()
                if rel != "." and "internal" not in rel.split("/"):
                    found.setdefault(rel.rsplit("/", 1)[-1], f"{dep}/{rel}")
    return found


def blocks(path):
    text = path.read_text(encoding="utf-8")
    for m in FENCE.finditer(text):
        if m.group(1) or "nocheck" in m.group(3):
            continue
        # The contents of a `moon.pkg` or `moon.mod` shown in a block are configuration, not code.
        if re.match(r"(?:\s*//[^\n]*\n)*\s*(import \{|options\(|name\s*=|pkgtype\()", m.group(4)):
            continue
        yield text[: m.start(4)].count("\n") + 1, "native" in m.group(3), m.group(4)


def wrapped(body):
    """One block as a package of its own: a block of statements becomes the body of a function, and a
    block of declarations is written as it is."""
    if TOP.search(body):
        return body.rstrip("\n") + "\n"
    inner = "\n".join("  " + line for line in body.rstrip("\n").splitlines())
    return f"async fn snippet() -> Unit raise {{\n{inner}\n}}\n"


def parts(items, homes):
    """The blocks of one file and target, split by the module that has to build them, and by whether
    the block is a program: an `async fn main` is the platform's to provide, so it is checked where the
    runtime that starts one exists."""
    here = homes["here"][1]
    elsewhere = homes.get("ecosystem", (ROOT, {}))[1]
    out = {}
    for line, body in items:
        used = set(re.findall(r"@([a-z_][a-z0-9_]*)\.", body))
        name = "ecosystem" if any(a in elsewhere and a not in here for a in used) else "here"
        program_ = re.search(r"^async fn main\b", body, re.M) is not None
        out.setdefault((name, program_), []).append((line, body))
    return out.items()


def errors_by_package(out, count):
    """The first error message of each block's package, by block index."""
    found = {}
    for chunk in re.split(r"(?=Error: \[\d+\]|Warning: \[\d+\])", out):
        if not chunk.startswith("Error: ["):
            continue
        where = re.search(r"_snippet[\\/](\d+)[\\/]snippets\.mbt:(\d+)", chunk)
        if not where:
            continue
        index = int(where.group(1))
        if index >= count or index in found:
            continue
        message = None
        for line in chunk.splitlines():
            mark = line.find("╰")
            if mark >= 0:
                message = line[mark + 1 :].lstrip("─┬ ")
                if message:
                    break
        if message is None:
            message = chunk.splitlines()[0]
        found[index] = message.strip()
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--moon", default="moon")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()
    module, src, deps = module_info(ROOT)
    if module.endswith("CHANGE-ME"):
        print("the template itself: nothing to check until CHANGE-ME is replaced")
        return 0
    homes = {"here": (ROOT, packages(ROOT))}
    if (ECOSYSTEM / "moon.mod").exists():
        homes["ecosystem"] = (ECOSYSTEM, packages(ECOSYSTEM))
    files = [Path(f) for f in args.files] or [ROOT / "README.md", *sorted((ROOT / "docs" / "skills").glob("*/SKILL.md"))]
    failed = 0
    updated = set()
    for file in files:
        file = file if file.is_absolute() else ROOT / file
        if not file.exists():
            continue
        found = list(blocks(file))
        for native in (False, True):
            items = [(line, body) for line, nat, body in found if nat == native]
            if not items:
                continue
            for (name, program_), group in parts(items, homes):
                home, aliases = homes[name]
                if home not in updated:
                    subprocess.run([args.moon, "update"], cwd=home, capture_output=True)
                    updated.add(home)
                # `_snippet` is ignored by `.gitignore`, so a run cut short cannot leave the tree dirty.
                pkg = module_info(home)[1] / "_snippet"
                shutil.rmtree(pkg, ignore_errors=True)
                pkg.mkdir(parents=True)
                written = []
                for index, (line, body) in enumerate(group):
                    code = wrapped(body)
                    used = set(re.findall(r"@([a-z_][a-z0-9_]*)\.", code))
                    imports = sorted({aliases[a] for a in used if a in aliases} | {f"moonbitlang/core/{a}" for a in used if a not in aliases and a in CORE} | {f"moonbitlang/core/{NESTED[a]}" for a in used if a not in aliases and a in NESTED})
                    if re.search(r"\basync (fn main|test)\b", code) and "moonbitlang/async" not in imports:
                        imports.append("moonbitlang/async")
                    at = pkg / str(index)
                    at.mkdir()
                    head = "import {\n" + "".join(f'  "{it}",\n' for it in imports) + "}\n" if imports else ""
                    if re.search(r"^(async )?fn main\b", code, re.M):
                        head += '\noptions("is-main": true)\n'
                    (at / "moon.pkg").write_text(head, encoding="utf-8", newline="\n")
                    (at / "snippets.mbt").write_text(code, encoding="utf-8", newline="\n")
                    written.append((index, line))
                target = "native" if native or program_ else "all"
                paths = [str((pkg / str(index)).relative_to(home)) for index, _ in written]
                try:
                    r = subprocess.run([args.moon, "check", "--target", target, *paths], cwd=home, capture_output=True, text=True, encoding="utf-8", errors="replace")
                finally:
                    shutil.rmtree(pkg, ignore_errors=True)
                    if pkg.exists():
                        print(f"{pkg} could not be removed; the next run starts from a clean one")
                        sys.exit(1)
                bad = errors_by_package(r.stdout + r.stderr, len(written))
                if r.returncode and not bad:
                    out = (r.stdout + r.stderr).strip()
                    bad = {0: out.splitlines()[-1] if out else "moon check failed"}
                for index, line in written:
                    if index in bad:
                        print(f"{file.relative_to(ROOT).as_posix()}:{line}: {bad[index]}")
                failed += len(bad)
                if not bad:
                    print(f"{file.relative_to(ROOT).as_posix()}: {len(written)} {target} blocks compile in {home.name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
