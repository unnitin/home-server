#!/usr/bin/env python3
"""
Unit tests for MCP server tool routing.

Tests that each tool name maps to the correct diagnostic script and that
check_port passes host/port arguments correctly. No server is started;
subprocess.run is patched throughout.
"""

import os
import sys
import pytest
from pathlib import Path
from unittest.mock import MagicMock

# Add repo root to path so we can import homelab_mcp/mcp_routing.py
REPO_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

DIAG = str(REPO_ROOT / "diagnostics")

sys.path.insert(0, str(REPO_ROOT / "homelab_mcp"))
from mcp_routing import (  # noqa: E402
    TOOL_SCRIPTS,
    TOOL_TIMEOUTS,
    DEFAULT_TIMEOUT,
    dispatch,
    run,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_run_result(stdout="ok", stderr="", returncode=0):
    result = MagicMock()
    result.stdout = stdout
    result.stderr = stderr
    result.returncode = returncode
    return result


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def patch_subprocess(monkeypatch):
    """Patch subprocess.run for all tests in this module."""
    mock = MagicMock(return_value=make_run_result())
    monkeypatch.setattr("subprocess.run", mock)
    return mock


# ---------------------------------------------------------------------------
# Tool routing — each tool must call the right script via dispatch()
# ---------------------------------------------------------------------------

TOOL_SCRIPT_MAP = list(TOOL_SCRIPTS.items())


@pytest.mark.parametrize("tool_name,expected_script", TOOL_SCRIPT_MAP)
def test_tool_routes_to_correct_script(patch_subprocess, tool_name, expected_script):
    """dispatch(tool_name) must invoke the correct diagnostics script via bash."""
    dispatch(tool_name)

    patch_subprocess.assert_called_once()
    cmd = patch_subprocess.call_args[0][0]
    expected_path = os.path.join(DIAG, expected_script)
    assert cmd == ["bash", expected_path], "{}: expected bash {}, got {}".format(
        tool_name, expected_path, cmd
    )


def test_collect_logs_uses_120s_timeout(patch_subprocess):
    """collect_logs must be dispatched with a 120-second timeout."""
    dispatch("collect_logs")

    kwargs = patch_subprocess.call_args[1]
    assert (
        kwargs.get("timeout") == 120
    ), "collect_logs timeout should be 120, got {}".format(kwargs.get("timeout"))
    assert TOOL_TIMEOUTS.get("collect_logs") == 120


def test_default_timeout_is_60():
    """Non-special tools should use the 60-second default timeout."""
    assert DEFAULT_TIMEOUT == 60
    assert "check_storage" not in TOOL_TIMEOUTS


# ---------------------------------------------------------------------------
# check_port argument passing
# ---------------------------------------------------------------------------


def test_check_port_default_host(patch_subprocess):
    """check_port with no host should default to localhost."""
    dispatch("check_port", {"port": 2283})

    cmd = patch_subprocess.call_args[0][0]
    assert cmd[2] == "localhost"
    assert cmd[3] == "2283"


def test_check_port_custom_host(patch_subprocess):
    """check_port should pass a custom host through unchanged."""
    dispatch("check_port", {"host": "hakuna-mateti", "port": 32400})

    cmd = patch_subprocess.call_args[0][0]
    assert cmd[2] == "hakuna-mateti"
    assert cmd[3] == "32400"


def test_check_port_port_is_string(patch_subprocess):
    """Port must be passed as a string to subprocess (not int)."""
    dispatch("check_port", {"port": 8765})

    cmd = patch_subprocess.call_args[0][0]
    assert isinstance(cmd[3], str), "Port must be a string in the subprocess command"


def test_check_port_calls_correct_script(patch_subprocess):
    """check_port must invoke network_port_check.sh."""
    dispatch("check_port", {"port": 2283})

    cmd = patch_subprocess.call_args[0][0]
    assert cmd[1].endswith("network_port_check.sh")


def test_unknown_tool_returns_error_string(patch_subprocess):
    """Unknown tool names should return an error string, not raise."""
    result = dispatch("nonexistent_tool")
    assert "Unknown tool" in result
    patch_subprocess.assert_not_called()


# ---------------------------------------------------------------------------
# Script existence — verify all referenced scripts are actually on disk
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("tool_name,expected_script", TOOL_SCRIPT_MAP)
def test_diagnostic_script_exists(tool_name, expected_script):
    """Every script in TOOL_SCRIPTS must exist on disk."""
    script_path = Path(DIAG) / expected_script
    assert script_path.exists(), "{} references {} but it does not exist at {}".format(
        tool_name, expected_script, script_path
    )


def test_network_port_check_script_exists():
    """network_port_check.sh used by check_port must exist on disk."""
    assert (Path(DIAG) / "network_port_check.sh").exists()


def test_no_unregistered_diagnostic_scripts():
    """
    Warn if scripts appear in diagnostics/ that are not registered in TOOL_SCRIPTS.
    Excludes known non-tool scripts (libraries, special-cased tools, out-of-scope).
    """
    # Scripts that are intentionally NOT exposed as MCP tools
    excluded = {
        "diag_lib.sh",  # shared library, not a tool
        "network_port_check.sh",  # exposed as check_port (special-cased with args)
        "check_power_settings.sh",  # not in MCP spec
    }
    registered_scripts = set(TOOL_SCRIPTS.values())
    on_disk = {p.name for p in Path(DIAG).glob("*.sh")}
    unregistered = on_disk - registered_scripts - excluded
    assert not unregistered, (
        "New scripts in diagnostics/ are not registered in TOOL_SCRIPTS "
        "or excluded: {}. Add them to routing.py or the excluded set.".format(
            unregistered
        )
    )


# ---------------------------------------------------------------------------
# File structure
# ---------------------------------------------------------------------------


def test_server_file_exists():
    assert (REPO_ROOT / "homelab_mcp" / "mcp_server.py").exists()


def test_routing_file_exists():
    assert (REPO_ROOT / "homelab_mcp" / "mcp_routing.py").exists()


def test_requirements_file_exists():
    assert (REPO_ROOT / "homelab_mcp" / "requirements.txt").exists()


def test_plist_file_exists():
    assert (REPO_ROOT / "launchd" / "io.homelab.mcp.plist").exists()


def test_requirements_includes_mcp():
    content = (REPO_ROOT / "homelab_mcp" / "requirements.txt").read_text()
    assert "mcp" in content


def test_requirements_includes_uvicorn():
    content = (REPO_ROOT / "homelab_mcp" / "requirements.txt").read_text()
    assert "uvicorn" in content


def test_requirements_includes_starlette():
    content = (REPO_ROOT / "homelab_mcp" / "requirements.txt").read_text()
    assert "starlette" in content


def test_requirements_pin_sdk_below_2():
    """mcp 2.x renamed FastMCP; an unpinned install breaks the server on import."""
    content = (REPO_ROOT / "homelab_mcp" / "requirements.txt").read_text()
    assert "<2" in content


def test_old_mcp_directory_is_gone():
    """A top-level mcp/ directory shadows the MCP SDK package."""
    assert not (REPO_ROOT / "mcp").exists()


# ---------------------------------------------------------------------------
# Executor: explicit result line, no color codes, timeouts handled, PATH fixed
# ---------------------------------------------------------------------------


def test_run_reports_ok_and_exit_code(patch_subprocess):
    out = run(["bash", "x.sh"])
    assert out.splitlines()[0] == "Result: OK (exit 0)"
    assert "ok" in out


def test_run_reports_failure_exit_code(patch_subprocess):
    patch_subprocess.return_value = make_run_result("FAIL - bad", "", 1)
    out = run(["bash", "x.sh"])
    assert out.splitlines()[0] == "Result: FAIL (exit 1)"
    assert "FAIL - bad" in out


def test_run_strips_terminal_color_codes(patch_subprocess):
    patch_subprocess.return_value = make_run_result(
        "\x1b[0;32mOK\x1b[0m  - fine", "", 0
    )
    out = run(["bash", "x.sh"])
    assert "\x1b" not in out
    assert "OK  - fine" in out


def test_run_handles_timeout(patch_subprocess):
    import subprocess

    patch_subprocess.side_effect = subprocess.TimeoutExpired(
        cmd="bash", timeout=60, output=b"partial line"
    )
    out = run(["bash", "x.sh"], timeout=60)
    assert out.startswith("Result: TIMEOUT after 60s")
    assert "partial line" in out


def test_run_sets_no_color_and_homebrew_path(patch_subprocess, monkeypatch):
    monkeypatch.setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
    run(["bash", "x.sh"])
    env = patch_subprocess.call_args[1]["env"]
    assert env["NO_COLOR"] == "1"
    assert "/opt/homebrew/bin" in env["PATH"].split(":")


def test_remote_access_alias_points_at_new_script():
    assert TOOL_SCRIPTS["check_remote_access"] == "check_remote_access.sh"
    assert TOOL_SCRIPTS["check_reverse_proxy"] == "check_remote_access.sh"


def test_plist_binds_loopback_and_runs_new_path():
    content = (REPO_ROOT / "launchd" / "io.homelab.mcp.plist").read_text()
    assert "__REPO__/homelab_mcp/mcp_server.py" in content
    assert "<string>127.0.0.1</string>" in content
    assert "/opt/homebrew/bin" in content
    assert "0.0.0.0" not in content
