#!/usr/bin/env python3
"""Write the code and the recorded answers of docs/guide.html from
src/examples/guide.

Each way of writing the same server has a package there: `ann` (annotations),
`fns` (one registration per capability) and `cls` (a type holding each
capability, implementing `Provider`). A block between `// guide:<name>` and
`// end` is a snippet. `check` sends the same requests to all three and fails
if they answer differently; what it prints is what the page records.

    python3 scripts/gen_guide.py           rewrite docs/guide.html
    python3 scripts/gen_guide.py --check   fail if the page is not what this writes
"""
import html
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "examples" / "guide"
GUIDE = ROOT / "docs" / "guide.html"

STYLES = ("annotations", "functions", "classes")


def snippets(path):
    """Every `// guide:<name>` block of `path`, with the indentation it shares
    removed."""
    text = (SRC / path).read_text(encoding="utf-8").replace("\r\n", "\n")
    out = {}
    for m in re.finditer(r"^( *)// guide:([a-z.]+)\n(.*?)^ *// end\n", text, re.S | re.M):
        indent = len(m.group(1))
        body = "\n".join(line[indent:] for line in m.group(3).rstrip("\n").split("\n"))
        out[m.group(2)] = body.lstrip("\n")
    return out


ANN = snippets("ann/tools.mbt")
FNS = snippets("fns/fns.mbt")
CLS = snippets("cls/cls.mbt")

# What each style has to say about itself in the sections where the others
# differ: a section a style cannot write is explained rather than left empty.
NOTES = {
    "first": {
        "annotations": "The generator reads these annotations at build time and writes the "
        "<code>register</code> call that makes each of them a tool. It is wired in once: a "
        "rule in <code>moon.mod</code> and a <code>dev_build</code> line in the package's "
        "<code>moon.pkg</code>.",
        "functions": "Each capability is one call on the server. This is what the annotations "
        "generate, and the form to reach for when a capability is decided at run time.",
        "classes": "The state lives in the struct and each method is the work of one tool; "
        "<code>impl Provider</code> says which of them the server offers. The server is handed "
        "the object, and asks it again whenever the tools are listed.",
    },
    "resources": {
        "annotations": "The URI is the annotation's argument. A URI with <code>{id}</code> in it "
        "makes a template, and the value it matched is read as the parameter's type.",
        "functions": "<code>resource</code> reads a fixed URI; <code>template</code> takes the "
        "parameters the URI matched.",
        "classes": "A resource and a template are two more methods of the object, offered "
        "through the same <code>impl</code>.",
    },
    "prompts": {
        "annotations": "The parameters of the annotated function become the prompt's arguments; "
        "an optional one may be left out of the call.",
        "functions": "<code>prompt</code> takes the renderer and the argument list a client "
        "shows before it fills the form in.",
        "classes": "The reviewer is a type with a method, offered through <code>impl "
        "Provider</code>.",
    },
    "context": {
        "annotations": "There is no annotation for a handler that wants the request: the "
        "generator registers the function it is given. Write these two forms instead — the "
        "annotation is the shorter way to say what they say.",
        "functions": "<code>tool_context</code> hands the handler the request it serves: its "
        "headers, the client's identity, its progress token, and the answers it sent back.",
        "classes": "The tool is built with <code>context_run_fn</code>, so the object's tools "
        "see the request too.",
    },
    "extend": {
        "annotations": "Nothing here is a declaration, so no annotation covers it: a transform "
        "and a layer are values handed to the server, or types the server is given. The two "
        "forms beside this one differ only in which.",
        "functions": "A transform and a layer are values: <code>add_transform</code> rewrites "
        "what the client is shown, <code>use_layer</code> puts code in front of every request.",
        "classes": "A transform is a contract, so the filter is a type of its own. A layer is a "
        "value either way, since it wraps a call rather than describing a component.",
    },
}


