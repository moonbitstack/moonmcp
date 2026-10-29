#!/usr/bin/env python3
"""Generate the moonmcp API reference (docs/api.html) and the site numbers
(docs/assets/numbers.js) from the package interfaces.

Every public item in each package's `pkg.generated.mbti` is listed, so the page
can never drift from the code; descriptions come from `///` doc-comments in the
source, with short auto-descriptions for derived and wire-codec methods so that
every item carries a line. Reproducible: re-running yields byte-identical output,
which the Docs workflow checks with `git diff --exit-code`.
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# Packages that form the public, runtime API (no build-time tooling, no examples).
PACKAGES = [
    ("moonmcp", "moonmcp", "Facade", "The names a server is written with. Re-exports the server and the three capability types, plus argument decoding."),
    ("server", "server", "Server", "One server holds tools, resources, templates and prompts, and speaks both protocol eras over Streamable HTTP and stdio."),
    ("tools", "tools", "Tools", "A tool: a handler, an input schema, and a typed result."),
    ("resources", "resources", "Resources", "A resource: a URI and a reader. Templates fill a URI pattern from arguments."),
    ("prompts", "prompts", "Prompts", "A prompt: a renderer that turns arguments into messages."),
    ("types", "types", "Wire types", "The JSON-RPC and MCP data shapes, method constants and protocol-version helpers shared with the wire."),
    ("exceptions", "exceptions", "Errors", "The error type the handlers raise, and how it maps onto JSON-RPC error codes."),
    ("component", "component", "Component", "The shared metadata every capability carries: name, title, description, tags and icons."),
    ("tasks", "tasks", "Tasks", "Configuration for tools that hand long work to a task and answer later."),
    ("settings", "settings", "Settings", "Build-time settings surfaced to the running server."),
    ("config", "config", "Config", "Default ports and other knobs the server reads at start."),
    ("utilities", "utilities", "Utilities", "Small helpers, chiefly media-type handling for binary content."),
]

KIND_WORDS = re.compile(
    r"\b(pub|async|struct|enum|let|type|using|suberror|derive|impl|trait|alias|all|open)\b")


def read(p):
    try:
        return p.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def parse_mbti(path):
    """Return [(kind, signature, name)] in source order."""
    text = read(path)
    if not text:
        return []
    lines = text.splitlines()
    items = []
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if not (s.startswith("pub ") or s.startswith("pub(") or s.startswith("pub\t")):
            i += 1
            continue
        buf = s
        j = i + 1
        while j < len(lines):
            nxt = lines[j]
            ns = nxt.strip()
            if ns == "" or ns.startswith("//"):
                break
            if (nxt.startswith("pub ") or nxt.startswith("pub(")) and nxt[:1] != " ":
                break
            buf += "\n" + ns
            j += 1
        i = j
        kind, name = classify(buf)
        sig = " ".join(buf.split())
        items.append((kind, sig, name))
    return items


def count_pub_decls(path):
    """Number of public declarations in an mbti — each begins a line with `pub`."""
    n = 0
    for line in read(path).splitlines():
        s = line.strip()
        if s.startswith("pub ") or s.startswith("pub(") or s.startswith("pub\t"):
            n += 1
    return n


def target_files(pkgdir):
    """Target-specific sources whose public items the target-agnostic mbti omits."""
    d = SRC / pkgdir
    files = []
    for pat in ("*.native.mbt", "*.js.mbt", "*.wasm.mbt", "*.wasm-gc.mbt"):
        files.extend(sorted(d.glob(pat)))
    return files


def parse_pub_decls(path):
    """Public declarations in a source file, signature only (cut at `{` or `=`)."""
    items = []
    lines = read(path).splitlines()
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if not (s.startswith("pub ") or s.startswith("pub(")):
            i += 1
            continue
        sig = s
        j = i
        while j < len(lines):
            if "{" in sig:
                sig = sig.split("{", 1)[0]
                break
            if " = " in sig:
                sig = sig.split(" = ", 1)[0]
                break
            if j + 1 >= len(lines):
                break
            j += 1
            sig += " " + lines[j].strip()
        kind, name = classify(sig)
        items.append((kind, " ".join(sig.split()), name))
        i = j + 1
    return items


def classify(buf):
    if "suberror" in buf:
        kind = "error"
    elif "struct" in buf.split()[:2] or "pub(all) struct" in buf:
        kind = "struct"
    elif "pub(all) enum" in buf or "pub enum" in buf:
        kind = "enum"
    elif "pub let" in buf:
        kind = "let"
    elif "pub type" in buf:
        kind = "alias"
    elif "pub using" in buf:
        kind = "alias"
    elif "pub fn" in buf or "pub async fn" in buf:
        kind = "fn"
    else:
        kind = "item"
    # name: strip generic brackets, then find the identifier before the first '('
    b = re.sub(r"\[[^\]]*\]", " ", buf)
    m = re.search(r"::\s*([A-Za-z_]\w*)\s*\(", b)
    if not m:
        m = re.search(r"\b(?:fn|struct|enum|suberror|let|type|using)\b\s+([A-Za-z_]\w*)", b)
    if not m:
        m = re.search(r"\b([A-Za-z_]\w*)\s*\(", b)
    name = m.group(1) if m else (buf.split()[1] if len(buf.split()) > 1 else buf)
    return kind, name


def parse_source_comments(path):
    """Map a declaration name -> its preceding /// doc text."""
    text = read(path)
    docs = {}
    if not text:
        return docs
    lines = text.splitlines()
    doc = []
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("///"):
            if s == "///|":
                doc.append("")
            else:
                doc.append(s[3:].strip())
            i += 1
            continue
        if s.startswith("pub") or s.startswith("pub("):
            # gather the signature up to its opening brace
            sig = s
            j = i + 1
            while j < len(lines):
                ns = lines[j].strip()
                if "{" in ns and not ns.startswith("//"):
                    pre = ns.split("{", 1)[0].strip()
                    if pre:
                        sig += " " + pre
                    break
                if ns.startswith("//"):
                    break
                sig += " " + ns
                j += 1
            _, name = classify(sig)
            key = name
            mm = re.search(r"::([A-Za-z_][A-Za-z0-9_]*)\s*\(", sig)
            if mm:
                key = mm.group(1)
            if key and doc:
                docs[key] = " ".join(d.strip() for d in doc).strip()
            doc = []
            i = j
            continue
        doc = []
        i += 1
    return docs


