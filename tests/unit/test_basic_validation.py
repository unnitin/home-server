#!/usr/bin/env python3
"""
Basic validation tests for home server setup.
These tests validate basic functionality without requiring system resources.
"""

import os
import subprocess
import unittest
from pathlib import Path


class TestBasicValidation(unittest.TestCase):
    
    def setUp(self):
        """Set up test fixtures."""
        self.repo_root = Path(__file__).parent.parent.parent
    
    def test_repo_structure(self):
        """Test that the repository has the expected structure."""
        # Check for key directories
        self.assertTrue((self.repo_root / "scripts").exists(), "scripts directory should exist")
        self.assertTrue((self.repo_root / "setup").exists(), "setup directory should exist")
        self.assertTrue((self.repo_root / "launchd").exists(), "launchd directory should exist")
        self.assertTrue((self.repo_root / "docs").exists(), "docs directory should exist")
        self.assertTrue((self.repo_root / "tests").exists(), "tests directory should exist")

    def test_setup_scripts_exist(self):
        """Test that key setup scripts exist and are executable."""
        scripts_dir = self.repo_root / "scripts"
        
        key_scripts = [
            "media/processor.sh",
            "media/watcher.sh", 
            "storage/setup_direct_mounts.sh",  # Updated from ensure_mounts.sh
            "storage/wait_for_storage.sh"
        ]
        
        for script in key_scripts:
            script_path = scripts_dir / script
            self.assertTrue(script_path.exists(), f"Script {script} does not exist")
            self.assertTrue(os.access(script_path, os.X_OK), f"Script {script} is not executable")

    def test_setup_flags_deprecated(self):
        """Test that setup_flags.sh shows deprecation warning."""
        setup_script = self.repo_root / "setup" / "setup_flags.sh"
        
        if setup_script.exists():
            # Since setup_flags.sh is deprecated and shows interactive prompt,
            # just check that it contains deprecation warning
            with open(setup_script, 'r') as f:
                content = f.read()
            self.assertIn("DEPRECATED", content, "setup_flags.sh should show deprecation warning")
            self.assertIn("setup_full.sh", content, "setup_flags.sh should recommend setup_full.sh")

    def test_documentation_exists(self):
        """Test that key documentation files exist."""
        docs_dir = self.repo_root / "docs"
        
        key_docs = [
            "AUTOMATION.md",
            "SETUP.md", 
            "QUICKSTART.md"
        ]
        
        for doc in key_docs:
            doc_path = docs_dir / doc
            self.assertTrue(doc_path.exists(), f"Documentation {doc} does not exist")

    def test_launchd_plists_exist(self):
        """Test that LaunchD plist files exist."""
        launchd_dir = self.repo_root / "launchd"
        
        expected_services = [
            "io.homelab.colima.plist",
            "io.homelab.compose.immich.plist",
            "io.homelab.plex.plist",
            "io.homelab.storage.plist",
            "io.homelab.powermgmt.plist"
        ]
        
        for service in expected_services:
            service_path = launchd_dir / service
            self.assertTrue(service_path.exists(), f"LaunchD service {service} does not exist")


if __name__ == "__main__":
    unittest.main()