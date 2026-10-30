// The debug page: one HTML document with its own style and script, served by
// `Server::to_asgi` at a path of the program's choosing. Nothing on it is
// rendered on the server, so the file is a constant and the browser does the
// listing and the calling itself; the only thing the server splices in is the
// endpoint to talk to, as JSON, so that no path can break out of the script.

///|
/// The page, up to the endpoint the script is told to call.
let debug_page_head : String =
  #|<!doctype html>
  #|<html lang="en">
  #|<head>
  #|<meta charset="utf-8">
  #|<meta name="viewport" content="width=device-width,initial-scale=1">
  #|<title>moonmcp debug</title>
  #|<meta name="robots" content="noindex">
  #|<link rel="icon" href="data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20viewBox='0%200%2032%2032'%3E%3Crect%20width='32'%20height='32'%20rx='6'%20fill='%23241A12'/%3E%3Ccircle%20cx='16'%20cy='16'%20r='9'%20fill='none'%20stroke='%23C98A4B'%20stroke-width='1.6'/%3E%3Ccircle%20cx='16'%20cy='16'%20r='3.2'%20fill='%23D97A2B'/%3E%3C/svg%3E">
  #|<link rel="preconnect" href="https://fonts.googleapis.com">
  #|<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  #|<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&family=JetBrains+Mono:wght@400;500&family=Noto+Serif+SC:wght@400;600&display=swap">
  #|<style>
  #|:root{
  #|  --bg:#E8E0D4;--panel:#FBF6EC;--panel-2:#F1E8D6;--ink:#241A12;--muted:#5B4A38;--line:rgba(36,26,18,.2);
  #|  --accent:#8B5A3C;--accent-soft:rgba(139,90,60,.12);--out:#3F6B54;--bad:#8E2B2B;
  #|  --code-bg:#271c14;--code-ink:#F8EFDC;
  #|  --bar:#241A12;--bar-ink:#F1E7D4;--bar-line:#120c07;--bar-muted:#C0AE91;
  #|  --shadow:0 2px 4px rgba(60,45,25,.14),0 22px 48px -30px rgba(60,45,25,.45);
  #|}
  #|@media (prefers-color-scheme:dark){:root{
  #|  --bg:#191309;--panel:#F3EAD8;--panel-2:#E7DCC4;--ink:#241A12;--muted:#5B4A38;--line:rgba(36,26,18,.24);
  #|  --accent:#7E4A2E;--accent-soft:rgba(120,70,40,.14);--out:#3F6B54;--bad:#8E2B2B;
  #|  --code-bg:#241a10;--code-ink:#F8EFDC;
  #|  --bar:#150F08;--bar-ink:#F1E7D4;--bar-line:#080503;--bar-muted:#C0AE91;
  #|  --shadow:0 2px 4px rgba(0,0,0,.45),0 26px 54px -28px rgba(0,0,0,.85);
  #|}}
  #|:root[data-theme=light]{--bg:#E8E0D4;--panel:#FBF6EC;--panel-2:#F1E8D6;--ink:#241A12;--muted:#5B4A38;--line:rgba(36,26,18,.2);--accent:#8B5A3C;--accent-soft:rgba(139,90,60,.12);--out:#3F6B54;--bad:#8E2B2B;--code-bg:#271c14;--code-ink:#F8EFDC;--bar:#241A12;--bar-ink:#F1E7D4;--bar-line:#120c07;--bar-muted:#C0AE91;--shadow:0 2px 4px rgba(60,45,25,.14),0 22px 48px -30px rgba(60,45,25,.45)}
  #|:root[data-theme=dark]{--bg:#191309;--panel:#F3EAD8;--panel-2:#E7DCC4;--ink:#241A12;--muted:#5B4A38;--line:rgba(36,26,18,.24);--accent:#7E4A2E;--accent-soft:rgba(120,70,40,.14);--out:#3F6B54;--bad:#8E2B2B;--code-bg:#241a10;--code-ink:#F8EFDC;--bar:#150F08;--bar-ink:#F1E7D4;--bar-line:#080503;--bar-muted:#C0AE91;--shadow:0 2px 4px rgba(0,0,0,.45),0 26px 54px -28px rgba(0,0,0,.85)}
  #|*{box-sizing:border-box}
  #|html,button,input,textarea,select{font-variant-ligatures:no-contextual}
  #|body{margin:0;background:var(--bg);color:var(--ink);
  #|  font-family:"Source Serif 4","Noto Serif SC",Georgia,serif;font-size:16px;line-height:1.65;-webkit-font-smoothing:antialiased}
  #|h1,h2,h3{margin:0;font-family:"Cormorant Garamond","Noto Serif SC",Georgia,serif;font-weight:600;letter-spacing:.005em}
  #|code,pre,textarea,.mono{font-family:"JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
  #|a{color:var(--accent)}
  #|.bar{position:sticky;top:0;z-index:5;display:flex;align-items:center;gap:.6rem;flex-wrap:wrap;
  #|  padding:.6rem 1rem;background:linear-gradient(180deg,rgba(255,255,255,.05),transparent 40%),var(--bar);
  #|  color:var(--bar-ink);border-bottom:2px solid var(--bar-line);
  #|  box-shadow:0 2px 0 rgba(0,0,0,.45),0 10px 26px -14px rgba(0,0,0,.8)}
  #|.brand{display:flex;align-items:center;gap:.5rem;font-family:"Cormorant Garamond",serif;font-size:1.18rem;color:var(--bar-ink)}
  #|.brand svg{width:22px;height:22px;display:block;flex:none}
  #|.brand .sub{color:var(--bar-muted);font-family:"JetBrains Mono",monospace;font-weight:400;font-size:.6rem;
  #|  text-transform:uppercase;letter-spacing:.22em}
  #|.grow{flex:1 1 auto;min-width:0}
  #|.ep{font-family:"JetBrains Mono",monospace;font-size:.78rem;color:#E4D3B4;background:rgba(0,0,0,.38);
  #|  border:1px solid rgba(255,255,255,.14);border-radius:4px;padding:.15rem .45rem;overflow-wrap:anywhere}
  #|.ctl{display:flex;align-items:center;gap:.35rem;font-family:"JetBrains Mono",monospace;font-size:.62rem;
  #|  text-transform:uppercase;letter-spacing:.14em;color:var(--bar-muted)}
  #|select,input[type=text],textarea{font:inherit;font-size:.9rem;color:var(--ink);background:var(--panel);
  #|  border:1px solid var(--line);border-radius:4px;padding:.3rem .5rem;min-width:0;max-width:100%}
  #|select{text-transform:none;letter-spacing:0;font-family:"JetBrains Mono",monospace;font-size:.78rem}
  #|textarea{width:100%;resize:vertical}
  #|select:focus-visible,input:focus-visible,textarea:focus-visible,button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
  #|.btn{font:inherit;font-family:"JetBrains Mono",monospace;font-size:.66rem;text-transform:uppercase;letter-spacing:.12em;
  #|  color:var(--bar-ink);background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.18);
  #|  border-radius:4px;padding:.3rem .6rem;cursor:pointer;box-shadow:inset 0 1px 0 rgba(255,255,255,.12)}
  #|.btn:hover{border-color:var(--accent);color:#fff}
  #|.btn.primary{background:linear-gradient(180deg,#C98A4B,#8B5A3C);border-color:#5E3A24;color:#FFF6E4;
  #|  box-shadow:inset 0 1px 0 rgba(255,255,255,.4),0 1px 2px rgba(0,0,0,.45)}
  #|.btn.primary:hover{color:#FFF6E4;filter:brightness(1.06)}
  #|.status{margin:0;padding:.5rem 1rem;color:var(--muted);font-size:.84rem;border-bottom:1px solid var(--line);background:var(--panel-2)}
  #|.status.bad{color:var(--bad)}
  #|.wrap{display:grid;grid-template-columns:264px minmax(0,1fr);gap:1.1rem;max-width:1280px;margin:0 auto;padding:1.1rem 1rem 3rem}
  #|.side{align-self:start;position:sticky;top:4.2rem;max-height:calc(100vh - 5.4rem);overflow-y:auto;
  #|  background:var(--panel);border:1px solid var(--line);border-radius:5px;padding:.7rem .6rem;box-shadow:var(--shadow)}
  #|.group{margin:.2rem 0 .7rem}
  #|.group h3{font-family:"JetBrains Mono",monospace;font-size:.6rem;text-transform:uppercase;letter-spacing:.18em;
  #|  color:var(--muted);padding:.3rem .5rem}
  #|.group .count{float:right;color:var(--accent);text-transform:none;letter-spacing:0}
  #|.nav-item{display:block;width:100%;text-align:left;font:inherit;font-size:.8rem;font-family:"JetBrains Mono",monospace;
  #|  color:var(--muted);background:none;border:0;border-left:2px solid transparent;border-radius:0 4px 4px 0;
  #|  padding:.28rem .5rem;cursor:pointer;overflow-wrap:anywhere}
  #|.nav-item:hover{background:var(--accent-soft);color:var(--ink)}
  #|.nav-item.on{background:var(--accent-soft);color:var(--ink);border-left-color:var(--accent);font-weight:500}
  #|.main{display:grid;gap:1.1rem;min-width:0}
  #|.card{background:var(--panel);border:1px solid var(--line);border-radius:5px;padding:1rem 1.1rem;
  #|  box-shadow:var(--shadow);min-width:0}
  #|.card > h2{font-size:1.5rem;margin:0 0 .1rem;overflow-wrap:anywhere}
  #|.desc{color:var(--muted);margin:.2rem 0 .8rem;font-size:.92rem}
  #|.kind{display:inline-block;font-family:"JetBrains Mono",monospace;font-size:.56rem;font-weight:500;
  #|  text-transform:uppercase;letter-spacing:.12em;border-radius:3px;padding:.12rem .42rem;vertical-align:.12em;margin-left:.4rem;
  #|  color:#7A3C1E;background:rgba(139,90,60,.14);border:1px solid rgba(139,90,60,.3)}
  #|.fields{display:grid;grid-template-columns:auto minmax(0,1fr);gap:.1rem .8rem;margin:0 0 .9rem;font-size:.88rem}
  #|.fields dt{color:var(--muted);font-family:"JetBrains Mono",monospace;font-size:.78rem}
  #|.fields dd{margin:0;overflow-wrap:anywhere}
  #|.lab{display:block;font-family:"JetBrains Mono",monospace;font-size:.6rem;text-transform:uppercase;letter-spacing:.14em;
  #|  color:var(--muted);margin:.6rem 0 .25rem}
  #|.row{display:flex;align-items:center;gap:.6rem;flex-wrap:wrap;margin-top:.8rem}
  #|.hint{font-size:.8rem;color:var(--muted)}
  #|pre.code{margin:0;background:var(--code-bg);color:var(--code-ink);border:1px solid #42342a;border-radius:5px;
  #|  padding:.6rem .7rem;font-size:.82rem;line-height:1.7;overflow-x:auto;white-space:pre;max-height:26rem;overflow-y:auto}
  #|.out{margin-top:.9rem}
  #|.out:empty{display:none}
  #|.note{border-left:3px solid var(--accent);border-radius:0 5px 5px 0;background:var(--panel-2);
  #|  padding:.5rem .7rem;margin:.5rem 0;font-size:.88rem}
  #|.note.bad{border-left-color:var(--bad);color:var(--bad)}
  #|.note.ok{border-left-color:var(--out)}
  #|.note .h{font-family:"JetBrains Mono",monospace;font-size:.72rem;color:var(--muted);display:block}
  #|.entry{border-top:1px solid var(--line);padding:.7rem 0}
  #|.entry:first-child{border-top:0;padding-top:0}
  #|.entry .head{display:flex;align-items:center;gap:.5rem;flex-wrap:wrap;font-family:"JetBrains Mono",monospace;font-size:.78rem;color:var(--muted)}
  #|.entry .head .op{color:var(--ink)}
  #|.entry .head .st{font-weight:500}
  #|.entry .head .st.ok{color:var(--out)}
  #|.entry .head .st.bad{color:var(--bad)}
  #|.entry .cols{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.7rem;margin-top:.4rem}
  #|.entry pre{margin:0}
  #|.tag{font-size:.7rem;color:var(--muted);font-family:"JetBrains Mono",monospace}
  #|@media (width<=860px){
  #|  .wrap{grid-template-columns:minmax(0,1fr);padding:.9rem .7rem 2.5rem}
  #|  .side{position:static;max-height:none}
  #|  .entry .cols{grid-template-columns:minmax(0,1fr)}
  #|}
  #|</style>
  #|</head>
  #|<body>
  #|<header class="bar">
  #|  <div class="brand">
  #|    <svg viewBox="0 0 32 32" aria-hidden="true"><rect width="32" height="32" rx="6" fill="#120C07"/><circle cx="16" cy="16" r="9" fill="none" stroke="#C98A4B" stroke-width="1.6"/><circle cx="16" cy="16" r="3.2" fill="#D97A2B"/></svg>
  #|    <span>moonmcp</span><span class="sub">debug</span>
  #|  </div>
  #|  <span class="ep" id="ep"></span>
  #|  <span class="grow"></span>
  #|  <label class="ctl">era
  #|    <select id="era">
  #|      <option value="2026-07-28">2026-07-28 stateless</option>
  #|      <option value="2025-11-25">2025-11-25 handshake</option>
  #|    </select>
  #|  </label>
  #|  <button class="btn" id="reload" type="button">reload</button>
  #|  <button class="btn" id="theme" type="button">theme</button>
  #|</header>
  #|<p class="status" id="status">loading</p>
  #|<div class="wrap">
  #|  <aside class="side" id="side"></aside>
  #|  <main class="main">
  #|    <section class="card" id="panel"></section>
  #|    <section class="card">
  #|      <h2>Exchange</h2>
  #|      <p class="desc" id="loghint">The last messages, newest first: the JSON-RPC request the page built and the reply it got back.</p>
  #|      <div id="log"></div>
  #|    </section>
  #|  </main>
  #|</div>
  #|<script id="mcp-debug" type="application/json">{"endpoint":

