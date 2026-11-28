"""The one way the control plane runs a program (docs/mcp-refactor/02, "exec.py").

- argv lists only, never a shell string;
- only programs on the allowlist below, each found at a fixed path (never PATH),
  and only the read-only subcommands listed for it, plus the safe actions (T1)
  with arguments taken from the manifest; the destructive storage commands
  (T3) are never added, and
  tests/homelab/test_exec.py checks that they're refused;
- a timeout per call that kills the program and everything it started;
- NO_COLOR=1, the manifest's HOMELAB_* values and a fixed PATH in its
  environment, and ANSI codes stripped from its output;
- under TEST_MODE=1 nothing runs at all: each call returns a recorded fixture
  from tests/fixtures/exec/ (or the folders in HOMELAB_EXEC_FIXTURES), and a
  call with no fixture is an error.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional, Sequence

from homelab.envfile import read_env_file

REPO = Path(__file__).resolve().parents[1]
DIAGNOSTICS = REPO / "diagnostics"
FIXTURES = REPO / "tests" / "fixtures" / "exec"
SAFE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
MAX_OUTPUT = 2_000_000  # characters kept per stream

BREW = ("/opt/homebrew/bin", "/usr/local/bin")

# Where each program may live. A program is never looked up on PATH, so a
# planted `diskutil` earlier on PATH can't be run instead.
PROGRAMS: dict[str, tuple[str, ...]] = {
    "bash": ("/bin/bash",),
    "brew": tuple(f"{d}/brew" for d in BREW),
    "colima": tuple(f"{d}/colima" for d in BREW),
    "diskutil": ("/usr/sbin/diskutil",),
    "docker": tuple(f"{d}/docker" for d in BREW),
    "launchctl": ("/bin/launchctl",),
    "lsof": ("/usr/sbin/lsof",),
    "pmset": ("/usr/bin/pmset",),
    "ps": ("/bin/ps",),
    # The interpreter running this code, for its own supervisors and jobs.
    "python": (sys.executable,),
    "security": ("/usr/bin/security",),
    "smartctl": tuple(f"{d}/smartctl" for d in BREW),
    "sw_vers": ("/usr/bin/sw_vers",),
    "sudo": ("/usr/bin/sudo",),
    "sysctl": ("/usr/sbin/sysctl",),
    "tailscale": (
        *(f"{d}/tailscale" for d in BREW),
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ),
}

# Storage scripts that erase or rebuild disks (T3). Never runnable from here.
T3_SCRIPT = re.compile(
    r"(create_[a-z]+_raid|delete_raid|format_and_mount|preclean_disks"
    r"|cleanup_disks|rebuild_storage|setup_flags)"
)


class ExecError(Exception):
    """A call that couldn't run."""


class ExecRefused(ExecError):
    """The program or its arguments aren't on the allowlist."""


class FixtureMissing(ExecError):
    """TEST_MODE call with no recorded fixture."""


@dataclass(frozen=True)
class ExecResult:
    argv: tuple[str, ...]
    rc: int
    stdout: str
    stderr: str
    duration: float = 0.0
    timed_out: bool = False

    @property
    def ok(self) -> bool:
        return self.rc == 0 and not self.timed_out


# --- the allowlist -------------------------------------------------------------


def _starts(args: Sequence[str], *prefixes: tuple[str, ...]) -> bool:
    return any(tuple(args[: len(p)]) == p for p in prefixes)


def _diskutil(args: Sequence[str]) -> bool:
    return _starts(args, ("list",), ("info",), ("apfs", "list"), ("appleRAID", "list"))


def _manifest():
    from homelab import config

    return config.load()


# Jobs never kickstarted from the control plane: the MCP server would end the
# very call that asked.
KICK_NEVER = {"io.homelab.mcp"}


def _launchctl(args: Sequence[str]) -> bool:
    if _starts(args, ("print",), ("print-disabled",), ("list",)):
        return True
    # T1: kickstart [-k] gui/<uid>/<label>, for a job in the manifest
    rest = list(args)
    if rest[:1] != ["kickstart"]:
        return False
    rest = rest[1:]
    if rest[:1] == ["-k"]:
        rest = rest[1:]
    if len(rest) != 1:
        return False
    from homelab.adapters import launchd  # this user's GUI domain only

    domain, _, label = rest[0].rpartition("/")
    if domain != launchd.domain() or label in KICK_NEVER:
        return False
    labels = {s.launchd for s in _manifest().services.values() if s.launchd}
    return label in labels


def _pmset(args: Sequence[str]) -> bool:
    return _starts(args, ("-g",))


