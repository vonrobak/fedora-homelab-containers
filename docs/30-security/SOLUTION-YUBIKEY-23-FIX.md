# Solution: Adding MacBook Air Keys for Yubikeys #2 and #3

## What Happened

**Test Results:**
- ✅ Yubikey #1: WORKED (key already matched)
- ❌ Yubikey #2: FAILED (wrong key in authorized_keys)
- ❌ Yubikey #3: FAILED (wrong key in authorized_keys)

**Root Cause:**
The keys in fedora-htpc's `authorized_keys` were generated **on fedora-htpc**, but your MacBook Air has **different keys** generated from the same Yubikeys. FIDO2 keys are unique per registration - you can't just copy them between machines.

## Solution: Add MacBook Air's Public Keys

### Step 1: Get Public Keys from MacBook Air

**On MacBook Air, run these commands and send me the output:**

```bash
# For Yubikey #2 (5C NFC - USB-C)
echo "=== Yubikey #2 Keys ==="
cat ~/.ssh/htpc-ed25519-yk5nfc.pub
cat ~/.ssh/id_ed25519_yk5cnfc.pub

# For Yubikey #3 (5Ci - USB-C + Lightning) 
echo "=== Yubikey #3 Keys ==="
cat ~/.ssh/htpc-ed25519-ykclghtn.pub
cat ~/.ssh/id_ed25519_yk5clgtn.pub
```

### Step 2: I'll Add Them to authorized_keys

Once you send me those public keys, I'll:
1. Add them to `~/.ssh/authorized_keys` on fedora-htpc
2. Add IP restrictions (`from="192.168.1.0/24"`)
3. Document which key belongs to which Yubikey
4. Test again

### Expected Result After Fix

```
Yubikey #1 (16173971): ✅ Already working (2 keys)
Yubikey #2 (17735753): ✅ Will work (MacBook key added)
Yubikey #3 (11187313): ✅ Will work (MacBook key added)
```

---

## Alternative: Quick Copy Solution

If you prefer, we can also copy the private key **stubs** from fedora-htpc to MacBook:

**On fedora-htpc:**
```bash
# These are just pointers to Yubikey, safe to copy
cat ~/.ssh/htpcpihole-ed25519-5cNFC
cat ~/.ssh/htpcpihole-ed25519
```

**On MacBook Air:**
```bash
# Save them as (for example):
# ~/.ssh/htpc-from-fedora-yk2
# ~/.ssh/htpc-from-fedora-yk3
# chmod 600 ~/.ssh/htpc-from-fedora-yk*
```

But **Option 1 is cleaner** - just add MacBook's existing public keys to fedora-htpc.

---

## What to Send Me

Please run on **MacBook Air** and paste the output:

```bash
# Get all Yubikey public keys
echo "=== All Yubikey SSH Public Keys from MacBook Air ==="
for f in ~/.ssh/*.pub; do
    if grep -q "sk-ssh-ed25519" "$f" 2>/dev/null; then
        echo "File: $(basename $f)"
        cat "$f"
        echo ""
    fi
done
```

This will show me all your Yubikey public keys so I can add the correct ones.
