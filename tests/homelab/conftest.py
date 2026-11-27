"""Every homelab test gets its own state database: never the mini's real one."""

import pytest


@pytest.fixture(autouse=True)
def state_db(tmp_path, monkeypatch):
    path = tmp_path / "state" / "state.db"
    monkeypatch.setenv("HOMELAB_STATE_DB", str(path))
    return path
