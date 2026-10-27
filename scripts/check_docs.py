"""Compile every MoonBit block of the documentation against this module, so the
README and the docs cannot drift from the code. Read: README.md, every .md
under docs/, and every <code class="language-moonbit"> block of the .html
pages under docs/. Blocks in any other language are not read.

A fragment, pseudo-code, or anything not meant to compile is marked and
skipped: an HTML comment `<!-- nocheck -->` just before the block (it does not
show on the rendered page), ```moonbit nocheck in Markdown, or a nocheck class
on the <code>.

A block with `fn main` becomes a program, one with top-level definitions a
library, and anything else the body of a function. Each `@alias.` it uses is
resolved to a package of this module, of a dependency, or of core.

Usage, from the repository root: python scripts/check_docs.py"""
import html
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def manifest(path):
    text = path.read_text(encoding="utf-8")
    name = re.search(r'^name\s*=\s*"([^"]+)"', text, re.M).group(1)
    source = re.search(r'^source\s*=\s*"([^"]+)"', text, re.M)
    deps = re.findall(r'"([\w.-]+/[\w./-]+)@[^"]*"', text)
    return name, (source.group(1) if source else "."), deps


def packages(module, base, into):
    """Every package under `base` of `module`, by the alias it is used under."""
    for pkg in sorted(base.rglob("moon.pkg")) + sorted(base.rglob("moon.pkg.json")):
        rel = pkg.parent.relative_to(base).as_posix()
        if any(part.startswith(("_", ".")) for part in pkg.parent.relative_to(base).parts):
            continue
        path = module if rel == "." else f"{module}/{rel}"
        into.setdefault(path.rsplit("/", 1)[-1], path)


def aliases():
    name, source, deps = manifest(ROOT / "moon.mod")
    found = {}
    packages(name, ROOT / source, found)
    for dep in deps:
        home = ROOT / ".mooncakes" / dep
        if (home / "moon.mod").exists():
            _, dep_source, _ = manifest(home / "moon.mod")
            packages(dep, home / dep_source, found)
    core = pathlib.Path.home() / ".moon" / "lib" / "core"
    if core.exists():
        packages("moonbitlang/core", core, found)
    return found


SKIP = r"(<!--\s*nocheck\s*-->\s*)?"
FENCE = re.compile(SKIP + r"```(?:moonbit|mbt)([^\n]*)\n(.*?)```", re.S)
CODE = re.compile(
    SKIP + r'(?:<pre[^>]*>\s*)?<code([^>]*class="[^"]*language-(?:moonbit|mbt)[^"]*"[^>]*)>(.*?)</code>',
    re.S,
)
TOP = re.compile(r"^(?:pub(?:\([a-z]+\))?\s+)?(?:async\s+)?(?:fn|struct|enum|let|const|test|impl|trait|type|suberror|extern|///\|)\b", re.M)


def blocks():
    found = []
    for md in [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]:
        if md.exists():
            text = md.read_text(encoding="utf-8")
            for marked, info, code in FENCE.findall(text):
                if not marked and "nocheck" not in info:
                    found.append((md, code))
    for page in sorted((ROOT / "docs").rglob("*.html")):
        text = page.read_text(encoding="utf-8")
        for marked, attrs, code in CODE.findall(text):
            if not marked and "nocheck" not in attrs:
                found.append((page, html.unescape(re.sub(r"<[^>]+>", "", code))))
    return found


def package_for(code, known):
    imports = []
    if re.search(r"\basync\b", code):
        imports.append("moonbitlang/async")
    for alias in sorted(set(re.findall(r"@(\w+)\.", code))):
        if alias in known and known[alias] not in imports:
            imports.append(known[alias])
    lines = ["import {"] + [f'  "{name}",' for name in imports] + ["}", ""]
    if re.search(r"\bfn main\b", code):
        lines += ['pkgtype(kind: "executable")', ""]
    lines += ['warnings = "-1-2-29-67"', ""]
    return "\n".join(lines)


def source_for(code):
    if re.search(r"\bfn main\b", code) or TOP.search(code):
        return "///|\n" + code
    body = "\n".join("    " + line for line in code.splitlines())
    return "///|\nasync fn snippet() -> Unit {\n  let _ = {\n" + body + "\n  }\n}\n"


def main():
    found = blocks()
    if not found:
        print("no MoonBit blocks in the documentation")
        return
    known = aliases()
    _, source, _ = manifest(ROOT / "moon.mod")
    made = []
    try:
        for i, (origin, code) in enumerate(found):
            pkg = ROOT / source / f"_doc{i}"
            pkg.mkdir()
            made.append(pkg)
            (pkg / "moon.pkg").write_text(package_for(code, known), encoding="utf-8")
            (pkg / "main.mbt").write_text(
                f"// {origin.relative_to(ROOT).as_posix()}\n" + source_for(code),
                encoding="utf-8",
            )
        result = subprocess.run(["moon", "check", "--target", "native"], cwd=ROOT)
    finally:
        for pkg in made:
            shutil.rmtree(pkg, ignore_errors=True)
    print(f"{len(found)} documentation block(s) checked")
    sys.exit(result.returncode)


main()
