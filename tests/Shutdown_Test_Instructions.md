# 🔄 Mac Mini HomeServer Shutdown Test Instructions

**Test Date:** ________________  
**Tester:** ________________  
**Expected Duration:** 15-20 minutes  

---

## 📋 **Test Overview**

This test validates that the automated recovery system works correctly after a complete system shutdown and reboot. The automation should restore all services (Plex, Immich, Landing Page) with minimal or no manual intervention.

---

## 📊 **Pre-Shutdown Checklist**

### ✅ **1. Verify Current System Status**
```bash
cd ~/Documents/home-server
./scripts/post_boot_health_check.sh
```

**Expected Result:** "🎉 ALL SYSTEMS OPERATIONAL!"

### ✅ **2. Test Service URLs**
Open in browser or test with curl:
- 📍 **Landing Page**: https://nitins-mac-mini.tailb6b278.ts.net
- 📸 **Immich**: https://nitins-mac-mini.tailb6b278.ts.net:2283
- 🎬 **Plex**: https://nitins-mac-mini.tailb6b278.ts.net:32400

**Record Results:**
- Landing Page: ⬜ Working ⬜ Failed  
- Immich: ⬜ Working ⬜ Failed  
- Plex: ⬜ Working ⬜ Failed  

### ✅ **3. Create Recovery Reference**
```bash
echo "POST-BOOT RECOVERY COMMANDS:" > ~/recovery_reference.txt
echo "1. Health check: ./scripts/post_boot_health_check.sh" >> ~/recovery_reference.txt
echo "2. Auto-recovery: ./scripts/post_boot_health_check.sh --auto-recover" >> ~/recovery_reference.txt
echo "3. Monitor logs: tail -f /tmp/{storage,colima,immich,plex,landing}.{out,err}" >> ~/recovery_reference.txt
```

---

## ⚡ **Shutdown Process**

### **Option A: Command Line Shutdown**
```bash
sudo shutdown -h now
```

### **Option B: GUI Shutdown**
Apple Menu → Shut Down

### **Wait for Complete Shutdown**
- ⬜ All lights are off
- ⬜ Wait 30 seconds after complete power down

**Shutdown Time:** ________________

---

## 🚀 **Boot and Monitoring Process**

### **1. Power On and Login**
- ⬜ Press power button
- ⬜ Login normally (this triggers automation)
- ⬜ Open Terminal

**Boot Time:** ________________  
**Login Time:** ________________

### **2. Monitor Automation (Real-Time)**
```bash
cd ~/Documents/home-server
tail -f /tmp/{storage,colima,immich,plex,landing}.{out,err}
```

### **3. Automation Timeline Checkpoints**

| Time | Service | Expected Action | ✅/❌ | Notes |
|------|---------|----------------|-------|-------|
| 0-30s | Storage | Mount points created | ⬜ | |
| 0-30s | Tailscale | VPN connection active | ⬜ | |
| 60s | Colima | Docker runtime starting | ⬜ | |
| 90s | Immich | Containers deploying | ⬜ | |
| 120s | Plex | Media Server starting | ⬜ | |
| 150s | Landing | HTTP + HTTPS configuration | ⬜ | |

---

## 🔍 **Post-Boot Validation (After 3 minutes)**

### **1. Health Check**
```bash
./scripts/post_boot_health_check.sh
```

**Expected Output Checklist:**
- ⬜ All LaunchD services "Running"
- ⬜ All service health "Running" 
- ⬜ Storage mounts "Available"
- ⬜ "🎉 ALL SYSTEMS OPERATIONAL!" message

### **2. Service URL Testing**
```bash
curl -s -o /dev/null -w "Landing: %{http_code}\n" https://nitins-mac-mini.tailb6b278.ts.net
curl -s -o /dev/null -w "Immich:  %{http_code}\n" https://nitins-mac-mini.tailb6b278.ts.net:2283  
curl -s -o /dev/null -w "Plex:    %{http_code}\n" https://nitins-mac-mini.tailb6b278.ts.net:32400
```

**Record HTTP Status Codes:**
- Landing Page: ________________ (Expected: 200/302)
- Immich: ________________ (Expected: 200/302)
- Plex: ________________ (Expected: 200/302)

### **3. Browser Verification**
Test from another device:
- ⬜ Landing page loads with service links
- ⬜ Immich login page appears
- ⬜ Plex web interface loads
- ⬜ HTTPS certificates are valid (no warnings)

---

## 🚨 **If Issues Occur**

### **1. Auto-Recovery Attempt**
```bash
./scripts/post_boot_health_check.sh --auto-recovery
```

**Record what auto-recovery fixed:**
- ⬜ Storage mounts
- ⬜ Docker services  
- ⬜ Plex startup
- ⬜ Landing page

### **2. Manual Recovery Commands**
If auto-recovery shows manual commands needed:

```bash
# Storage fixes (if needed):
sudo ln -sf /Volumes/warmstore/Photos /Volumes/Photos
sudo mkdir -p /Volumes/Archive

# HTTPS fixes (if needed):
sudo tailscale serve --bg --https=443 http://localhost:8080
sudo tailscale serve --bg --https=2283 http://localhost:2283
sudo tailscale serve --bg --https=32400 http://localhost:32400
```

**Manual commands needed:**
- ⬜ Storage commands: ________________
- ⬜ HTTPS commands: ________________
- ⬜ Other: ________________

### **3. Log Analysis (if needed)**
```bash
# Check specific service logs:
cat /tmp/storage.{out,err}
cat /tmp/colima.{out,err}
cat /tmp/immich.{out,err}
cat /tmp/plex.{out,err}
cat /tmp/landing.{out,err}
```

---

## 📊 **Test Results Summary**

### **Overall Test Result:**
- ⬜ **FULL SUCCESS**: All services started automatically, no manual intervention
- ⬜ **PARTIAL SUCCESS**: Most services started, auto-recovery fixed remaining issues  
- ⬜ **MANUAL INTERVENTION**: Some manual commands needed
- ⬜ **REQUIRES INVESTIGATION**: Multiple issues, automation needs debugging

### **Timing Summary:**
- **Total shutdown to full operation:** ________________ minutes
- **Time to first service available:** ________________ minutes
- **Time to all services operational:** ________________ minutes

### **Services Recovery:**
- **Automatic:** ________________
- **Auto-recovery fixed:** ________________  
- **Manual commands needed:** ________________

### **Final Service Status:**
```bash
# Run final health check and paste results:
./scripts/post_boot_health_check.sh
```

**Final Results:**
```
[Paste health check output here]
```

---

## 📝 **Notes and Observations**

**What worked well:**
```
[Record successful automation behaviors]
```

**Issues encountered:**
```
[Record any problems or unexpected behaviors]
```

**Suggestions for improvement:**
```
[Note any areas where automation could be enhanced]
```

---

## ✅ **Test Completion**

**Test completed at:** ________________  
**Total test duration:** ________________  
**System ready for production use:** ⬜ Yes ⬜ No ⬜ With noted issues

**Tester signature:** ________________

---

## 🔒 **Safety Notes**

- ✅ This test does not modify RAID or user data
- ✅ All automation is user-level (LaunchAgents), not system-level
- ✅ Automation can be disabled if needed: `./scripts/40_configure_launchd.sh` + manual bootout
- ✅ All actions are logged for troubleshooting

---

*Test document version: 1.0 | Generated: $(date)*

