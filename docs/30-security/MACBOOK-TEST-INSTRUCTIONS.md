# MacBook Air - Yubikey SSH Testing Instructions

**Date**: 2025-11-04
**Target**: fedora-htpc.lokal (192.168.1.70)
**Auto-rollback**: Active for 5 minutes (until ~18:24)

---

## ⚠️ IMPORTANT - Timeline

**Auto-rollback timer active!**
- **Rollback PID**: 51229
- **Triggers in**: ~5 minutes from activation
- **What happens**: Automatically restores old authorized_keys if not canceled

**After successful test from Yubikey #1:**
```bash
# Run on fedora-htpc to cancel rollback:
kill 51229
```

---

## 🧪 Test Procedure - MacBook Air

### Prerequisites
- MacBook Air at 192.168.1.34 (current DHCP IP)
- All 3 Yubikeys available
- Terminal app open on MacBook

---

### Test 1: Yubikey #1 (Serial 16173971) - PRIMARY

**Expected**: ✅ **SHOULD WORK** (this key was working before)

**Yubikey details:**
- Model: YubiKey 5 NFC (USB-A)
- Serial: 16173971
- Status: This is your currently working key

**Commands to run on MacBook Air:**

```bash
# Test 1A: Basic connection test
ssh patriark@fedora-htpc.lokal

# Expected:
# - Prompt for Yubikey touch
# - Connection succeeds
# - You get shell on fedora-htpc

# If successful:
echo "✅ Yubikey #1 TEST PASSED"
exit

# Test 1B: Using short hostname (from SSH config)
ssh htpc

# Expected: Same as above (should work)

# Test 1C: Direct IP address
ssh patriark@192.168.1.70

# Expected: Same as above (should work)
```

**Gathering info after Test 1:**

After successful connection, run on fedora-htpc:
```bash
# Check which key was used
journalctl -u sshd -n 5 --no-pager | grep "Accepted publickey"

# This will show the fingerprint - note which one it is
```

---

### Test 2: Yubikey #2 (Serial 17735753) - BACKUP #1

**Expected**: ⚠️ **UNKNOWN** (newly added key, never tested before)

**Yubikey details:**
- Model: YubiKey 5C NFC (USB-C)
- Serial: 17735753
- Status: Newly added from htpcpihole-ed25519-5cNFC.pub

**Commands to run on MacBook Air:**

```bash
# Step 1: REMOVE Yubikey #1 from MacBook
# Step 2: INSERT Yubikey #2 (USB-C)

# Verify correct Yubikey inserted (if ykman installed on Mac):
ykman list --serials
# Should show: 17735753

# Test 2A: Connection test
ssh patriark@fedora-htpc.lokal

# Possible outcomes:
# ✅ SUCCESS: Yubikey touch prompt → connection works
# ❌ FAIL: "Permission denied (publickey)" or no touch prompt
```

**If Test 2 SUCCEEDS:**
```bash
echo "✅ Yubikey #2 TEST PASSED"

# On fedora-htpc, check logs:
journalctl -u sshd -n 3 --no-pager | grep "Accepted publickey"
# Should show fingerprint: SHA256:zYySvXeA5BVaWbpds2XoQqTrtJhizfuKreXToCmQeCc
```

**If Test 2 FAILS:**
```bash
echo "❌ Yubikey #2 TEST FAILED"

# This is OK! We'll debug on fedora-htpc
# Keep Yubikey #2 inserted and note the failure
```

---

### Test 3: Yubikey #3 (Serial 11187313) - BACKUP #2

**Expected**: ⚠️ **UNKNOWN** (newly added key, never tested before)

**Yubikey details:**
- Model: YubiKey 5Ci (USB-C + Lightning dual)
- Serial: 11187313
- Status: Newly added from htpcpihole-ed25519.pub

**Commands to run on MacBook Air:**

```bash
# Step 1: REMOVE Yubikey #2 from MacBook
# Step 2: INSERT Yubikey #3 (USB-C or Lightning)

# Verify correct Yubikey inserted:
ykman list --serials
# Should show: 11187313

# Test 3A: Connection test
ssh patriark@fedora-htpc.lokal

# Possible outcomes:
# ✅ SUCCESS: Yubikey touch prompt → connection works
# ❌ FAIL: "Permission denied (publickey)" or no touch prompt
```