///|
/// The page, from the endpoint onwards.
let debug_page_tail : String =
  #|}</script>
  #|<script>
  #|const CFG = JSON.parse(document.getElementById("mcp-debug").textContent);
  #|const NAMED = { "tools/call": "name", "prompts/get": "name", "resources/read": "uri" };
  #|const LISTS = [
  #|  ["tools/list", "tools", "tools"],
  #|  ["resources/list", "resources", "resources"],
  #|  ["resources/templates/list", "templates", "resourceTemplates"],
  #|  ["prompts/list", "prompts", "prompts"]
  #|];
  #|const S = { era: "2026-07-28", seq: 1, items: { tools: [], resources: [], templates: [], prompts: [] },
  #|  kind: "server", index: 0, server: null, log: [] };
  #|
  #|const el = id => document.getElementById(id);
  #|function h(tag, cls, text) {
  #|  const n = document.createElement(tag);
  #|  if (cls) n.className = cls;
  #|  if (text !== undefined && text !== null) n.textContent = String(text);
  #|  return n;
  #|}
  #|function pre(text) { return h("pre", "code", text); }
  #|function pretty(v) {
  #|  try { return JSON.stringify(v, null, 2); } catch (e) { return String(v); }
  #|}
  #|function status(text, bad) {
  #|  const s = el("status");
  #|  s.textContent = text;
  #|  s.className = bad ? "status bad" : "status";
  #|}
  #|
  #|function mirror(schema, args) {
  #|  const out = {};
  #|  const props = (schema && schema.properties) || {};
  #|  for (const key of Object.keys(props)) {
  #|    const label = props[key] && props[key]["x-mcp-header"];
  #|    if (typeof label !== "string") continue;
  #|    const v = args ? args[key] : undefined;
  #|    if (v === undefined || v === null) continue;
  #|    out["mcp-param-" + label.toLowerCase()] = typeof v === "object" ? JSON.stringify(v) : String(v);
  #|  }
  #|  return out;
  #|}
  #|
  #|async function send(op, params, extra) {
  #|  const id = S.seq++;
  #|  const p = Object.assign({}, params || {});
  #|  const headers = { "content-type": "application/json" };
  #|  if (S.era === "2026-07-28") {
  #|    p._meta = { "io.modelcontextprotocol/protocolVersion": S.era,
  #|      "io.modelcontextprotocol/clientCapabilities": {} };
  #|    headers["mcp-protocol-version"] = S.era;
  #|    headers["mcp-method"] = op;
  #|    const field = NAMED[op];
  #|    if (field && typeof p[field] === "string") headers["mcp-name"] = p[field];
  #|  } else {
  #|    headers["mcp-protocol-version"] = S.era;
  #|  }
  #|  Object.assign(headers, extra || {});
  #|  const body = { jsonrpc: "2.0", id: id, method: op, params: p };
  #|  const started = Date.now();
  #|  let statusCode = 0;
  #|  let text = "";
  #|  try {
  #|    const res = await fetch(CFG.endpoint, { method: "POST", headers: headers, body: JSON.stringify(body) });
  #|    statusCode = res.status;
  #|    text = await res.text();
  #|  } catch (e) {
  #|    text = String(e);
  #|  }
  #|  let reply = null;
  #|  try { reply = JSON.parse(text); } catch (e) { reply = null; }
  #|  pushLog(op, headers, body, statusCode, text, Date.now() - started);
  #|  noteServer(reply);
  #|  return reply;
  #|}
  #|
  #|function pushLog(op, headers, body, statusCode, text, ms) {
  #|  const shown = {};
  #|  for (const key of Object.keys(headers)) {
  #|    if (key.indexOf("mcp-") === 0) shown[key] = headers[key];
  #|  }
  #|  const head = { method: "POST", url: CFG.endpoint, headers: shown, body: body };
  #|  S.log.unshift({ op: op, status: statusCode, ms: ms, request: pretty(head), response: text });
  #|  if (S.log.length > 6) S.log.pop();
  #|  renderLog();
  #|}
  #|
  #|function noteServer(reply) {
  #|  const info = reply && reply.result && reply.result._meta
  #|    ? reply.result._meta["io.modelcontextprotocol/serverInfo"]
  #|    : (reply && reply.result ? reply.result.serverInfo : null);
  #|  if (info && info.name) {
  #|    S.server = info;
  #|    el("ep").textContent = info.name + (info.version ? " " + info.version : "");
  #|  }
  #|}
  #|
  #|function renderLog() {
  #|  const box = el("log");
  #|  box.textContent = "";
  #|  if (!S.log.length) {
  #|    box.appendChild(h("p", "hint", "Nothing sent yet."));
  #|    return;
  #|  }
  #|  for (const item of S.log) {
  #|    const entry = h("div", "entry");
  #|    const head = h("div", "head");
  #|    head.appendChild(h("span", "op", item.op));
  #|    const st = h("span", "st " + (item.status === 200 ? "ok" : "bad"), "HTTP " + item.status);
  #|    head.appendChild(st);
  #|    head.appendChild(h("span", "tag", item.ms + " ms"));
  #|    entry.appendChild(head);
  #|    const cols = h("div", "cols");
  #|    const left = h("div");
  #|    left.appendChild(h("div", "tag", "request"));
  #|    left.appendChild(pre(item.request));
  #|    const right = h("div");
  #|    right.appendChild(h("div", "tag", "response"));
  #|    let shown = item.response;
  #|    try { shown = pretty(JSON.parse(item.response)); } catch (e) { shown = item.response; }
  #|    right.appendChild(pre(shown));
  #|    cols.appendChild(left);
  #|    cols.appendChild(right);
  #|    entry.appendChild(cols);
  #|    box.appendChild(entry);
  #|  }
  #|}
  #|
  #|function listOf(kind) { return S.items[kind] || []; }
  #|
  #|function renderSide() {
  #|  const side = el("side");
  #|  side.textContent = "";
  #|  const groups = [["server", "Server", ["server"]], ["tools", "Tools", listOf("tools").map(t => t.name)],
  #|    ["resources", "Resources", listOf("resources").map(r => r.uri)],
  #|    ["templates", "Templates", listOf("templates").map(t => t.uriTemplate)],
  #|    ["prompts", "Prompts", listOf("prompts").map(p => p.name)]];
  #|  for (const [kind, label, names] of groups) {
  #|    const group = h("div", "group");
  #|    const head = h("h3", null, label);
  #|    if (kind !== "server") {
  #|      const count = h("span", "count", String(names.length));
  #|      head.appendChild(count);
  #|    }
  #|    group.appendChild(head);
  #|    const rows = kind === "server" ? ["server"] : names;
  #|    rows.forEach((name, i) => {
  #|      const b = h("button", "nav-item" + (S.kind === kind && S.index === i ? " on" : ""), name);
  #|      b.type = "button";
  #|      b.addEventListener("click", () => { S.kind = kind; S.index = i; render(); });
  #|      group.appendChild(b);
  #|    });
  #|    if (kind !== "server" && !rows.length) group.appendChild(h("div", "nav-item hint", "none"));
  #|    side.appendChild(group);
  #|  }
  #|}
  #|
  #|function meta(pairs) {
  #|  const dl = h("dl", "fields");
  #|  for (const [key, value] of pairs) {
  #|    if (value === undefined || value === null || value === "") continue;
  #|    dl.appendChild(h("dt", null, key));
  #|    dl.appendChild(h("dd", null, value));
  #|  }
  #|  return dl;
  #|}
  #|
  #|function schemaFields(schema) {
  #|  const props = (schema && schema.properties) || {};
  #|  const required = Array.isArray(schema && schema.required) ? schema.required : Object.keys(props);
  #|  return { props: props, required: required };
  #|}
  #|
  #|function sampleValue(spec) {
  #|  if (Array.isArray(spec.enum) && spec.enum.length) return spec.enum[0];
  #|  if (spec.default !== undefined) return spec.default;
  #|  switch (spec.type) {
  #|    case "number": case "integer": return 0;
  #|    case "boolean": return false;
  #|    case "array": return [];
  #|    case "object": return {};
  #|    default: return "";
  #|  }
  #|}
  #|
  #|function renderPanel() {
  #|  const panel = el("panel");
  #|  panel.textContent = "";
  #|  if (S.kind === "server") return renderServer(panel);
  #|  const item = listOf(S.kind)[S.index];
  #|  if (!item) {
  #|    panel.appendChild(h("h2", null, "Nothing selected"));
  #|    panel.appendChild(h("p", "desc", "Pick one of the components on the left."));
  #|    return;
  #|  }
  #|  if (S.kind === "tools") return renderTool(panel, item);
  #|  if (S.kind === "resources") return renderResource(panel, item);
  #|  if (S.kind === "templates") return renderTemplate(panel, item);
  #|  return renderPrompt(panel, item);
  #|}
  #|
  #|function titled(panel, name, kind, description) {
  #|  const h2 = h("h2", null, name);
  #|  h2.appendChild(h("span", "kind", kind));
  #|  panel.appendChild(h2);
  #|  if (description) panel.appendChild(h("p", "desc", description));
  #|}
  #|
  #|function renderServer(panel) {
  #|  titled(panel, "server", "server", null);
  #|  const info = S.server;
  #|  panel.appendChild(meta([
  #|    ["name", info && info.name], ["version", info && info.version], ["title", info && info.title],
  #|    ["era", S.era], ["endpoint", CFG.endpoint]
  #|  ]));
  #|  if (S.discover) {
  #|    panel.appendChild(h("span", "lab", "server/discover"));
  #|    panel.appendChild(pre(pretty(S.discover)));
  #|  }
  #|  const row = h("div", "row");
  #|  const discover = h("button", "btn primary", "discover");
  #|  discover.type = "button";
  #|  discover.addEventListener("click", async () => {
  #|    const reply = await send("server/discover", {});
  #|    S.discover = reply && reply.result ? reply.result : reply;
  #|    renderServer(panel);
  #|  });
  #|  const init = h("button", "btn", "initialize");
  #|  init.type = "button";
  #|  init.addEventListener("click", async () => {
  #|    const reply = await send("initialize", {
  #|      protocolVersion: S.era === "2026-07-28" ? "2025-11-25" : S.era,
  #|      capabilities: {}, clientInfo: { name: "moonmcp debug", version: "1" }
  #|    });
  #|    S.discover = reply && reply.result ? reply.result : reply;
  #|    renderServer(panel);
  #|  });
  #|  row.appendChild(discover);
  #|  row.appendChild(init);
  #|  row.appendChild(h("span", "hint", "discover lists every revision; initialize is the handshake of the revisions before 2026-07-28."));
  #|  panel.appendChild(row);
  #|}
  #|
  #|function renderTool(panel, tool) {
  #|  titled(panel, tool.name, "tool", tool.description);
  #|  panel.appendChild(meta([["title", tool.title], ["output schema", tool.outputSchema ? "declared" : null]]));
  #|  const schema = tool.inputSchema || {};
  #|  const fields = schemaFields(schema);
  #|  panel.appendChild(h("span", "lab", "input schema"));
  #|  panel.appendChild(pre(pretty(schema)));
  #|  panel.appendChild(h("span", "lab", "arguments"));
  #|  const box = h("textarea");
  #|  box.rows = Math.min(12, 2 + Object.keys(fields.props).length);
  #|  box.spellcheck = false;
  #|  const sample = {};
  #|  for (const key of fields.required) {
  #|    if (fields.props[key]) sample[key] = sampleValue(fields.props[key]);
  #|  }
  #|  box.value = pretty(sample);
  #|  panel.appendChild(box);
  #|  const out = h("div", "out");
  #|  const row = h("div", "row");
  #|  const run = h("button", "btn primary", "call");
  #|  run.type = "button";
  #|  run.addEventListener("click", async () => {
  #|    let args = {};
  #|    try { args = JSON.parse(box.value || "{}"); } catch (e) {
  #|      out.textContent = "";
  #|      out.appendChild(h("div", "note bad", "arguments are not JSON: " + e));
  #|      return;
  #|    }
  #|    const reply = await send("tools/call", { name: tool.name, arguments: args },
  #|      S.era === "2026-07-28" ? mirror(schema, args) : {});
  #|    showCall(out, reply);
  #|  });
  #|  row.appendChild(run);
  #|  row.appendChild(h("span", "hint", "arguments are checked against the input schema before the tool runs"));
  #|  panel.appendChild(row);
  #|  panel.appendChild(out);
  #|}
  #|
  #|function showCall(out, reply) {
  #|  out.textContent = "";
  #|  if (!reply) return out.appendChild(h("div", "note bad", "no JSON reply"));
  #|  if (reply.error) {
  #|    const note = h("div", "note bad", reply.error.message);
  #|    note.appendChild(h("span", "h", "error " + reply.error.code));
  #|    out.appendChild(note);
  #|    if (reply.error.data) out.appendChild(pre(pretty(reply.error.data)));
  #|    return;
  #|  }
  #|  const result = reply.result || {};
  #|  if (result.isError) {
  #|    const note = h("div", "note bad", "the tool reported an error");
  #|    out.appendChild(note);
  #|  }
  #|  for (const block of result.content || []) {
  #|    if (block.type === "text") out.appendChild(pre(block.text));
  #|    else out.appendChild(pre(pretty(block)));
  #|  }
  #|  if (result.structuredContent) {
  #|    out.appendChild(h("span", "lab", "structured content"));
  #|    out.appendChild(pre(pretty(result.structuredContent)));
  #|  }
  #|  if (!out.children.length) out.appendChild(pre(pretty(result)));
  #|}
  #|
  #|function showRead(out, reply) {
  #|  out.textContent = "";
  #|  if (!reply) return out.appendChild(h("div", "note bad", "no JSON reply"));
  #|  if (reply.error) {
  #|    const note = h("div", "note bad", reply.error.message);
  #|    note.appendChild(h("span", "h", "error " + reply.error.code));
  #|    out.appendChild(note);
  #|    return;
  #|  }
  #|  const contents = (reply.result && reply.result.contents) || [];
  #|  for (const item of contents) {
  #|    const note = h("div", "note ok", item.mimeType || item.uri || "content");
  #|    out.appendChild(note);
  #|    out.appendChild(pre(item.text !== undefined ? item.text : pretty(item)));
  #|  }
  #|  if (!contents.length) out.appendChild(pre(pretty(reply.result)));
  #|}
  #|
  #|function showPrompt(out, reply) {
  #|  out.textContent = "";
  #|  if (!reply) return out.appendChild(h("div", "note bad", "no JSON reply"));
  #|  if (reply.error) {
  #|    const note = h("div", "note bad", reply.error.message);
  #|    note.appendChild(h("span", "h", "error " + reply.error.code));
  #|    out.appendChild(note);
  #|    return;
  #|  }
  #|  const messages = (reply.result && reply.result.messages) || [];
  #|  for (const m of messages) {
  #|    const text = m.content && m.content.text !== undefined ? m.content.text : pretty(m.content);
  #|    out.appendChild(h("span", "lab", m.role || "message"));
  #|    out.appendChild(pre(text));
  #|  }
  #|  if (!messages.length) out.appendChild(pre(pretty(reply.result)));
  #|}
  #|
  #|function renderResource(panel, resource) {
  #|  titled(panel, resource.uri, "resource", resource.description);
  #|  panel.appendChild(meta([["name", resource.name], ["mime type", resource.mimeType]]));
  #|  const out = h("div", "out");
  #|  const row = h("div", "row");
  #|  const run = h("button", "btn primary", "read");
  #|  run.type = "button";
  #|  run.addEventListener("click", async () => {
  #|    showRead(out, await send("resources/read", { uri: resource.uri }));
  #|  });
  #|  row.appendChild(run);
  #|  panel.appendChild(row);
  #|  panel.appendChild(out);
  #|}
  #|
  #|function renderTemplate(panel, template) {
  #|  titled(panel, template.uriTemplate, "template", template.description);
  #|  panel.appendChild(meta([["name", template.name], ["mime type", template.mimeType]]));
  #|  const pattern = template.uriTemplate || "";
  #|  const names = (pattern.match(/\{[^}]+\}/g) || []).map(s => s.slice(1, -1));
  #|  const inputs = {};
  #|  for (const name of names) {
  #|    panel.appendChild(h("span", "lab", name));
  #|    const input = h("input");
  #|    input.type = "text";
  #|    input.value = "";
  #|    panel.appendChild(input);
  #|    inputs[name] = input;
  #|  }
  #|  const out = h("div", "out");
  #|  const row = h("div", "row");
  #|  const run = h("button", "btn primary", "read");
  #|  run.type = "button";
  #|  run.addEventListener("click", async () => {
  #|    let uri = pattern;
  #|    for (const name of names) uri = uri.split("{" + name + "}").join(inputs[name].value);
  #|    out.textContent = "";
  #|    out.appendChild(h("div", "tag", uri));
  #|    showRead(out, await send("resources/read", { uri: uri }));
  #|  });
  #|  row.appendChild(run);
  #|  if (!names.length) row.appendChild(h("span", "hint", "no variables in this template"));
  #|  panel.appendChild(row);
  #|  panel.appendChild(out);
  #|}
  #|
  #|function renderPrompt(panel, prompt) {
  #|  titled(panel, prompt.name, "prompt", prompt.description);
  #|  panel.appendChild(meta([["title", prompt.title]]));
  #|  const args = prompt.arguments || [];
  #|  const inputs = {};
  #|  for (const arg of args) {
  #|    panel.appendChild(h("span", "lab", arg.name + (arg.required ? " (required)" : " (optional)")));
  #|    const input = h("input");
  #|    input.type = "text";
  #|    input.value = "";
  #|    panel.appendChild(input);
  #|    inputs[arg.name] = input;
  #|    if (arg.description) panel.appendChild(h("div", "tag", arg.description));
  #|  }
  #|  const out = h("div", "out");
  #|  const row = h("div", "row");
  #|  const run = h("button", "btn primary", "get");
  #|  run.type = "button";
  #|  run.addEventListener("click", async () => {
  #|    const given = {};
  #|    for (const arg of args) {
  #|      const value = inputs[arg.name].value;
  #|      if (value !== "" || arg.required) given[arg.name] = value;
  #|    }
  #|    showPrompt(out, await send("prompts/get", { name: prompt.name, arguments: given }));
  #|  });
  #|  row.appendChild(run);
  #|  if (!args.length) row.appendChild(h("span", "hint", "this prompt takes no arguments"));
  #|  panel.appendChild(row);
  #|  panel.appendChild(out);
  #|}
  #|
  #|function render() {
  #|  renderSide();
  #|  renderPanel();
  #|}
  #|
  #|async function reload() {
  #|  status("loading " + S.era + " ...");
  #|  renderSide();
  #|  for (const [op, kind, field] of LISTS) {
  #|    const reply = await send(op, {});
  #|    const result = reply && reply.result ? reply.result : {};
  #|    S.items[kind] = result[field] || [];
  #|  }
  #|  if (S.kind !== "server" && S.index >= listOf(S.kind).length) { S.kind = "server"; S.index = 0; }
  #|  const counts = LISTS.map(([op, kind]) => {
  #|    const n = listOf(kind).length;
  #|    return n + " " + (n === 1 ? kind.slice(0, -1) : kind);
  #|  }).join(", ");
  #|  const failed = S.log.length && S.log[0].status !== 200;
  #|  status(counts + " over " + S.era + (failed ? " (last reply was not 200)" : ""), failed);
  #|  render();
  #|}
  #|
  #|function initTheme() {
  #|  const dark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  #|  document.documentElement.setAttribute("data-theme", dark ? "dark" : "light");
  #|  const button = el("theme");
  #|  const sync = () => {
  #|    const next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
  #|    document.documentElement.setAttribute("data-theme", next);
  #|    button.textContent = "theme: " + next;
  #|  };
  #|  button.addEventListener("click", sync);
  #|  button.textContent = "theme: " + (dark ? "dark" : "light");
  #|}
  #|
  #|const root = document.documentElement;
  #|const syncTop = () => root.classList.toggle("at-top", window.scrollY <= 0);
  #|window.addEventListener("scroll", syncTop, { passive: true });
  #|
  #|el("ep").textContent = CFG.endpoint;
  #|el("era").value = S.era;
  #|el("era").addEventListener("change", e => { S.era = e.target.value; reload(); });
  #|el("reload").addEventListener("click", reload);
  #|initTheme();
  #|syncTop();
  #|renderLog();
  #|reload();
  #|</script>
  #|</body>
  #|</html>

///|
/// The debug page as HTML, for a server whose endpoint answers at `endpoint`:
/// a path on the same origin, or an absolute URL. Serve it from a route of
/// your own, or let `to_asgi` do it with `debug_page?`.
///
/// The page lists the tools, resources, resource templates and prompts the
/// server offers and calls them over the endpoint, showing the JSON-RPC
/// request it built and the reply it got back. It speaks either era of the
/// protocol, chosen on the page.
pub fn debug_page_html(endpoint~ : String = "/mcp") -> String {
  debug_page_head + Json(endpoint).stringify() + debug_page_tail
}