AUTO = {
    "equal": "Equality with another value of the same type.",
    "not_equal": "Inequality with another value of the same type.",
    "to_repr": "Debug representation of this value.",
    "from_json": "Decode this shape from JSON.",
    "to_json": "Encode this shape to JSON.",
    "to_mcp_tool": "Project this tool to its wire `Tool` shape.",
    "to_mcp_resource": "Project this resource to its wire `Resource` shape.",
    "to_mcp_template": "Project this template to its wire `ResourceTemplate` shape.",
    "to_mcp_prompt": "Project this prompt to its wire `Prompt` shape.",
    "to_mcp_prompt_result": "Project this result to its wire `GetPromptResult` shape.",
    "to_mcp_result": "Project this result to its wire result shape.",
    "from_mcp_template": "Reconstruct a template from its wire `ResourceTemplate` shape.",
    "from_function": "Build a resource whose reader is the given function.",
    "base": "The shared component metadata.",
    "identifier": "The stable identifier used in listings.",
    "key": "The de-duplication key used in the registry.",
    "get_meta": "Arbitrary metadata carried with the component.",
    "convert_result": "Wrap a raw value as a typed result.",
    "dispatch": "Invoke the component's handler and return its result.",
    "run": "Run the tool's handler with the given arguments.",
    "render": "Render the prompt with the given arguments.",
    "read": "Read the resource's raw value.",
    "render_result": "Render and wrap the prompt as a result.",
    "read_result": "Read and wrap the resource as a result.",
    "matches": "Match a URI against this template, returning its variables.",
    "create_resource": "Build a concrete resource from a matched URI.",
    "resolve_security": "Resolve the effective security policy for a read.",
    "of_content": "Build a message from a single content block.",
    "text": "Build a message or resource from text.",
    "new": "Construct a value with the given fields.",
    "default": "The default value.",
    "validate": "Validate a request against this policy.",
    "message": "The human-readable message of the error.",
    "output": "Write the error to the given logger.",
    "to_string": "Render the error as a string.",
    "to_wire": "Encode this value to its wire string.",
    "verb": "The method name this request carries.",
    "progress_token": "The progress token carried in the request meta.",
    "uri": "The URI this content or reference points at.",
    "input_required": "Build a result that asks the client for more input.",
    "is_input_required": "Whether this result asks the client for more input.",
    "accept": "Accept an elicitation with the given content.",
    "cancel": "Cancel an elicitation.",
    "decline": "Decline an elicitation.",
    "error": "Build an error result with the given message.",
    "from_mcp_result": "Reconstruct a tool result from its wire shape.",
    "convert_to_content": "Decode a JSON value into content blocks.",
    "is_valid_tool_name": "Whether a string is a legal tool name.",
    "default_title": "A title derived from a tool name.",
}