def _ps(args: Sequence[str]) -> bool:
    """ps -o FIELDS -p PID: one process's fields, nothing else."""
    return (
        len(args) == 4
        and args[0] == "-o"
        and re.fullmatch(r"[a-z]+=?(,[a-z]+=?)*", args[1]) is not None
        and args[2] == "-p"
        and args[3].isdigit()
    )


def _sudo(args: Sequence[str]) -> bool:
    """`sudo -n CMD…` only for a command in the scoped sudo rule
    (homelab/sudoers.py): never a shell, never diskutil, never a value the
    manifest doesn't hold. And `sudo -n -l`, which lists what may run. -n:
    never ask for a password, so a missing rule fails at once instead of
    hanging."""
    from homelab import sudoers

    rest = list(args)
    if rest[:1] != ["-n"]:
        return False
    rest = rest[1:]
    if rest == ["-l"]:
        return True
    return sudoers.allowed(rest)


def _security(args: Sequence[str]) -> bool:
    return _starts(args, ("find-generic-password",))


def _sysctl(args: Sequence[str]) -> bool:
    # sysctl name=value sets a value; -w writes.
    return bool(args) and not any("=" in a or a == "-w" for a in args)


def _anything(args: Sequence[str]) -> bool:
    return True


def _nothing_but_flags(args: Sequence[str]) -> bool:
    return all(a.startswith("-") for a in args)


def _brew(args: Sequence[str]) -> bool:
    return _starts(
        args,
        ("outdated",),
        ("info",),
        ("list",),
        ("--version",),
        ("config",),
        ("services", "list"),
    )


def _colima(args: Sequence[str]) -> bool:
    return _starts(args, ("status",), ("list",), ("version",))


def _tailscale(args: Sequence[str]) -> bool:
    if _starts(
        args,
        ("status",),
        ("serve", "status"),
        ("funnel", "status"),
        ("version",),
        ("ip",),
    ):
        return True
    # T1: serve --bg --https=PORT TARGET, only a mapping the manifest declares.
    # Never funnel, reset or off.
    if len(args) == 4 and tuple(args[:2]) == ("serve", "--bg"):
        m = re.fullmatch(r"--https=(\d+)", args[2])
        mappings = {
            (mp.https, mp.target) for mp in _manifest().remote_access.tailscale_serve
        }
        return bool(m) and (int(m.group(1)), args[3]) in mappings
    return False


COMPOSE_OPTIONS = {"-f", "--file", "-p", "--project-name", "--project-directory"}
COMPOSE_READ = {"ps", "logs", "images", "ls", "version", "config"}
# T1: restart and start keep the containers that exist: they never pull,
# recreate or apply a changed compose file (that's `up`, never allowed here).
COMPOSE_ACT = {"restart", "start"}


def _compose_files() -> set[str]:
    return {
        str((REPO / s.compose_dir / "docker-compose.yml").resolve())
        for s in _manifest().services.values()
        if s.compose_dir
    }


def _docker(args: Sequence[str]) -> bool:
    if _starts(args, ("info",), ("version",), ("ps",), ("inspect",), ("logs",)):
        return True
    if not _starts(args, ("compose",)):
        return False
    rest = list(args[1:])
    files = []
    while rest and rest[0].startswith("-"):
        option = rest.pop(0)
        if "=" in option and option.split("=", 1)[0] in COMPOSE_OPTIONS:
            name, value = option.split("=", 1)
            if name in ("-f", "--file"):
                files.append(value)
            continue
        if option not in COMPOSE_OPTIONS or not rest:
            return False
        value = rest.pop(0)
        if option in ("-f", "--file"):
            files.append(value)
    if not rest:
        return False
    if rest[0] in COMPOSE_READ:
        return True
    if rest[0] in COMPOSE_ACT and len(rest) == 1 and files:
        known = _compose_files()
        return all(str(Path(f).resolve()) in known for f in files)
    return False


SMART_READ = {"-a", "-H", "-i", "-A", "-x", "-j", "--json", "--all", "--info"}


def _smartctl(args: Sequence[str]) -> bool:
    flags = [a for a in args if a.startswith("-")]
    return bool(flags) and all(f in SMART_READ for f in flags)


JOB_FIXTURES = REPO / "tests" / "fixtures" / "jobs"
MEDIA_PASSES = {"--movies-only", "--tv-only", "--collections-only", "--all"}


def _native_apps() -> set[str]:
    return {n for n, s in _manifest().services.items() if s.kind == "native_app"}


