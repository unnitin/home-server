"""The scoped sudo rule (homelab/sudoers.py) and exec's sudo allowlist."""

from __future__ import annotations

import shutil
import subprocess

import pytest

from homelab import config, sudoers
from homelab import exec as hexec


def test_rules_are_the_power_profile_exactly():
    m = config.load()
    rules = sudoers.rules(m)
    assert len(rules) == len(sudoers.POWER_SETTINGS)
    for rule in rules:
        assert rule[:2] == ["/usr/bin/pmset", "-a"] and len(rule) == 4
        assert rule[3] == str(getattr(m.power, rule[2]))


def test_the_rendered_file_has_no_wildcards_and_no_diskutil():
    text = sudoers.render("someone")
    rules = "\n".join(line for line in text.splitlines() if not line.startswith("#"))
    assert "*" not in rules and "diskutil" not in rules and "ALL = (root)" in rules
    assert rules.count("/usr/bin/pmset") == len(sudoers.POWER_SETTINGS)


@pytest.mark.skipif(not shutil.which("visudo"), reason="no visudo here")
def test_visudo_accepts_the_rendered_file(tmp_path):
    f = tmp_path / "homelab"
    f.write_text(sudoers.render("someone"))
    assert (
        subprocess.run(["visudo", "-cf", str(f)], capture_output=True).returncode == 0
    )


def test_a_strange_user_name_is_refused():
    with pytest.raises(ValueError):
        sudoers.render("bob ALL=(ALL) ALL #")


@pytest.mark.parametrize(
    "argv,allowed",
    [
        (["sudo", "-n", "/usr/bin/pmset", "-a", "sleep", "0"], True),
        (["sudo", "-n", "-l"], True),  # what may run: the check reads it
        (["sudo", "-n", "-l", "/usr/bin/pmset", "-a", "womp", "1"], False),
        (["sudo", "/usr/bin/pmset", "-a", "sleep", "0"], False),  # could prompt
        (["sudo", "-n", "/usr/bin/pmset", "-a", "sleep", "10"], False),  # not ours
        (["sudo", "-n", "/usr/bin/pmset", "-a", "hibernatemode", "0"], False),
        (["sudo", "-n", "/usr/bin/pmset", "-a", "sleep", "0", "standby", "1"], False),
        (["sudo", "-n", "pmset", "-a", "sleep", "0"], False),  # never by PATH
        (["sudo", "-n", "/usr/sbin/diskutil", "list"], False),
        (["sudo", "-n", "/bin/sh", "-c", "id"], False),
        (["sudo", "-n", "-u", "root", "/usr/bin/pmset", "-a", "sleep", "0"], False),
        (["sudo", "-n", "-s"], False),
    ],
)
def test_exec_allows_sudo_only_for_the_rule(argv, allowed):
    if allowed:
        hexec.check(argv)
    else:
        with pytest.raises(hexec.ExecRefused):
            hexec.check(argv)


LISTING = """Matching Defaults entries for admin on mini:
    env_reset, env_keep+=BLOCKSIZE

User admin may run the following commands on mini:
    (ALL) ALL
    (root) NOPASSWD: /usr/bin/pmset -a sleep 0, /usr/bin/pmset -a displaysleep 1,
    /usr/bin/pmset -a disksleep 0
    (root) NOPASSWD: SETENV: /usr/bin/pmset -a womp 1, /usr/bin/pmset -a powernap 0
"""


def test_only_nopasswd_entries_count():
    """An admin may run anything with a password: that's not the rule."""
    have = sudoers.nopasswd_commands(LISTING)
    assert "/usr/bin/pmset -a sleep 0" in have and "/usr/bin/pmset -a womp 1" in have
    assert "ALL" not in have and not any("diskutil" in c for c in have)


def test_missing_names_what_the_listing_lacks():
    missing = sudoers.missing(LISTING)
    assert "/usr/bin/pmset -a standby 0" in missing
    assert "/usr/bin/pmset -a sleep 0" not in missing
    full = "    (root) NOPASSWD: " + ", ".join(" ".join(r) for r in sudoers.rules())
    assert sudoers.missing(full) == []
    assert len(sudoers.missing("")) == len(sudoers.rules())  # sudo couldn't list


def test_the_rule_spells_out_every_command():
    text = sudoers.render("someone")
    assert "Cmnd_Alias" not in text  # sudo -l would show the alias, not the commands
    for rule in sudoers.rules():
        assert " ".join(rule) in text