def auto_desc(kind, name, sig):
    if name in AUTO:
        return AUTO[name]
    if kind == "struct":
        return "A data shape. The fields below are its wire and in-memory members."
    if kind == "enum":
        return "An alternative type. Each variant is listed below."
    if kind == "error":
        return "The error alternatives this type can carry."
    if kind == "let":
        return "A constant value."
    if kind == "alias":
        return "A re-exported name, defined in another package."
    return "A public item of this server framework."


def tint(sig):
    s = html.escape(sig)
    s = re.sub(r"\b(pub|async|struct|enum|let|type|using|suberror|derive|impl|trait|alias|all|open)\b",
                r'<span class="k">\1</span>', s)
    s = re.sub(r"\b([A-Z][A-Za-z0-9_]*)\b", r'<span class="ty">\1</span>', s)
    s = s.replace("-&gt;", '<span class="op">-&gt;</span>').replace("?", '<span class="op">?</span>')
    s = s.replace("::", '<span class="op">::</span>')
    return s


def clean_doc(t):
    """The site must not name other libraries (docs.md). The source's doc
    comments note one, so drop those notes from the rendered text only; the
    source itself is left untouched."""
    t = re.sub(r"\s*\(←\s*FastMCP'?s?.*?\)(?=\s*[:.;,])", "", t)
    t = re.sub(r"\s*\(←\s*FastMCP'?s?[^)]*\)", "", t)
    t = re.sub(r"\s*←\s*FastMCP'?s?[^)]*\)?", "", t)
    t = t.replace("FastMCP-namespaced", "Namespaced")
    t = re.sub(r"\bFastMCP-specific\s+", "", t)
    t = re.sub(r"FastMCP(?!Meta)", "MCP", t)
    t = re.sub(r"\s{2,}", " ", t).strip()
    if t and t[0].islower():
        t = t[0].upper() + t[1:]
    return t


def prose(t):
    t = clean_doc(t)
    t = html.escape(t)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", t)


def gem_legend():
    return ('<p class="pdesc">Three capability kinds give the reference its colours: '
            '<span class="gem gem-jade"></span> <b class="t-jade">tools</b>, '
            '<span class="gem gem-amber"></span> <b class="t-amber">resources</b>, '
            '<span class="gem gem-amethyst"></span> <b class="t-amethyst">prompts</b>. '
            'Everything else is the server, the wire, or the errors in between.</p>')


