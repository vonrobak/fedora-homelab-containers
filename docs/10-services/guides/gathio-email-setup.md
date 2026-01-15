# Gathio Email Configuration Guide

**Created:** 2026-01-14
**Service:** Gathio Event Management
**Purpose:** Configure SMTP email for event editing magic links

---

## Quick Decision: Do You Need Email?

**No - Email is optional!**

When creating an event, Gathio gives you an **editing link** with the password embedded:
```
https://events.patriark.org/edit/abc123?e=generated-password
```

**Save this link** (bookmark, password manager, notes) and you can edit the event anytime.

**Use email if:** You want automatic delivery of editing links to avoid manually saving them.

---

## Option 1: No Email (Simplest)

**Setup:** Already done - `mail_service = "none"` in config.toml

**Workflow:**
1. Create event at https://events.patriark.org/new
2. **Copy the editing link** shown after creation
3. Save it somewhere safe (Vaultwarden, notes app, bookmark)
4. Share the **public event link** with guests
5. Use your saved editing link to modify event later

**Pros:**
- Zero configuration
- No email provider needed
- More private

**Cons:**
- Must manually save links
- Lose link = lose edit access (event stays live but uneditable)

---

## Option 2: SendGrid (Recommended SMTP Solution)

**Free tier:** 100 emails/day forever
**Why recommended:** API-based, reliable, good free tier

### Setup Steps

1. **Sign up:** https://sendgrid.com/free/
2. **Create API Key:**
   - Settings → API Keys → Create API Key
   - Name: "Gathio Events"
   - Permissions: "Mail Send" (Full Access)
   - Copy the key (shown once!)

3. **Verify Sender Email:**
   - Settings → Sender Authentication → Single Sender Verification
   - Add: surfaceideology@proton.me
   - Check Proton inbox for verification link

4. **Update Gathio Config:**

```bash
nano ~/containers/config/gathio/config.toml
```

Update these sections:
```toml
[general]
email = "surfaceideology@proton.me"
mail_service = "sendgrid"

[sendgrid]
api_key = "SG.xxxxxxxxxxxx"  # Your API key from step 2
```

5. **Restart Gathio:**
```bash
systemctl --user restart gathio.service
```

6. **Test:** Create a test event and verify email arrives

---

## Option 3: Brevo (formerly Sendinblue)

**Free tier:** 300 emails/day
**Why use:** Higher free tier than SendGrid

### Setup Steps

1. **Sign up:** https://www.brevo.com/
2. **Get SMTP credentials:**
   - Settings → SMTP & API → SMTP
   - Username: Your Brevo login email
   - Password: Generate SMTP key

3. **Update config.toml:**
```toml
[general]
email = "surfaceideology@proton.me"
mail_service = "nodemailer"

[nodemailer]
smtp_server = "smtp-relay.brevo.com"
smtp_port = "587"
smtp_username = "YOUR_BREVO_EMAIL"
smtp_password = "YOUR_BREVO_SMTP_KEY"
```

4. **Restart:** `systemctl --user restart gathio.service`

---

## Option 4: New Gmail Account (Last Resort)

Your current Gmail/Outlook won't work (passwordless auth = no app passwords).

**Workaround:** Create a **new** Gmail account specifically for Gathio:

1. **Create new Gmail:** gathio.events.patriark@gmail.com (example)
2. **Enable 2FA:** Required for app passwords
3. **Generate App Password:**
   - Google Account → Security → 2-Step Verification → App passwords
   - App: "Gathio" → Generate
4. **Update config.toml:**
```toml
[general]
email = "gathio.events.patriark@gmail.com"
mail_service = "nodemailer"

[nodemailer]
smtp_server = "smtp.gmail.com"
smtp_port = "587"
smtp_username = "gathio.events.patriark@gmail.com"
smtp_password = "xxxx xxxx xxxx xxxx"  # 16-character app password
```

---

## Why Your Existing Accounts Don't Work

❌ **Proton Mail (free):**
- No SMTP access on free tier
- Requires Proton Mail Plus + Proton Bridge ($4.99/month)

❌ **Gmail/Outlook (passwordless):**
- Passwordless auth = no traditional password
- Can't generate app passwords without password login
- Microsoft/Google security policy

---

## Testing Email Configuration

1. **Check Gathio logs:**
```bash
journalctl --user -u gathio.service -f
```

2. **Create test event:**
   - Visit https://events.patriark.org/new
   - Fill in event details
   - Enter your email address
   - Submit

3. **Verify:**
   - Check email inbox for editing link
   - Logs should show: "Email sent successfully" (not error)

4. **If it fails:**
```bash
# Check logs for error messages
podman logs gathio 2>&1 | grep -i "error\|email\|smtp"

# Common issues:
# - API key invalid → regenerate in provider
# - Email not verified → check sender verification
# - SMTP port blocked → try port 465 (SSL)
```

---

## Security Considerations

### SendGrid API Key

**Storage:** Should be in podman secret, but Gathio doesn't support env vars in TOML.

**Current approach (acceptable):**
- API key in `config.toml`
- File is in `.gitignore` ✅
- File permissions: `644` ✅
- SELinux label: `:Z` ✅

**To rotate:**
```bash
# 1. Generate new API key in SendGrid
# 2. Update config.toml
nano ~/containers/config/gathio/config.toml
# 3. Restart service
systemctl --user restart gathio.service
# 4. Revoke old API key in SendGrid
```

---

## Recommendation

**For now:** Use Option 1 (no email)
- Zero configuration
- Works immediately
- Save editing links in Vaultwarden

**If you want email automation:** Use Option 2 (SendGrid)
- Free forever (100/day sufficient for personal use)
- API-based (more reliable than SMTP)
- 15 minutes to set up

**Avoid:** Creating new Gmail account just for this - adds complexity for minimal benefit.

---

## Related Documentation

- [Gathio GitHub](https://github.com/lowercasename/gathio)
- [SendGrid Free Plan](https://sendgrid.com/pricing/)
- [Brevo Pricing](https://www.brevo.com/pricing/)
- [Secrets Management Guide](../../30-security/guides/secrets-management.md)
