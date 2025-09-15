# 🔄 Migration Module

Migration layer providing storage tier migration capabilities, data movement, and service reconfiguration workflows.

## 📋 Scripts

### **Core Migration Engine**

#### **migrate.sh**
**Purpose**: Main orchestrator for storage tier migrations with safety checks and rollback capabilities  
**Usage**: `./scripts/migration/migrate.sh --from <source> --to <target> [--phase <phase>] [--dry-run] [--backup-dir <dir>]`  
**Features**: 
- Multi-phase migration support (quick-wins, advanced, full)
- Comprehensive backup creation before migration
- Service coordination (stop/start as needed)
- Rollback capabilities with validation

#### **validate.sh**
**Purpose**: Comprehensive validation of migration success and system health  
**Usage**: `./scripts/migration/validate.sh --migration <type> [--post-migration] [--performance]`  
**Features**: Storage health checks, service validation, performance benchmarking

### **Migration Types**

#### **storage_tier_migration.sh**
**Purpose**: Handles migration between storage tiers (warmstore → faststore, etc.)  
**Usage**: `./scripts/migration/storage_tier_migration.sh --source-tier <tier> --target-tier <tier> --data-types <types>`  
**Features**: Data type classification, selective migration, integrity verification

#### **service_data_migration.sh**
**Purpose**: Migrates service-specific data (Plex metadata, Docker volumes, etc.)  
**Usage**: `./scripts/migration/service_data_migration.sh --service <service> --target-location <path>`  
**Features**: Service-aware migration, configuration updates, symlink management

### **Utilities**

#### **backup.sh**
**Purpose**: Creates comprehensive backups before migration with metadata preservation  
**Usage**: `./scripts/migration/backup.sh --source <path> --backup-dir <dir> [--compress] [--verify]`  
**Features**: Incremental backups, integrity verification, metadata preservation

#### **rollback.sh**
**Purpose**: Safely rollback migrations using created backups  
**Usage**: `./scripts/migration/rollback.sh --backup-dir <dir> --migration-type <type>`  
**Features**: Selective rollback, service state restoration, validation

## 🔧 Migration Types Supported

### **Storage Tier Migrations**
- **warmstore → faststore**: Moving data from SSD to NVMe for performance
- **any → coldstore**: Moving data to HDD for archival
- **interim → dedicated**: Moving from symlink setup to dedicated storage

### **Service Data Migrations**
- **Plex Metadata**: Library database, thumbnails, preferences
- **Docker Volumes**: Container persistent data, databases
- **Application Cache**: Temporary processing directories
- **System Data**: Configuration files, logs

## 🎯 Migration Phases

### **Phase 1: Quick Wins (Low Risk)**
- Service processing directories
- Temporary cache locations
- Non-critical data migration

### **Phase 2: Advanced (Medium Risk)**
- Application metadata
- Database volumes
- Configuration files

### **Phase 3: Critical (High Risk)**
- Core application data
- System-level configurations
- Service binaries

## 📊 Migration Workflow

1. **Pre-flight**: Validate environment, check prerequisites
2. **Backup**: Create comprehensive backups with verification
3. **Stop Services**: Gracefully stop affected services
4. **Migrate Data**: Move data with integrity checking
5. **Update Config**: Modify configurations and symlinks
6. **Start Services**: Restart services and validate
7. **Validate**: Comprehensive health and performance checks
8. **Cleanup**: Remove temporary files, update documentation

## 🔗 Module Dependencies

**Depends on**: `core/`, `storage/`, `services/`  
**Used by**: Manual operations, `automation/` (future)

## 📁 Module Architecture

```
scripts/migration/
├── lib/
│   ├── migration_common.sh    # Shared migration utilities
│   ├── backup_helpers.sh      # Backup and restore functions
│   └── validation_helpers.sh  # Validation and health checks
├── migrate.sh                 # Main migration orchestrator
├── validate.sh                # Migration validation
├── storage_tier_migration.sh  # Storage tier migration
├── service_data_migration.sh  # Service data migration
├── backup.sh                  # Backup creation
├── rollback.sh                # Migration rollback
└── README.md                  # This documentation
```

## 🚀 Usage Examples

### **Complete Faststore Migration**
```bash
# Full migration from warmstore to faststore
./scripts/migration/migrate.sh \
  --from warmstore \
  --to faststore \
  --data-types "photos,plex-metadata,docker-volumes" \
  --backup-dir /Volumes/warmstore/migration_backup
```

### **Phased Migration**
```bash
# Phase 1: Quick wins only
./scripts/migration/migrate.sh \
  --from warmstore \
  --to faststore \
  --phase quick-wins \
  --data-types "processing-dirs"

# Phase 2: Advanced optimizations
./scripts/migration/migrate.sh \
  --from warmstore \
  --to faststore \
  --phase advanced \
  --data-types "plex-metadata,docker-volumes"
```

### **Dry Run Validation**
```bash
# Test migration without making changes
./scripts/migration/migrate.sh \
  --from warmstore \
  --to faststore \
  --dry-run \
  --data-types "photos"
```

### **Service-Specific Migration**
```bash
# Migrate only Plex metadata
./scripts/migration/service_data_migration.sh \
  --service plex \
  --target-location /Volumes/faststore/plex_metadata
```

### **Rollback Migration**
```bash
# Rollback using backup
./scripts/migration/rollback.sh \
  --backup-dir /Volumes/warmstore/migration_backup_20231215_143022 \
  --migration-type storage-tier
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
