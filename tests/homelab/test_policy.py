"""config/policy.yaml: tiers, scopes, and that it matches the server (05)."""

from __future__ import annotations

import asyncio
import copy
import sys
from pathlib import Path

import pytest

from homelab import config, policy, tools

REPO = Path(__file__).resolve().parents[2]
POL = policy.load()


def raw() -> dict:
    return copy.deepcopy(policy.read())  # the YAML, or policy.json without PyYAML


def test_policy_json_matches_the_yaml():
    pytest.importorskip("yaml")
    rendered = (config.CONFIG_DIR / policy.POLICY_JSON).read_text(encoding="utf-8")
    assert rendered == policy.render(), "run: python3 -m homelab config render"


def test_policy_reads_from_json_without_pyyaml(monkeypatch):
    monkeypatch.setattr(config, "have_yaml", lambda: False)
    assert policy.parse(policy.read()) == POL


def test_tools_py_tiers_match_the_policy():
    for name in tools.TOOLS:
        assert POL.tier(name) == "T0", name
    for name in tools.WRITES:
        assert POL.tier(name) == "T1", name


def test_observe_sees_no_t1_and_ops_sees_both():
    t0 = [n for n, r in POL.rules().items() if r.tier == "T0"]
    t1 = [n for n, r in POL.rules().items() if r.tier == "T1"]
    assert t0 and t1
    assert all(POL.visible(n, ["observe"]) for n in t0)
    assert not any(POL.visible(n, ["observe"]) for n in t1)
    assert all(POL.visible(n, ["ops"]) for n in t0 + t1)


def test_curator_sees_only_its_tools():
    seen = {n for n in POL.tools if POL.visible(n, ["curator"])}
    assert seen == set(POL.scopes["curator"].only or [])


def test_unknown_scope_and_unknown_tool_see_nothing():
    assert not POL.visible("system_overview", ["root"])
    assert not POL.visible("system_overview", [])
    assert not POL.visible("no_such_tool", ["admin"])


def test_toolset_narrows_a_scope():
    core = set(POL.toolsets["core"])
    seen = {n for n in POL.tools if POL.visible(n, ["ops"], toolset="core")}
    assert seen == core
    assert not POL.visible("memory_note", ["ops"], toolset="core")


@pytest.mark.parametrize(
    "name",
    [
        "create_ssd_raid",
        "create_nvme_raid",
        "delete_raid",
        "format_and_mount",
        "rebuild_storage",
        "preclean_disks",
        "setup_flags",
        "photos_delete",
    ],
)
def test_t3_names_are_never_exposed(name):
    assert policy.is_never(name, POL.never)
    assert not POL.visible(name, ["admin", "ops", "observe", "curator"])


def test_a_t3_name_in_the_policy_is_invalid():
    data = raw()
    data["tools"]["create_hdd_raid"] = "T1"
    with pytest.raises(policy.PolicyError, match="never exposed"):
        policy.parse(data)


def test_unknown_names_in_scopes_and_toolsets_are_invalid():
    data = raw()
    data["toolsets"]["core"].append("no_such_tool")
    with pytest.raises(policy.PolicyError, match="toolset core: unknown tool"):
        policy.parse(data)
    data = raw()
    data["scopes"]["curator"]["only"].append("no_such_tool")
    with pytest.raises(policy.PolicyError, match="scope curator"):
        policy.parse(data)


def test_unknown_keys_and_bad_rates_are_invalid():
    data = raw()
    data["tiers"]["T1"]["rate_limit"] = "lots"
    with pytest.raises(policy.PolicyError, match="rate_limit"):
        policy.parse(data)
    data = raw()
    data["tools"]["system_overview"] = {"tier": "T0", "approval": "none"}
    with pytest.raises(policy.PolicyError):
        policy.parse(data)


def test_rate_limit_and_dry_run_default():
    assert POL.rate_limit("T1") == (10, 60)
    assert POL.rate_limit("T0") is None
    assert POL.dry_run_default("T1") and not POL.dry_run_default("T0")


def test_lock_key_formats_from_the_call_arguments():
    data = raw()
    data["tools"]["memory_note"] = {"tier": "T1", "lock": "notes:{kind}"}
    pol = policy.parse(data)
    assert pol.lock_key("memory_note", {"kind": "fact", "body": "x"}) == "notes:fact"
    assert pol.lock_key("system_overview", {}) is None


def test_check_registered_names_every_mismatch():
    names = set(POL.tools)
    policy.check_registered(names)  # agrees
    with pytest.raises(policy.PolicyError, match="not in the policy: brand_new"):
        policy.check_registered(names | {"brand_new"})
    with pytest.raises(policy.PolicyError, match="not registered: system_overview"):
        policy.check_registered(names - {"system_overview"})
    with pytest.raises(policy.PolicyError, match="format_and_mount"):
        policy.check_registered(names | {"format_and_mount"})


# --- the server ----------------------------------------------------------------


def server_module():
    pytest.importorskip("mcp.server.fastmcp")
    sys.path.insert(0, str(REPO / "homelab_mcp"))
    import mcp_server as module

    return module


def test_the_server_registers_exactly_the_policys_tools():
    module = server_module()
    listed = asyncio.run(module.build_server().list_tools())
    assert {t.name for t in listed} == set(POL.tools)


def test_the_server_refuses_to_start_when_a_tool_is_missing(monkeypatch):
    module = server_module()
    data = raw()
    del data["tools"]["updates_check"]
    monkeypatch.setattr(policy, "load", lambda *a, **k: policy.parse(data))
    with pytest.raises(policy.PolicyError, match="not in the policy: updates_check"):
        module.build_server()


def test_annotations_follow_the_tier():
    module = server_module()
    for tool in asyncio.run(module.build_server().list_tools()):
        read_only = bool(tool.annotations and tool.annotations.readOnlyHint)
        if POL.tier(tool.name) == "T1":
            assert not read_only, f"{tool.name} is T1 but says read-only"