# T1: the scripts/ executors the actions run, each with the arguments it may get.
ACTION_SCRIPTS: dict[str, Callable[[list[str]], bool]] = {
    "scripts/services/restart_native_app.sh": lambda a: len(a) == 1
    and a[0] in _native_apps(),
    "scripts/services/start_plex_safe.sh": lambda a: a == [],
    "scripts/services/start_jellyfin_safe.sh": lambda a: a == [],
    "scripts/media/processor.sh": lambda a: len(a) == 1 and a[0] in MEDIA_PASSES,
    "scripts/storage/setup_direct_mounts.sh": lambda a: a in ([], ["--dry-run"]),
}


def _bash(args: Sequence[str]) -> bool:
    """A diagnostics script, or one of ACTION_SCRIPTS with its arguments, run as
    a file: no -c, no options.

    Under TEST_MODE also the test jobs in tests/fixtures/jobs/.
    """
    if not args or args[0].startswith("-"):
        return False
    script = Path(args[0])
    if not script.is_absolute():
        script = REPO / script
    try:
        script = script.resolve(strict=True)
    except OSError:
        return False
    if T3_SCRIPT.search(script.name) or script.suffix != ".sh":
        return False
    try:
        relative = str(script.relative_to(REPO.resolve()))
    except ValueError:
        relative = ""
    if relative in ACTION_SCRIPTS:
        return ACTION_SCRIPTS[relative](list(args[1:]))
    folders = [DIAGNOSTICS.resolve()]
    if test_mode():
        folders.append(JOB_FIXTURES.resolve())
    return script.parent in folders


JOB_ID = re.compile(r"^j-\d{8}-\d{6}-[0-9a-f]{4}$")


def _python(args: Sequence[str]) -> bool:
    """Only this package's own commands: a job's supervisor, the log bundle."""
    if len(args) == 4 and tuple(args[:3]) == ("-m", "homelab", "job-run"):
        return JOB_ID.match(args[3]) is not None
    if len(args) == 5 and tuple(args[:4]) == ("-m", "homelab", "bundle", "--since"):
        return re.fullmatch(r"\d{1,4}[mhd]", args[4]) is not None
    return False


RULES: dict[str, Callable[[Sequence[str]], bool]] = {
    "bash": _bash,
    "brew": _brew,
    "colima": _colima,
    "diskutil": _diskutil,
    "docker": _docker,
    "launchctl": _launchctl,
    "lsof": _anything,
    "pmset": _pmset,
    "ps": _ps,
    "python": _python,
    "security": _security,
    "sudo": _sudo,
    "smartctl": _smartctl,
    "sw_vers": _nothing_but_flags,
    "sysctl": _sysctl,
    "tailscale": _tailscale,
}


def check(argv: Sequence[str]) -> None:
    """Raise ExecRefused unless argv is allowed. argv[0] is a name from PROGRAMS."""
    if isinstance(argv, (str, bytes)) or not argv:
        raise ExecRefused("argv must be a non-empty list, never a shell string")
    name, args = argv[0], list(argv[1:])
    if name not in RULES:
        raise ExecRefused(f"{name!r} is not on the allowlist")
    if any(T3_SCRIPT.search(a) for a in args):
        raise ExecRefused(f"{name}: a destructive storage command is never run")
    if not RULES[name](args):
        raise ExecRefused(f"{name} {' '.join(args)}: not an allowed use of {name}")


def resolve(name: str) -> Optional[str]:
    """The program's absolute path, or None if it isn't installed."""
    for path in PROGRAMS[name]:
        if os.access(path, os.X_OK):
            return path
    return None


def available(name: str) -> bool:
    """Whether a program is installed (in TEST_MODE: always, fixtures decide)."""
    return test_mode() or resolve(name) is not None


# --- running -------------------------------------------------------------------


def test_mode() -> bool:
    return os.environ.get("TEST_MODE") == "1"


@dataclass
class _Recorder:
    calls: list[tuple[str, ...]] = field(default_factory=list)


RECORDED = _Recorder()


def child_env(extra: Optional[dict[str, str]] = None) -> dict[str, str]:
    env = dict(os.environ)
    for key, value in read_env_file().items():
        env.setdefault(key, value)
    env.update({"PATH": SAFE_PATH, "NO_COLOR": "1", "TERM": "dumb"})
    env.update(extra or {})
    return env


