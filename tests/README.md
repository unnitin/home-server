# 🧪 Comprehensive Test Suite

**Hybrid testing framework using Bash (BATS) + Python for Mac Mini HomeServer validation and regression prevention.**

---

## 📋 **Test Categories**

### **🔧 Unit Tests** (`tests/unit/`)
Test individual components and scripts in isolation.

| Test Module | Language | Purpose | Coverage |
|-------------|----------|---------|----------|
| `test_script_validation.bats` | BATS | Script syntax and basic functionality | All shell scripts |
| `test_environment_validation.bats` | BATS | Environment variable handling | Setup configurations |
| `test_media_processing.bats` | BATS | Media file processing logic | Naming conventions, file operations |
| `test_storage_utilities.bats` | BATS | Storage mount and RAID utilities | Mount point creation, symlinks |
| `test_power_management.bats` | BATS | Power settings validation | macOS power configurations |
| `test_complex_logic.py` | Python | Complex data processing and validation | Edge cases, data structures |

### **🔗 Integration Tests** (`tests/integration/`)
Test component interactions and service dependencies.

| Test Module | Language | Purpose | Coverage |
|-------------|----------|---------|----------|
| `test_service_dependencies.bats` | BATS | LaunchD service startup order | Service timing, dependencies |
| `test_storage_integration.bats` | BATS | Storage and service integration | Mount timing, data placement |
| `test_docker_integration.bats` | BATS | Docker/Colima service integration | Container startup, networking |
| `test_media_workflow.py` | Python | End-to-end media processing | Staging → Target workflow |
| `test_logging_integration.bats` | BATS | Centralized logging system | Log file creation, rotation |

### **🌐 End-to-End Tests** (`tests/e2e/`)
Full system validation simulating real-world scenarios.

| Test Module | Language | Purpose | Coverage |
|-------------|----------|---------|----------|
| `test_fresh_install.bats` | BATS | Complete setup from scratch | Full setup_flags.sh execution |
| `test_service_recovery.py` | Python | System recovery scenarios | Boot failures, service restarts |
| `test_data_integrity.py` | Python | Data preservation during operations | RAID safety, backup validation |
| `test_network_scenarios.py` | Python | Network connectivity and VPN | Tailscale, HTTPS, port access |
| `test_maintenance_workflows.bats` | BATS | Routine maintenance operations | Updates, cleanup, monitoring |

---

## 🚨 **Critical Issues Tested**

Based on historical debugging sessions, these tests prevent regression of known issues:

### **Storage & Mount Issues**
- ✅ **Immich Data Placement**: Validates photos stored on RAID, not root filesystem
- ✅ **Circular Symlinks**: Prevents `/Volumes/warmstore/Movies/Movies` loops
- ✅ **Mount Timing**: Ensures services wait for storage availability
- ✅ **Storage Dependencies**: Tests `wait_for_storage.sh` functionality

### **Service Startup Issues**
- ✅ **LaunchD Loading**: Validates all services load and start correctly
- ✅ **Docker Compose**: Tests both `docker compose` and `docker-compose` availability
- ✅ **Service Order**: Validates Colima → Storage → Immich → Plex startup sequence
- ✅ **Permission Errors**: Tests sudo requirements and script permissions

### **Configuration Drift**
- ✅ **Power Settings**: Validates 24/7 server power configuration persistence
- ✅ **Environment Variables**: Tests RAID and service configuration consistency
- ✅ **Network Configuration**: Validates Tailscale and HTTPS setup

### **Media Processing Edge Cases**
- ✅ **File Processing**: Tests various naming patterns and edge cases
- ✅ **Error Handling**: Validates failed file quarantine and cleanup
- ✅ **Directory Structure**: Tests staging and target directory integrity
- ✅ **Associated Files**: Validates subtitle and metadata handling

---

## 🛠️ **Test Execution**

### **Prerequisites**
```bash
# Install BATS testing framework
brew install bats-core bats-support bats-assert bats-file

# Install Python dependencies (for integration tests only)
pip install -r requirements-test.txt

# Ensure test environment
export TEST_MODE=1
export RAID_I_UNDERSTAND_DATA_LOSS=0  # Safety: Never destroy data in tests
```

