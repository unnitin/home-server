"""Every unit test gets its own state database: none may touch the real one."""

import pytest


@pytest.fixture(autouse=True)
def _private_state_db(tmp_path, monkeypatch):
    monkeypatch.setenv("HOMELAB_STATE_DB", str(tmp_path / "state.db"))
