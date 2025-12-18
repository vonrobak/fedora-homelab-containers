# Re-Test Yubikeys with Corrected Keys

## What Was Fixed

Added the correct MacBook Air keys to fedora-htpc authorized_keys:
- **5 keys total** (down from 8 originally)
- All keys have `from="192.168.1.0/24"` IP restrictions
- Matched to your MacBook Air's actual SSH keys

## Important Discovery

**What we learned:**
- "Yubikey #1" we thought was working is actually **Yubikey #2** (Serial 17735753)!
- The real Yubikey #1 (Serial 16173971) might not have keys on MacBook Air
- You've been using Yubikey #2 (5C NFC, USB-C) as your primary key

## Quick Re-Test

### Test from MacBook Air:

**Test 1: Yubikey #2 (5C NFC - Serial 17735753) - PRIMARY**
```bash
# Insert Yubikey #2 (USB-C, the one you've been using)
ssh patriark@fedora-htpc.lokal

# Expected: ✅ Should work (this was already working)
```

**Test 2: Yubikey #3 (5Ci - Serial 11187313) - BACKUP**
```bash
# Remove Yubikey #2, insert Yubikey #3 (USB-C or Lightning)
ssh patriark@fedora-htpc.lokal

# Expected: ✅ SHOULD NOW WORK (we added both MacBook keys)
```

**Test 3: Yubikey #1 (5 NFC - Serial 16173971) - UNKNOWN**
```bash
# Remove Yubikey #3, insert Yubikey #1 (USB-A)
ssh patriark@fedora-htpc.lokal

# Expected: ❓ MIGHT work (we kept one old key from patriark-MB.local)
# If it doesn't work, that's OK - we can add keys if needed
```

## Expected Results

```
Yubikey #1 (16173971 - USB-A):     ❓ Unknown (test to find out)
Yubikey #2 (17735753 - USB-C):     ✅ Should work (already working)
Yubikey #3 (11187313 - USB-C+Ltg): ✅ Should work (keys added)
```

## If Tests Pass

You'll have:
- **Primary**: Yubikey #2 (your daily driver)
- **Backup**: Yubikey #3 (USB-C + Lightning dual)
- **Extra**: Yubikey #1 (USB-A, for fedora-jern or legacy systems)

## Report Back

Please test and let me know:
1. Which Yubikeys worked?
2. Any error messages?

Then I'll:
- Update the documentation
- Clean up temporary files
- Create final Yubikey inventory
- Mark Option 1 as complete!