### **Running Tests**

#### **Quick Validation** (5 minutes)
```bash
# BATS unit tests - safe and fast
bats tests/unit/*.bats

# Python unit tests for complex logic
python -m pytest tests/unit/ -v
```

#### **Comprehensive Testing** (30 minutes)
```bash
# All BATS tests
bats tests/**/*.bats

# All Python integration tests
python -m pytest tests/integration/ tests/e2e/ -v
```

#### **Specific Test Categories**
```bash
# Storage-related tests (BATS)
bats tests/unit/test_storage_*.bats tests/integration/test_storage_*.bats

# Media processing tests (BATS + Python)
bats tests/unit/test_media_*.bats
python -m pytest tests/ -k "media" -v

# Service dependency tests (BATS)
bats tests/integration/test_service_*.bats
```

#### **CI/CD Pipeline Testing**
```bash
# Non-destructive tests suitable for CI
bats tests/unit/*.bats
python -m pytest tests/unit/ -v --tb=line
```

### **Test Modes**

#### **🟢 Safe Mode** (Default)
- No system modifications
- Mock external dependencies
- Read-only operations only
- Suitable for CI/CD pipelines

#### **🟡 Integration Mode**
```bash
export TEST_INTEGRATION=1
```
- Limited system interactions
- Tests actual service status
- Validates configurations
- Requires running system

#### **🔴 Full System Mode** (Use with caution)
```bash
export TEST_FULL_SYSTEM=1
export RAID_I_UNDERSTAND_DATA_LOSS=1
```
- Complete system testing
- May modify configurations
- **⚠️ Only use on test systems**
- Validates complete workflows

---

## 📊 **Test Reports**

### **Coverage Reports**
```bash
# Generate coverage report
python -m pytest tests/ --cov=scripts --cov-report=html
open htmlcov/index.html
```

### **Performance Benchmarks**
```bash
# Benchmark test execution times
python -m pytest tests/ --benchmark-only
```

### **CI/CD Integration**
Tests integrate with GitHub Actions for:
- ✅ Pull request validation
- ✅ Pre-merge testing
- ✅ Nightly full system validation
- ✅ Release candidate testing

---

## 🔧 **Test Development**

### **Adding New Tests**
1. **Identify the component/issue** to test
2. **Choose appropriate test category** (unit/integration/e2e)
3. **Create test file** following naming convention
4. **Add fixtures** for test data in `tests/fixtures/`
5. **Update this README** with test description

### **Test Naming Convention**
- **Files**: `test_<component>_<aspect>.py`
- **Classes**: `Test<Component><Aspect>`
- **Methods**: `test_<specific_behavior>`

### **Mock Strategy**
- **External services**: Mock Docker, Tailscale, network calls
- **System commands**: Mock `sudo`, `launchctl`, `diskutil`
- **File operations**: Use temporary directories
- **Time-dependent**: Mock sleep and timing functions

---

## 🚀 **CI/CD Pipeline**

### **GitHub Actions Workflow**
```yaml
# .github/workflows/test.yml
name: Comprehensive Test Suite
on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install -r tests/requirements.txt
      - name: Run safe tests
        run: python -m pytest tests/unit/ tests/integration/ -v
      - name: Generate coverage
        run: python -m pytest tests/ --cov=scripts --cov-report=xml
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

### **Pre-commit Hooks**
```bash
# Install pre-commit hooks
pip install pre-commit
pre-commit install

# Manual run
pre-commit run --all-files
```

---

## 📚 **Related Documentation**

- **🔍 [Diagnostics](../diagnostics/README.md)** - System health checks
- **🛠️ [Scripts Reference](../scripts/README.md)** - Component documentation
- **📖 [Setup Guide](../docs/SETUP.md)** - System setup procedures
- **🔧 [Troubleshooting](../docs/TROUBLESHOOTING.md)** - Known issues and solutions

---

**💡 Remember**: Tests should be fast, reliable, and comprehensive. When in doubt, add more tests rather than fewer!
