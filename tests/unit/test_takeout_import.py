"""enhanced_takeout_import.py: log location and metadata on a synthetic Takeout zip.

Skipped unless the importer's dependencies (piexif, Pillow, ffmpeg-python) are installed
"""

import importlib
import io
import json
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

piexif = pytest.importorskip("piexif")
pytest.importorskip("ffmpeg")
Image = pytest.importorskip("PIL.Image")

REPO_ROOT = Path(__file__).parent.parent.parent
SCRIPT = REPO_ROOT / "scripts" / "takeout" / "enhanced_takeout_import.py"
sys.path.insert(0, str(SCRIPT.parent))


def _jpeg():
    buf = io.BytesIO()
    Image.new("RGB", (32, 24), "orange").save(buf, "JPEG")
    return buf.getvalue()


@pytest.fixture
def takeout(tmp_path):
    src = tmp_path / "takeout"
    src.mkdir()
    meta = {
        "photoTakenTime": {"timestamp": "1703764800"},
        "geoData": {"latitude": 15.2993, "longitude": 74.124, "altitude": 10.0},
    }
    root = "Takeout/Google Photos/Trip 2024"
    with zipfile.ZipFile(src / "takeout-001.zip", "w") as z:
        z.writestr(f"{root}/IMG_0001.jpg", _jpeg())
        z.writestr(f"{root}/IMG_0001.jpg.supplemental-metadata.json", json.dumps(meta))
    return src


def test_import_does_not_create_a_log_in_the_working_directory(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    sys.modules.pop("enhanced_takeout_import", None)
    importlib.import_module("enhanced_takeout_import")
    assert list(tmp_path.iterdir()) == []


def test_default_log_file_honors_env(monkeypatch, tmp_path):
    module = importlib.import_module("enhanced_takeout_import")
    monkeypatch.setenv("TAKEOUT_LOG_FILE", str(tmp_path / "x.log"))
    assert module.default_log_file() == tmp_path / "x.log"


def test_default_log_file_falls_back_to_library_logs(monkeypatch, tmp_path):
    module = importlib.import_module("enhanced_takeout_import")
    monkeypatch.delenv("TAKEOUT_LOG_FILE", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(module.os, "access", lambda *a: False)
    path = module.default_log_file()
    assert path.parent == tmp_path / "Library" / "Logs" / "homelab" / "takeout"


def test_processes_takeout_with_metadata_and_logs_where_told(takeout, tmp_path):
    out, log, cwd = tmp_path / "out", tmp_path / "logs" / "import.log", tmp_path / "cwd"
    cwd.mkdir()
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "-i", str(takeout), "-o", str(out)]
        + ["--skip-upload", "--log-file", str(log)],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr
    assert log.exists() and "Processing complete" in log.read_text()
    assert list(cwd.iterdir()) == []

    exif = piexif.load(str(out / "processed" / "Trip 2024" / "IMG_0001.jpg"))
    taken = exif["Exif"][piexif.ExifIFD.DateTimeOriginal].decode()
    assert taken == "2023:12:28 12:00:00"
    assert exif["GPS"][piexif.GPSIFD.GPSLatitudeRef] == b"N"


def test_default_log_file_skips_a_log_root_whose_volume_isnt_mounted(
    monkeypatch, tmp_path
):
    """An empty mount-point folder isn't the volume (D22): use ~/Library/Logs."""
    module = importlib.import_module("enhanced_takeout_import")
    monkeypatch.delenv("TAKEOUT_LOG_FILE", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("HOMELAB_LOG_ROOT", "/Volumes/warmstore/logs")
    monkeypatch.setattr(module.os.path, "ismount", lambda p: False)
    monkeypatch.setattr(module.os, "access", lambda *a: True)
    path = module.default_log_file()
    assert path.parent == tmp_path / "Library" / "Logs" / "homelab" / "takeout"


def test_default_log_file_uses_the_manifests_log_root(monkeypatch, tmp_path):
    module = importlib.import_module("enhanced_takeout_import")
    monkeypatch.delenv("TAKEOUT_LOG_FILE", raising=False)
    (tmp_path / "logs").mkdir()
    monkeypatch.setenv("HOMELAB_LOG_ROOT", str(tmp_path / "logs"))
    assert module.default_log_file().parent == tmp_path / "logs" / "takeout"
