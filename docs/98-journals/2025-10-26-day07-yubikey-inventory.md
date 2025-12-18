# YubiKey Inventory

**Date:** $(date +%Y-%m-%d)

## YubiKey #1: Primary (Daily Use)
- **Model:** YubiKey 5C NFC
- **Serial:** 17735753
- **Firmware:** 5.4.3
- **Form Factor:** Keychain (USB-C)
- **Interfaces:** OTP, FIDO, CCID
- **NFC:** Enabled
- **Location:** Daily keychain
- **Purpose:** Primary authentication device

## YubiKey #2: Backup (Home Safe)
- **Model:** YubiKey 5 NFC
- **Serial:** 16173971
- **Firmware:** 5.4.3
- **Form Factor:** Keychain (USB-A)
- **Interfaces:** OTP, FIDO, CCID
- **NFC:** Enabled
- **Location:** Home safe
- **Purpose:** Backup if primary is lost

## YubiKey #3: Spare (Secure Location)
- **Model:** YubiKey 5Ci
- **Serial:** 11187313
- **Firmware:** 5.2.4
- **Form Factor:** Keychain (USB-C, Lightning)
- **Interfaces:** OTP, FIDO, CCID
- **Location:** [Your secure location]
- **Purpose:** Emergency backup

## FIDO2 Configuration
- **All keys:** FIDO2 enabled ✓
- **All keys:** PIN set (8 attempts) ✓
- **Minimum PIN length:** 4 characters

## TOTP Backup
- **App:** [To be configured]
- **Backup codes:** [To be stored in password manager]

## Testing Schedule
- **Weekly:** Test primary key (normal use)
- **Monthly:** Test backup key
- **Quarterly:** Test spare key
- **Annually:** Rotate keys (primary becomes backup, etc.)

## Registration Plan
1. Register Primary (17735753) first
2. Register Backup (16173971) second  
3. Register Spare (11187313) third
4. Set up TOTP as final backup
5. Save recovery codes

## Security Notes
- Never keep all 3 keys in same location
- Test each key quarterly minimum
- Store recovery codes separately from keys
- Consider adding additional key if traveling

**Status:** Ready for registration
