➜  ~ ~/containers/scripts/configure-authelia-dual-domain-org.sh 
========================================
  Authelia Dual-Domain Configuration
========================================

[✓] Backed up configuration to:
    /home/patriark/containers/backups/authelia-config-20251022-184131.yml

Configuration changes:

--- /home/patriark/containers/config/authelia/configuration.yml	2025-10-22 18:37:11.961560353 +0200
+++ /home/patriark/containers/config/authelia/configuration.yml.new	2025-10-22 18:41:31.290519218 +0200
@@ -1,16 +1,26 @@
 ---
-# Authelia Configuration - Working Version
-# Domain: patriark.lokal
+# Authelia Configuration - Dual Domain Support
+# Domains: patriark.lokal (LAN) + patriark.org (Internet)
+# Updated: 2025-10-22
 
 theme: 'dark'
 default_2fa_method: 'webauthn'
 
 server:
   address: 'tcp://0.0.0.0:9091'
+  buffers:
+    read: 4096
+    write: 4096
+  timeouts:
+    read: '6s'
+    write: '6s'
+    idle: '30s'
 
 log:
   level: 'info'
   format: 'text'
+  file_path: ''
+  keep_stdout: true
 
 identity_validation:
   reset_password:
@@ -18,20 +28,22 @@
 
 totp:
   disable: false
-  issuer: 'patriark.lokal'
+  issuer: 'patriark.org'
   algorithm: 'sha512'
   digits: 6
   period: 30
   skew: 1
+  secret_size: 32
 
 webauthn:
   disable: false
   display_name: 'Patriark Homelab'
   attestation_conveyance_preference: 'indirect'
+  user_verification: 'preferred'
+  
+  # Multiple origins for both domains
   timeout: '60s'
-  selection_criteria:
-    user_verification: 'preferred'
-
+  
 authentication_backend:
   password_reset:
     disable: false
@@ -39,6 +51,7 @@
   
   file:
     path: '/config/users_database.yml'
+    watch: true
     password:
       algorithm: 'argon2'
       argon2:
@@ -49,34 +62,89 @@
         key_length: 32
         salt_length: 16
 
+# CRITICAL: Dual-domain access control
 access_control:
   default_policy: 'deny'
   
+  networks:
+    - name: 'internal'
+      networks:
+        - '192.168.1.0/24'
+        - '10.89.0.0/16'
+    
+    - name: 'vpn'
+      networks:
+        - '192.168.100.0/24'
+  
   rules:
+    # Authelia portal - always accessible (both domains)
     - domain:
         - 'auth.patriark.lokal'
+        - 'auth.patriark.org'
       policy: 'bypass'
     
+    # Admin interfaces - internal network or VPN only
     - domain:
         - 'traefik.patriark.lokal'
+        - 'traefik.patriark.org'
+      policy: 'two_factor'
+      networks:
+        - 'internal'
+        - 'vpn'
+    
+    # Jellyfin - accessible from anywhere with 2FA
+    - domain:
         - 'jellyfin.patriark.lokal'
+        - 'jellyfin.patriark.org'
+      policy: 'two_factor'
+    
+    # Future services - locked to internal/VPN initially
+    - domain:
         - 'nextcloud.patriark.lokal'
+        - 'nextcloud.patriark.org'
         - 'vaultwarden.patriark.lokal'
+        - 'vaultwarden.patriark.org'
       policy: 'two_factor'
+      networks:
+        - 'internal'
+        - 'vpn'
 
+# CRITICAL: Dual-domain session configuration
 session:
   secret: 'file:///run/secrets/authelia_session_secret'
   name: 'authelia_session'
+  
+  # Use 'lax' for better compatibility with redirects
   same_site: 'lax'
+  
+  # Session timeouts
   inactivity: '5m'
   expiration: '1h'
   remember_me: '1M'
   
+  # Multiple cookie domains for LAN and internet access
   cookies:
