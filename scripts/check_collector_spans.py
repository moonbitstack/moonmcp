#!/usr/bin/env python3
"""Check the spans a real OpenTelemetry collector received, field by field.

The tracing job starts an otelcol-contrib with an OTLP receiver and a file
exporter; this script reads the OTLP/JSON it wrote. One MCP call made over a
transport with no headers sends its W3C trace context in `params._meta`, so the
server span must be the child of the caller span in the same trace, and must
carry the attributes the OpenTelemetry conventions for MCP name.

    python3 scripts/check_collector_spans.py <traces.json>
"""
import json
import pathlib
import sys

SERVICE = "moonmcp-collector-check"
SCOPE = "moonbitstack/moonmcp"
CALLER = "caller calls tools/call add"
SERVER = "tools/call add"


def value(span, key):
    """One attribute's value, whichever OTLP value kind it was written in."""
    for item in span.get("attributes", []):
        if item.get("key") == key:
            return item.get("value", {})
    return None


def plain(item):
    if not item:
        return None
    for kind in ("stringValue", "intValue", "doubleValue", "boolValue"):
        if kind in item:
            return str(item[kind])
    return None


def records(path):
    """Every span the collector wrote, with the resource and scope it came under."""
    found = []
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        document = json.loads(line)
        for resource in document.get("resourceSpans", []):
            own = {"attributes": resource.get("resource", {}).get("attributes", [])}
            service = plain(value(own, "service.name"))
            for group in resource.get("scopeSpans", []):
                scope = group.get("scope", {}).get("name")
                for span in group.get("spans", []):
                    found.append((service, scope, span))
    return found


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check_collector_spans.py <traces.json>")
    path = pathlib.Path(sys.argv[1])
    if not path.is_file() or path.stat().st_size == 0:
        sys.exit("the collector wrote no spans to {}".format(path))
    found = records(path)
    by_name = {record[2].get("name"): record for record in found}
    server = by_name.get(SERVER)
    caller = by_name.get(CALLER)

    checks = []

    def check(label, ok):
        checks.append((label, bool(ok)))

    check("the collector decoded exactly two spans", len(found) == 2)
    check("the caller span arrived", caller is not None)
    check("the MCP server span arrived", server is not None)
    if server is None or caller is None:
        report(checks)
        sys.exit(1)

    service, scope, span = server
    caller_service, caller_scope, parent_span = caller
    check("the server span is named tools/call add", span.get("name") == SERVER)
    check("the server span is a server span", span.get("kind") == 2)
    check("the caller span is a client span", parent_span.get("kind") == 3)
    check("the service name is on the server span", service == SERVICE)
    check("the service name is on the caller span", caller_service == SERVICE)
    check("the instrumentation scope is moonbitstack/moonmcp", scope == SCOPE)
    check(
        "the same scope is on the caller span",
        caller_scope == SCOPE,
    )
    check(
        "both spans share one trace id",
        span.get("traceId") == parent_span.get("traceId") and bool(span.get("traceId")),
    )
    check(
        "the server span is the child of the caller span",
        span.get("parentSpanId") == parent_span.get("spanId"),
    )
    check(
        "the child has its own span id",
        span.get("spanId") != parent_span.get("spanId"),
    )
    check("the caller span has no parent", not parent_span.get("parentSpanId"))
    check(
        "mcp.method.name is tools/call",
        plain(value(span, "mcp.method.name")) == "tools/call",
    )
    check(
        "gen_ai.tool.name is add",
        plain(value(span, "gen_ai.tool.name")) == "add",
    )
    check(
        "gen_ai.operation.name is execute_tool",
        plain(value(span, "gen_ai.operation.name")) == "execute_tool",
    )
    check(
        "mcp.protocol.version is 2026-07-28",
        plain(value(span, "mcp.protocol.version")) == "2026-07-28",
    )
    check(
        "jsonrpc.request.id is the request's id",
        plain(value(span, "jsonrpc.request.id")) == "42",
    )
    check("the span was answered successfully", span.get("status", {}).get("code") == 1)
    check(
        "the span has a timeline",
        int(span.get("startTimeUnixNano", 0)) > 0
        and int(span.get("endTimeUnixNano", 0))
        >= int(span.get("startTimeUnixNano", 0)),
    )
    report(checks)


def report(checks):
    for label, ok in checks:
        print("{}  {}".format("ok  " if ok else "FAIL", label))
    failed = [label for label, ok in checks if not ok]
    if failed:
        print("{} of {} checks failed: {}".format(len(failed), len(checks), ", ".join(failed)))
        sys.exit(1)
    print("{} checks passed against the collector's own trace record".format(len(checks)))


main()