**If Test 3 SUCCEEDS:**
```bash
echo "✅ Yubikey #3 TEST PASSED"

# On fedora-htpc, check logs:
journalctl -u sshd -n 3 --no-pager | grep "Accepted publickey"
# Should show fingerprint: SHA256:PZd9qeW/f2+rR9PkRfVjA2lq0aMQLBmA7+RoJnFjWxI
```

**If Test 3 FAILS:**
```bash
echo "❌ Yubikey #3 TEST FAILED"

# This is OK! We'll debug on fedora-htpc
```

---

## 📊 Test Results Summary

Fill this out as you test:

```
┌─────────────────────────────────────────────────┐
│ Yubikey Test Results                            │
├─────────────────────────────────────────────────┤
│                                                 │
│ Yubikey #1 (16173971):  [ ] PASS  [ ] FAIL     │
│ Yubikey #2 (17735753):  [ ] PASS  [ ] FAIL     │
│ Yubikey #3 (11187313):  [ ] PASS  [ ] FAIL     │
│                                                 │
│ Notes:                                          │
│ _____________________________________________   │
│ _____________________________________________   │
│ _____________________________________________   │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 🔍 Troubleshooting

### Issue: "Permission denied (publickey)"

**Possible causes:**
1. Wrong Yubikey inserted
2. Key not in authorized_keys (Yubikey #2 or #3)
3. IP restriction blocking connection
4. SSH config issue

**Debug on MacBook:**
```bash
# Verbose SSH to see what's happening
ssh -vvv patriark@fedora-htpc.lokal

# Look for lines like:
# "Offering public key: ..."
# "Server accepts key: ..."
# "Permission denied"
```

### Issue: "Host key verification failed"

**Solution:**
```bash
# On MacBook Air:
ssh-keygen -R fedora-htpc.lokal
ssh-keygen -R 192.168.1.70

# Then retry connection
```

### Issue: No Yubikey touch prompt

**Possible causes:**
1. Yubikey not inserted properly
2. Key not configured for touch requirement
3. SSH trying non-Yubikey keys first

**Debug:**
```bash
# Check SSH config is being used:
ssh -G fedora-htpc.lokal | grep -i identity

# Should show: id_ed25519_sk and id_ecdsa_sk
```

---

## ⏱️ After All Tests - Cancel Auto-Rollback

**If at least Yubikey #1 worked**, cancel the auto-rollback:

**On fedora-htpc console:**
```bash
# Cancel rollback timer
kill 51229

# Verify it's stopped
ps aux | grep "sleep 300" | grep -v grep
# Should show nothing

echo "✅ Auto-rollback canceled - changes are permanent"
```

**If you want to keep the changes** (even if Yubikeys #2/#3 failed):
```bash
# The old authorized_keys is saved at:
ls -la ~/.ssh/authorized_keys.old

# Remove the .old file once you're confident:
# rm ~/.ssh/authorized_keys.old
```

---

## 📝 Information to Report Back

After testing, provide this information:

1. **Which Yubikeys worked?**
   - [ ] Yubikey #1 (16173971)
   - [ ] Yubikey #2 (17735753)
   - [ ] Yubikey #3 (11187313)

2. **Any errors encountered?**
   - Type of error: _________________
   - Which Yubikey: _________________

3. **SSH logs from successful connections:**
   ```bash
   # Run on fedora-htpc:
   journalctl -u sshd --since "5 minutes ago" | grep "Accepted publickey"
   ```

4. **Did you cancel auto-rollback?**
   - [ ] Yes, canceled (kill 51229)
   - [ ] No, let it rollback
   - [ ] Unsure

---

## 🎯 Success Criteria

**Minimum success**: Yubikey #1 works
- This was working before, should still work
- If this fails, auto-rollback will restore old config

**Good success**: Yubikey #1 + one other works
- You have primary + backup working

**Perfect success**: All 3 Yubikeys work
- Full redundancy achieved
- Can lose any one key and still access

---

## 🔙 Manual Rollback (Emergency)

If you need to rollback immediately:

**On fedora-htpc console:**
```bash
cp ~/.ssh/authorized_keys.old ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Kill the auto-rollback timer to prevent double-rollback
kill 51229

echo "✅ Manually rolled back to old configuration"
```

---

**Ready to test? Start with Yubikey #1!**