+    # LAN access via .lokal domain
     - domain: 'patriark.lokal'
       authelia_url: 'https://auth.patriark.lokal'
       default_redirection_url: 'https://jellyfin.patriark.lokal'
+      name: 'authelia_session'
+      same_site: 'lax'
+      inactivity: '5m'
+      expiration: '1h'
+      remember_me: '1M'
+    
+    # Internet access via .dev domain
+    - domain: 'patriark.org'
+      authelia_url: 'https://auth.patriark.org'
+      default_redirection_url: 'https://jellyfin.patriark.org'
+      name: 'authelia_session'
+      same_site: 'lax'
+      inactivity: '5m'
+      expiration: '1h'
+      remember_me: '1M'
   
+  # Redis backend for session storage
   redis:
     host: 'authelia-redis'
     port: 6379
@@ -84,6 +152,9 @@
     database_index: 0
     maximum_active_connections: 8
     minimum_idle_connections: 0
+    tls:
+      skip_verify: false
+      minimum_version: 'TLS1.2'
 
 storage:
   encryption_key: 'file:///run/secrets/authelia_storage_key'
@@ -92,10 +163,35 @@
 
 notifier:
   disable_startup_check: false
-  filesystem:
-    filename: '/config/notifications.txt'
+  
+  # SMTP configuration (update with your credentials)
+  smtp:
+    address: 'smtp://smtp-mail.outlook.com:587'
+    timeout: '5s'
+    username: 'blyhode@hotmail.com'
+    password: 'file:///run/secrets/smtp_password'
+    sender: 'Authelia <auth@patriark.org>'
+    identifier: 'patriark.org'
+    subject: '[Patriark Homelab] {title}'
+    startup_check_address: 'blyhode@hotmail.com'
+    disable_require_tls: false
+    disable_html_emails: false
+    
+    tls:
+      server_name: 'smtp-mail.outlook.com'
+      skip_verify: false
+      minimum_version: 'TLS1.2'
 
+# Brute force protection
 regulation:
-  max_retries: 3
+  max_retries: 5
   find_time: '2m'
-  ban_time: '5m'
+  ban_time: '10m'
+
+# NTP for time synchronization (important for TOTP)
+ntp:
+  address: 'time.cloudflare.com:123'
+  version: 4
+  max_desync: '3s'
+  disable_startup_check: false
+  disable_failure: false

Review the changes above.
Apply new configuration? (yes/no): yes
[✓] Configuration applied

Validating configuration...
[!] yamllint not installed, skipping syntax check

Testing with Authelia validator...
Error: unknown command "/config/configuration.yml" for "authelia validate-config"
Usage:
  authelia validate-config [flags]

Examples:
authelia validate-config
authelia validate-config --config config.yml

Flags:
  -h, --help   help for validate-config

Global Flags:
  -c, --config strings                        configuration files or directories to load, for more information run 'authelia -h authelia config' (default [configuration.yml])
      --config.experimental.filters strings   list of filters to apply to all configuration files, for more information run 'authelia -h authelia filters'


========================================
  Post-Configuration Steps
========================================

1. Ensure secrets are created:
   - /home/patriark/containers/secrets/redis_password
   - /home/patriark/containers/secrets/smtp_password

2. Update SMTP password if using Outlook/Hotmail:
   # Create app password at: account.microsoft.com
   echo "your_app_password_here" > ~/containers/secrets/smtp_password
   chmod 600 ~/containers/secrets/smtp_password

3. Restart Authelia to apply changes:
   systemctl --user restart authelia.service

4. Clear Redis sessions (if login loop persists):
   podman exec -it authelia-redis redis-cli -a "$(cat ~/containers/secrets/redis_password)" FLUSHDB

5. Test authentication:
   LAN:      https://jellyfin.patriark.lokal
   Internet: https://jellyfin.patriark.org (after DNS/port forwarding)

Configuration update complete!
