#!/usr/bin/env python3
"""Every MCP tool works with any model's tool calling (03, Phase 2 acceptance).

- Names: ^[a-z][a-z0-9_]*$, at most 64 characters (OpenAI, Gemini, Anthropic,
  Ollama all accept it).
- Descriptions: present, under 1,024 characters (OpenAI's limit).
- Schemas: flat objects of primitives, enums and arrays of them; a parameter
  may be optional (anyOf [T, null]). No $ref, oneOf/allOf, or nested objects,
  so each converts to OpenAI strict mode and to Gemini's OpenAPI subset, and
  both conversions are checked.
- The tools/list surface is committed (tests/mcp/tools_list.json): a change
  shows up in review. Regenerate with UPDATE_TOOL_SNAPSHOT=1.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import sys
from pathlib import Path

import pytest

pytest.importorskip("mcp.server.fastmcp")

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "homelab_mcp"))
import mcp_server  # noqa: E402

SNAPSHOT = REPO / "tests" / "mcp" / "tools_list.json"
NAME = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
PRIMITIVE = {"string", "integer", "number", "boolean"}
ALLOWED_KEYS = {
    "type",
    "enum",
    "description",
    "title",
    "default",
    "items",
    "anyOf",
    "minimum",
    "maximum",
    "maxItems",
}

TOOLS = asyncio.run(mcp_server.build_server().list_tools())


def check_property(name: str, prop: dict) -> None:
    extra = set(prop) - ALLOWED_KEYS
    assert not extra, f"{name}: unsupported keywords {extra}"
    if "anyOf" in prop:
        options = prop["anyOf"]
        non_null = [o for o in options if o.get("type") != "null"]
        assert len(options) == 2 and len(non_null) == 1, f"{name}: anyOf is only T|null"
        check_property(name, non_null[0])
        return
    kind = prop.get("type")
    if "enum" in prop:
        assert kind in PRIMITIVE or kind is None, f"{name}: enum of {kind}"
        assert all(isinstance(v, (str, int, float, bool)) for v in prop["enum"])
        return
    if kind == "array":
        check_property(f"{name}[]", prop["items"])
        assert prop["items"].get("type") in PRIMITIVE, f"{name}: arrays of primitives"
        return
    assert kind in PRIMITIVE, f"{name}: type {kind!r} is not flat"


@pytest.mark.parametrize("tool", TOOLS, ids=lambda t: t.name)
def test_name_description_and_flat_schema(tool):
    assert NAME.match(tool.name)
    assert tool.description and len(tool.description) < 1024
    schema = tool.inputSchema
    assert schema["type"] == "object"
    assert "$defs" not in schema and "$ref" not in json.dumps(schema)
    for name, prop in schema.get("properties", {}).items():
        check_property(name, prop)


def to_openai_strict(schema: dict) -> dict:
    """What a harness sends with strict: true: all required, nullable as a type list."""
    props = {}
    for name, prop in schema.get("properties", {}).items():
        p = {k: v for k, v in prop.items() if k not in ("default", "title")}
        if "anyOf" in p:
            inner = next(o for o in p.pop("anyOf") if o.get("type") != "null")
            p.update({k: v for k, v in inner.items() if k != "title"})
            p["type"] = [p.get("type", "string"), "null"]
        props[name] = p
    return {
        "type": "object",
        "properties": props,
        "required": list(props),
        "additionalProperties": False,
    }


def to_gemini(schema: dict) -> dict:
    """Gemini's OpenAPI subset: nullable instead of anyOf, no defaults or titles."""
    props = {}
    for name, prop in schema.get("properties", {}).items():
        p = {k: v for k, v in prop.items() if k not in ("default", "title")}
        if "anyOf" in p:
            inner = next(o for o in p.pop("anyOf") if o.get("type") != "null")
            p.update({k: v for k, v in inner.items() if k != "title"})
            p["nullable"] = True
        props[name] = p
    return {
        "type": "object",
        "properties": props,
        "required": schema.get("required", []),
    }


@pytest.mark.parametrize("tool", TOOLS, ids=lambda t: t.name)
def test_converts_to_openai_strict_and_gemini(tool):
    strict = to_openai_strict(tool.inputSchema)
    assert set(strict["required"]) == set(strict["properties"])
    for prop in strict["properties"].values():
        assert "anyOf" not in prop and "default" not in prop
    gemini = to_gemini(tool.inputSchema)
    allowed = {
        "type",
        "enum",
        "description",
        "items",
        "nullable",
        "minimum",
        "maximum",
        "maxItems",
    }
    for name, prop in gemini["properties"].items():
        assert set(prop) <= allowed, f"{tool.name}.{name}: {set(prop) - allowed}"
        assert isinstance(prop["type"], str) or "enum" in prop


def surface() -> list[dict]:
    return [
        {
            "name": t.name,
            "input": t.inputSchema,
            "read_only": bool(t.annotations and t.annotations.readOnlyHint),
        }
        for t in sorted(TOOLS, key=lambda t: t.name)
    ]


def test_the_tools_list_matches_the_committed_snapshot():
    current = surface()
    if os.environ.get("UPDATE_TOOL_SNAPSHOT") == "1":
        SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
        SNAPSHOT.write_text(json.dumps(current, indent=2) + "\n")
    committed = json.loads(SNAPSHOT.read_text())
    assert current == committed, (
        "tools/list changed: review it, then UPDATE_TOOL_SNAPSHOT=1 pytest "
        "tests/unit/test_schema_portability.py"
    )


def test_no_t3_name_is_ever_exposed():
    names = {t.name for t in TOOLS}
    for banned in (
        "format",
        "erase",
        "delete_raid",
        "create_raid",
        "rebuild",
        "shell",
        "exec",
    ):
        assert not any(banned in n for n in names), banned