def recorded():
    """The check program's output, by section, and whether the three agree."""
    run = subprocess.run(
        ["moon", "run", "src/examples/guide/check", "--target", "native"],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
    )
    out = run.stdout
    if run.returncode != 0:
        sys.exit("the guide's check program failed:\n" + out + run.stderr)
    sections, name = {}, None
    for line in out.splitlines():
        mark = re.match(r"^\[([a-z]+)\]\s*(.*)$", line)
        if mark:
            name = mark.group(1)
            sections.setdefault(name, [])
            if mark.group(2):
                sections[name].append(mark.group(2))
        elif name and " -> " in line:
            sections[name].append(line)
    if sections.get("same") != ["true"]:
        sys.exit("the three ways of writing the guide answer differently:\n" + out)
    missing = {"common", "context", "extended"} - set(sections)
    if missing:
        sys.exit("the check program did not report " + ", ".join(sorted(missing)))
    return sections


def code(text):
    return (
        '<div class="code"><pre><code class="language-moonbit">'
        + html.escape(text, quote=False)
        + '</code></pre><button class="copy" type="button">copy</button></div>'
    )


def group(name):
    """The three variants of one section, in the order the switch lists them."""
    code_for = {"annotations": ANN.get(name), "functions": FNS.get(name), "classes": CLS.get(name)}
    parts = ['<div class="styles">']
    for style in STYLES:
        note = NOTES.get(name, {}).get(style)
        snippet = code_for[style]
        if snippet is None and not note:
            sys.exit("no %s snippet for the %s section" % (style, name))
        body = code(snippet) if snippet else ""
        note_html = '<p class="why">' + note + "</p>" if note else ""
        parts.append(
            '<div class="variant" data-style="%s">%s%s</div>' % (style, body, note_html)
        )
    parts.append("</div>")
    return "\n        ".join(parts)


def session(lines):
    rows = []
    for line in lines:
        label, _, answer = line.partition(" -> ")
        rows.append(
            '<span class="row"><span class="say">%s</span><span class="arrow">-&gt;</span>'
            '<span class="got">%s</span></span>'
            % (html.escape(label, quote=False), html.escape(answer, quote=False))
        )
    return '<div class="session">' + "".join(rows) + "</div>"


def fill(page, name, body):
    """Replace what is between `<!-- name -->` and `<!-- /name -->`."""
    open_tag = "<!-- %s -->" % name
    close_tag = "<!-- /%s -->" % name
    start = page.find(open_tag)
    if start < 0:
        sys.exit("docs/guide.html has no " + open_tag + " marker")
    end = page.find(close_tag, start)
    if end < 0:
        sys.exit("docs/guide.html has no " + close_tag + " marker")
    return page[: start + len(open_tag)] + "\n        " + body + "\n        " + page[end:]


def main():
    page = GUIDE.read_text(encoding="utf-8")
    got = recorded()
    common = got["common"]
    by_label = {}
    for line in common:
        by_label[line.partition(" -> ")[0]] = line
    new = page
    new = fill(new, "code:first", group("first"))
    new = fill(
        new,
        "out:first",
        session(
            [
                by_label["tools/list"],
                by_label['tools/call add {"a":2,"b":3}'],
                by_label['tools/call greet {"name":"leo","language":"zh"}'],
                by_label['tools/call unknown {"name":"nope"}'],
            ]
        ),
    )
    new = fill(new, "code:resources", group("resources"))
    new = fill(
        new,
        "out:resources",
        session(
            [
                by_label["resources/list"],
                by_label["resources/templates/list"],
                by_label['resources/read {"uri":"config://app"}'],
                by_label['resources/read {"uri":"users://7/profile"}'],
            ]
        ),
    )
    new = fill(new, "code:prompts", group("prompts"))
    new = fill(
        new,
        "out:prompts",
        session([by_label["prompts/list"], by_label['prompts/get review {"code":"fn f() { 1 }"}']]),
    )
    new = fill(new, "code:context", group("context"))
    new = fill(new, "out:context", session(got["context"]))
    new = fill(new, "code:extend", group("extend"))
    new = fill(new, "out:extend", session(got["extended"]))
    if "--check" in sys.argv:
        if new != page:
            sys.exit("docs/guide.html is out of date with src/examples/guide; run scripts/gen_guide.py")
        print("docs/guide.html is up to date")
        return
    GUIDE.write_text(new, encoding="utf-8", newline="\n")
    print("wrote docs/guide.html")


main()
