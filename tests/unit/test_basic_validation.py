#!/usr/bin/env python3
"""
Basic validation tests for home server setup.
These tests validate basic functionality without requiring system resources.
"""

import os
import subprocess
import pytest
from pathlib import Path


def test_repo_structure():
    """Test that the repository has the expected structure."""
    repo_root = Path(__file__).parent.parent.parent
    
    # Check for key directories
    assert (repo_root / "scripts").exists()
    assert (repo_root / "setup").exists()
    assert (repo_root / "launchd").exists()
    assert (repo_root / "docs").exists()
    assert (repo_root / "tests").exists()


def test_setup_scripts_exist():
    """Test that key setup scripts exist and are executable."""
    repo_root = Path(__file__).parent.parent.parent
    scripts_dir = repo_root / "scripts"
    
    key_scripts = [
        "media_processor.sh",
        "media_watcher.sh",
        "ensure_storage_mounts.sh",
        "wait_for_storage.sh"
    ]
    
    for script in key_scripts:
        script_path = scripts_dir / script
        assert script_path.exists(), f"Script {script} does not exist"
        assert os.access(script_path, os.X_OK), f"Script {script} is not executable"


def test_setup_flags_help():
    """Test that setup_flags.sh shows help when called with --help."""
    repo_root = Path(__file__).parent.parent.parent
    setup_script = repo_root / "setup" / "setup_flags.sh"
    
    if setup_script.exists():
        result = subprocess.run(
            ["bash", str(setup_script), "--help"],
            capture_output=True,
            text=True,
            cwd=repo_root
        )
        assert result.returncode == 0
        assert "usage" in result.stdout.lower() or "Usage" in result.stdout


def test_media_processor_help():
    """Test that media_processor.sh shows help when called with --help."""
    repo_root = Path(__file__).parent.parent.parent
    script = repo_root / "scripts" / "media_processor.sh"
    
    if script.exists():
        result = subprocess.run(
            ["bash", str(script), "--help"],
            capture_output=True,
            text=True,
            cwd=repo_root
        )
        assert result.returncode == 0
        assert "Usage:" in result.stdout


def test_documentation_exists():
    """Test that key documentation files exist."""
    repo_root = Path(__file__).parent.parent.parent
    docs_dir = repo_root / "docs"
    
    key_docs = [
        "AUTOMATION.md",
        "SETUP.md",
        "QUICKSTART.md"
    ]
    
    for doc in key_docs:
        doc_path = docs_dir / doc
        assert doc_path.exists(), f"Documentation {doc} does not exist"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