def run(
    argv: Sequence[str],
    timeout: float = 30,
    env: Optional[dict[str, str]] = None,
) -> ExecResult:
    """Run an allowed program. Never raises for a non-zero exit or a timeout."""
    check(argv)
    key = tuple(argv)
    RECORDED.calls.append(key)
    if test_mode():
        return fixture(key)
    path = resolve(argv[0])
    if path is None:
        return ExecResult(key, 127, "", f"{argv[0]}: not installed")
    started = time.monotonic()
    proc = subprocess.Popen(
        [path, *argv[1:]],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=child_env(env),
        cwd=str(REPO),
        start_new_session=True,  # its own process group, so a timeout kills it all
    )
    try:
        out, err = proc.communicate(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        _kill_group(proc)
        out, err = proc.communicate()
        timed_out = True
    return ExecResult(
        argv=key,
        rc=124 if timed_out else proc.returncode,
        stdout=_clean(out),
        stderr=_clean(err),
        duration=round(time.monotonic() - started, 3),
        timed_out=timed_out,
    )


def spawn(
    argv: Sequence[str], log_path: Path, env: Optional[dict[str, str]] = None
) -> int:
    """Start an allowed program detached, in its own session, with its output
    appended to log_path. Returns its PID at once. A job's supervisor starts
    this way, so it outlives the process that started it.

    Runs for real under TEST_MODE too: it's only allowed for this package's
    own supervisor (python -m homelab job-run ID).
    """
    check(argv)
    RECORDED.calls.append(tuple(argv))
    path = resolve(argv[0])
    if path is None:
        raise ExecError(f"{argv[0]}: not installed")
    with open(log_path, "ab") as log:
        proc = subprocess.Popen(
            [path, *argv[1:]],
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            env=child_env(env),
            cwd=str(REPO),
            start_new_session=True,
            close_fds=True,
        )
    return proc.pid


def popen(argv: Sequence[str], env: Optional[dict[str, str]] = None):
    """Start an allowed program in its own process group with stdout and stderr
    on one pipe, for a job's supervisor to read line by line. Under TEST_MODE
    only the test jobs pass check()."""
    check(argv)
    RECORDED.calls.append(tuple(argv))
    if test_mode() and not _is_test_job(argv):
        # Tests run on the mini too: a real action (quitting Plex…) never runs.
        raise ExecRefused(
            f"TEST_MODE: only tests/fixtures/jobs run as jobs, not {argv[0]} …"
        )
    path = resolve(argv[0])
    if path is None:
        raise ExecError(f"{argv[0]}: not installed")
    return subprocess.Popen(
        [path, *argv[1:]],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=child_env(env),
        cwd=str(REPO),
        start_new_session=True,
        close_fds=True,
    )


def _is_test_job(argv: Sequence[str]) -> bool:
    if len(argv) < 2 or argv[0] != "bash":
        return False
    try:
        return Path(argv[1]).resolve().parent == JOB_FIXTURES.resolve()
    except OSError:
        return False


def clean_line(raw: bytes) -> str:
    """One line of a program's output: decoded, ANSI codes gone, no newline."""
    return ANSI.sub("", raw.decode("utf-8", errors="replace")).rstrip("\r\n")


def _kill_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        proc.kill()


def _clean(raw: bytes) -> str:
    text = raw.decode("utf-8", errors="replace")[:MAX_OUTPUT]
    return ANSI.sub("", text)


# --- fixtures (TEST_MODE) --------------------------------------------------------


def fixture_key(argv: Sequence[str]) -> str:
    """A fixture's file name, without extension, for an argv.

    A path inside the repo is written relative to it, so a fixture doesn't
    depend on where the checkout lives.
    """
    parts = []
    for arg in argv:
        if arg.startswith(str(REPO) + os.sep):
            arg = os.path.relpath(arg, REPO)
        parts.append(arg)
    key = re.sub(r"[^A-Za-z0-9.-]+", "_", " ".join(parts)).strip("_")
    if len(key) > 120:
        key = key[:100] + "_" + hashlib.sha1(key.encode()).hexdigest()[:10]
    return key


def fixture_dirs() -> list[Path]:
    extra = os.environ.get("HOMELAB_EXEC_FIXTURES", "")
    return [Path(d) for d in extra.split(os.pathsep) if d] + [FIXTURES]


def fixture(argv: Sequence[str]) -> ExecResult:
    """The recorded result for argv: <key>.json ({rc, stdout, stderr}) or <key>.out.

    A .out file is the stdout of a call that exited 0.
    """
    key = fixture_key(argv)
    for folder in fixture_dirs():
        data = folder / f"{key}.json"
        if data.exists():
            rec = json.loads(data.read_text(encoding="utf-8"))
            return ExecResult(
                tuple(argv),
                int(rec.get("rc", 0)),
                rec.get("stdout", ""),
                rec.get("stderr", ""),
                timed_out=bool(rec.get("timed_out", False)),
            )
        out = folder / f"{key}.out"
        if out.exists():
            return ExecResult(tuple(argv), 0, out.read_text(encoding="utf-8"), "")
    raise FixtureMissing(
        f"TEST_MODE: no fixture for {' '.join(argv)!r} "
        f"(add {key}.json or {key}.out to one of: "
        f"{', '.join(str(d) for d in fixture_dirs())})"
    )