def main():
    # gather items per package and count coverage
    sections = []
    total = 0
    covered = 0
    for pkgdir, pkgname, title, desc in PACKAGES:
        mbti = SRC / pkgdir / "pkg.generated.mbti"
        src_candidates = sorted((SRC / pkgdir).glob("*.mbt"))
        docs = {}
        for sc in src_candidates:
            docs.update(parse_source_comments(sc))
        items = parse_mbti(mbti)
        declared = count_pub_decls(mbti)
        if len(items) != declared:
            raise SystemExit(
                "gen_api: %s lists %d of %d public declarations; the reference would be incomplete"
                % (pkgdir, len(items), declared))
        # the committed mbti is target-agnostic; add native/js-only public items
        have = {(k, n) for k, _, n in items}
        for tf in target_files(pkgdir):
            for kind, sig, name in parse_pub_decls(tf):
                if (kind, name) not in have:
                    items.append((kind, sig, name))
                    have.add((kind, name))
        rows = []
        for kind, sig, name in items:
            d = docs.get(name)
            if d is None:
                d = docs.get(sig.split("::")[-1].split("(")[0]) if "::" in sig else None
            if d:
                covered += 1
            else:
                d = auto_desc(kind, name, sig)
            rows.append((kind, sig, d))
        total += len(items)
        sections.append((pkgname, title, desc, rows))

    # numbers.js
    numbers = {
        "public_items": total,
        "tests": count_tests(),
        "packages": len(PACKAGES),
        "eras": 3,
        "transports": 2,
        "capability_kinds": 3,
    }
    (ROOT / "docs" / "assets").mkdir(parents=True, exist_ok=True)
    (ROOT / "docs" / "assets" / "numbers.js").write_text(
        "window.MOONMCP_NUMBERS = " + __import__("json").dumps(numbers) + ";\n", encoding="utf-8", newline="\n")

    # api.html
    side = ['<aside class="sidebar"><p class="side-title">Armillary · moonmcp</p><nav class="side-nav">']
    for pkgname, title, _, _ in sections:
        side.append('<a href="#pkg-%s">%s</a>' % (pkgname, title))
    side.append('</nav><div class="side-foot" style="margin-top:1.4rem">'
                '<a class="ghost" href="index.html">Home</a> '
                '<a class="ghost" href="guide.html">Guide</a> '
                '<a class="ghost" href="showcase.html">Showcase</a></div></aside>')

    head = ('<!doctype html><html lang="en" data-theme="dark"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<script>document.documentElement.classList.add("js")</script>'
            '<title>moonmcp — API reference</title>'
            '<meta name="description" content="The complete public API of moonmcp, a Model Context Protocol server framework for MoonBit.">'
            '<link rel="icon" href="assets/favicon.svg" type="image/svg+xml">'
            '<link rel="preconnect" href="https://fonts.googleapis.com">'
            '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
            '<link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400;9..144,500;9..144,600&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&family=Noto+Serif+SC:wght@400;600&display=swap" rel="stylesheet">'
            '<link rel="stylesheet" href="assets/armillary.css"></head><body>')

    nav = ('<nav class="nav"><a class="brand" href="index.html">'
           '<svg class="glyph" viewBox="0 0 32 32" aria-hidden="true"><g fill="none" stroke="#D4B87A" stroke-width="1.1"><circle cx="16" cy="16" r="11"/><ellipse cx="16" cy="16" rx="11" ry="4.4"/><ellipse cx="16" cy="16" rx="4.4" ry="11"/></g><circle cx="16" cy="16" r="3.4" fill="#FFF8E8"/></svg>'
           'moonmcp</a><div class="links">'
           '<a href="index.html">Home</a><a href="guide.html">Guide</a>'
           '<a href="api.html" class="active">API</a><a href="showcase.html">Showcase</a>'
           '<a class="ghost theme-btn" data-theme-toggle href="#" aria-label="Toggle theme">&#9688; theme</a>'
           '<a class="ghost" href="https://github.com/moonbitstack/moonmcp">GitHub &#8599;</a></div></nav>')

    main_html = ['<main class="doc"><header>'
                 '<div class="kicker">Reference</div>'
                 '<h1 class="doc-h1">The public surface</h1>'
                 '<p class="lead">Every type, function, method and value moonmcp exposes, drawn straight from the compiled package interfaces. '
                 'Generated from source &mdash; it cannot drift from the code.</p>']
    main_html.append(gem_legend())
    main_html.append('</header>')
    main_html.append('<div class="rule"><span class="node"></span></div>')

    for pkgname, title, desc, rows in sections:
        main_html.append('<section class="section" id="pkg-%s"><h2>%s</h2><p class="pdesc">%s</p>'
                         % (pkgname, title, prose(desc)))
        for kind, sig, d in rows:
            main_html.append('<div class="item" data-k="%s"><span class="kind">%s</span>'
                             '<pre class="sig">%s</pre>%s</div>'
                             % (kind, kind, tint(sig), ('<p class="doc">%s</p>' % prose(d)) if d else ''))
        main_html.append('</section>')

    main_html.append('<footer class="site"><span>moonmcp &middot; API reference</span>'
                     '<span class="grow"></span>'
                     '<a href="https://github.com/moonbitstack/moonmcp">GitHub</a>'
                     '<a href="https://mooncakes.io/docs/moonbitstack/moonmcp">mooncakes</a>'
                     '<span>Apache-2.0</span></footer>')
    main_html.append('</main>')

    doc = "\n".join([head, nav, '<div class="shell">'] + side + main_html + ['</div>',
                 '<script src="assets/armillary.js"></script>', '</body></html>'])

    out = ROOT / "docs" / "api.html"
    out.write_text(doc + "\n", encoding="utf-8", newline="\n")

    print("api.html: %d public items across %d packages (%d had a source doc, %d auto-described)"
          % (total, len(sections), covered, total - covered))
    print("numbers.js:", numbers)


def count_tests():
    n = 0
    for p in SRC.rglob("*_test.mbt"):
        for line in p.read_text(encoding="utf-8").splitlines():
            if re.match(r"\s*test\s+\"", line):
                n += 1
    return n


if __name__ == "__main__":
    main()
