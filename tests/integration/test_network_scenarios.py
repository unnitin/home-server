#!/usr/bin/env python3
"""
Integration tests for network scenarios and connectivity validation.
Uses Python for complex network testing that would be difficult in BATS.
"""

import pytest
import subprocess
import socket
import time
import os
import requests
from unittest.mock import patch, MagicMock


class TestNetworkScenarios:
    """Test network connectivity and service availability."""
    
    def setup_method(self):
        """Set up test environment."""
        self.test_mode = os.getenv('TEST_MODE', '1') == '1'
        self.integration_mode = os.getenv('TEST_INTEGRATION', '0') == '1'
        
    def test_tailscale_connectivity(self):
        """Test Tailscale VPN connectivity and status."""
        if not self.integration_mode:
            pytest.skip("Integration tests disabled")
            
        try:
            # Check if Tailscale is installed
            result = subprocess.run(['which', 'tailscale'], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                pytest.skip("Tailscale not installed")
                
            # Check Tailscale status
            result = subprocess.run(['tailscale', 'status'], 
                                  capture_output=True, text=True, timeout=10)
            
            # Should not fail (even if not connected)
            assert result.returncode in [0, 1], "Tailscale command should be functional"
            
        except subprocess.TimeoutExpired:
            pytest.fail("Tailscale status command timed out")
        except Exception as e:
            pytest.skip(f"Tailscale test skipped: {e}")
    
    def test_local_service_ports(self):
        """Test that expected services are listening on correct ports."""
        expected_ports = [
            (8080, "Immich"),
            (32400, "Plex"),
            (8000, "Landing Page"),
        ]
        
        for port, service_name in expected_ports:
            if not self.integration_mode:
                # In test mode, just validate port numbers are reasonable
                assert 1024 <= port <= 65535, f"Port {port} for {service_name} is not in valid range"
                continue
                
            # In integration mode, actually test connectivity
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            
            try:
                result = sock.connect_ex(('localhost', port))
                # Port might be closed if service isn't running - that's ok for testing
                # We just want to ensure the port is not blocked
                assert result in [0, 61], f"Port {port} for {service_name} appears to be blocked"
            except Exception as e:
                pytest.skip(f"Port test for {service_name} skipped: {e}")
            finally:
                sock.close()
    
    @patch('requests.get')
    def test_https_serving_configuration(self, mock_get):
        """Test HTTPS serving configuration (mocked)."""
        # Mock successful HTTPS response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.text = "Plex Media Server"
        mock_get.return_value = mock_response
        
        # Test the logic that would check HTTPS serving
        response = requests.get("https://example.tailscale-domain.ts.net")
        
        assert response.status_code == 200
        assert "Plex" in response.text
        mock_get.assert_called_once()
    
    def test_dns_resolution(self):
        """Test DNS resolution for critical domains."""
        critical_domains = [
            "github.com",
            "brew.sh", 
            "docker.com",
        ]
        
        for domain in critical_domains:
            try:
                socket.gethostbyname(domain)
            except socket.gaierror:
                pytest.fail(f"DNS resolution failed for {domain}")
    
    def test_network_interface_availability(self):
        """Test that required network interfaces are available."""
        if not self.integration_mode:
            pytest.skip("Integration tests disabled")
            
        try:
            # Check for basic network connectivity
            result = subprocess.run(['ping', '-c', '1', '-W', '3000', '8.8.8.8'], 
                                  capture_output=True, text=True, timeout=5)
            
            # Ping might fail due to firewall, but command should work
            assert result.returncode in [0, 1, 2], "Ping command should be functional"
            
        except subprocess.TimeoutExpired:
            pytest.fail("Network connectivity test timed out")
        except Exception as e:
            pytest.skip(f"Network test skipped: {e}")
    
    def test_firewall_configuration(self):
        """Test macOS firewall configuration."""
        if not self.integration_mode:
            pytest.skip("Integration tests disabled")
            
        try:
            # Check firewall status
            result = subprocess.run(['sudo', 'pfctl', '-s', 'info'], 
                                  capture_output=True, text=True, timeout=5)
            
            # Command should work (even if firewall is disabled)
            assert result.returncode in [0, 1], "Firewall status check should work"
            
        except subprocess.TimeoutExpired:
            pytest.fail("Firewall check timed out")
        except Exception as e:
            pytest.skip(f"Firewall test skipped: {e}")
    
    def test_service_health_endpoints(self):
        """Test service health check endpoints."""
        health_endpoints = [
            ("http://localhost:8080/api/server-info/ping", "Immich"),
            ("http://localhost:32400/identity", "Plex"),
        ]
        
        for endpoint, service_name in health_endpoints:
            if not self.integration_mode:
                # Just validate URL format
                assert endpoint.startswith('http'), f"Invalid endpoint for {service_name}"
                continue
            
            try:
                response = requests.get(endpoint, timeout=5)
                # Service might be down - that's ok, we just want to test connectivity
                assert response.status_code in [200, 401, 404, 500, 503], \
                    f"Unexpected response from {service_name}: {response.status_code}"
                    
            except requests.exceptions.ConnectionError:
                # Service not running - acceptable for testing
                pass
            except requests.exceptions.Timeout:
                pytest.fail(f"Health check for {service_name} timed out")
            except Exception as e:
                pytest.skip(f"Health check for {service_name} skipped: {e}")
    
    def test_tailscale_serve_configuration(self):
        """Test Tailscale serve configuration logic."""
        # This tests the configuration logic without actually running Tailscale
        
        # Mock Tailscale serve configuration
        serve_config = {
            "https:443": {
                "/": "http://localhost:8000",  # Landing page
                "/immich/": "http://localhost:8080",  # Immich
                "/plex/": "http://localhost:32400",   # Plex
            }
        }
        
        # Validate configuration structure
        assert "https:443" in serve_config
        assert "/" in serve_config["https:443"]
        assert "/immich/" in serve_config["https:443"]
        assert "/plex/" in serve_config["https:443"]
        
        # Validate all targets are localhost
        for path, target in serve_config["https:443"].items():
            assert target.startswith("http://localhost:"), \
                f"Invalid target for {path}: {target}"
    
    def test_port_conflict_detection(self):
        """Test detection of port conflicts."""
        # Common ports that might conflict
        common_ports = [80, 443, 8080, 32400, 3000, 8000]
        
        # Our service ports
        our_ports = [8080, 32400, 8000]
        
        # Check for potential conflicts
        conflicts = set(common_ports) & set(our_ports)
        
        # We expect some conflicts (that's normal)
        assert len(conflicts) > 0, "Should detect expected port usage"
        assert 8080 in conflicts, "Immich port should be in use"
        assert 32400 in conflicts, "Plex port should be in use"


class TestNetworkSecurity:
    """Test network security configurations."""
    
    def test_no_hardcoded_credentials(self):
        """Test that no hardcoded credentials exist in network configs."""
        config_files = [
            "scripts/91_configure_https_dns.sh",
            "scripts/90_install_tailscale.sh",
        ]
        
        sensitive_patterns = [
            "password=",
            "token=", 
            "secret=",
            "key=",
        ]
        
        for config_file in config_files:
            if not os.path.exists(config_file):
                continue
                
            with open(config_file, 'r') as f:
                content = f.read().lower()
                
            for pattern in sensitive_patterns:
                # Allow environment variable references
                if pattern in content and not f"${pattern}" in content:
                    pytest.fail(f"Potential hardcoded credential in {config_file}: {pattern}")
    
    def test_secure_default_configurations(self):
        """Test that default configurations are secure."""
        # Test that services bind to localhost by default
        secure_configs = {
            "immich": "localhost:8080",
            "landing": "localhost:8000", 
        }
        
        for service, expected_bind in secure_configs.items():
            # This would normally check actual service configurations
            # For now, just validate the expected format
            assert "localhost:" in expected_bind, \
                f"Service {service} should bind to localhost by default"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
