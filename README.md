---

```markdown
# Auto-Shutdown System

> An intelligent automatic timed shutdown system based on Linux, with Chinese holiday recognition, web‑based control panel, and annual automatic upgrade.

[![Version](https://img.shields.io/badge/version-v2.0.0-blue.svg)](https://github.com/your-repo)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange.svg)](https://ubuntu.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

---

## Table of Contents

- [1. Introduction](#1-introduction)
- [2. Key Features](#2-key-features)
- [3. System Architecture](#3-system-architecture)
- [4. File and Directory Structure](#4-file-and-directory-structure)
- [5. Installation Guide](#5-installation-guide)
- [6. Web Control Panel](#6-web-control-panel)
- [7. Manual Commands](#7-manual-commands)
- [8. Uninstallation](#8-uninstallation)
- [9. Logging and Monitoring](#9-logging-and-monitoring)
- [10. Troubleshooting](#10-troubleshooting)
- [11. Changelog](#11-changelog)
- [12. Security Recommendations](#12-security-recommendations)
- [13. FAQ](#13-faq)

---

## 1. Introduction

A **Linux + Python + Shell + Systemd + Crontab** based system for **automatic timed shutdown** of servers or personal computers.

### Use Cases
- 💻 Personal computer / server scheduled shutdown
- 🏢 Office energy saving management
- 🖥️ Unattended device maintenance
- 🌙 Night‑time automatic power‑off to save electricity

### Core Workflow
1. Every day at 00:01, the system checks whether **today is a workday**.
2. If **workday** → executes `shutdown -h now`.
3. If **holiday / weekend** → skips shutdown.
4. The web panel allows **temporary skip** and **permanent disable** controls.

---

## 2. Key Features

### 🎯 Smart Holiday Recognition
- **Multi‑level data sources**: online API → local `chinesecalendar` library → weekday‑based fallback.
- **Automatic fallback**: when network is unavailable, it seamlessly switches to backup schemes.
- **Yearly auto‑upgrade**: automatically updates the holiday library every December.

### 🌐 Web Visual Panel
- Real‑time system status and next shutdown time.
- One‑click “skip tonight” or “permanently disable”.
- Cache status (days, year, today’s workday judgement).
- Manual cache refresh button.

### 🔧 Flexible Control
- **Temporary disable**: only tonight, automatically restored next day.
- **Global disable**: permanently turns off auto‑shutdown until manually re‑enabled.
- **Cache refresh**: update holiday data at any time.

### 📊 Comprehensive Logging
- Daily shutdown log (`/var/log/auto_shutdown.log`)
- Weekly cache refresh log (`/var/log/auto_shutdown_refresh.log`)
- Library upgrade log (`/opt/shutdown-ctrl/update_cc.log`)

### 🛡️ High Availability
- Systemd service auto‑restart.
- Multi‑source data redundancy.
- Automatic cache validation.
- Cron job de‑duplication.

---

## 3. System Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────┐
│              Scheduled Triggers (Crontab)               │
│        Daily 00:01 / Monday 12:00 / Every December      │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│           Core Script (auto_shutdown_full.sh)            │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │       Refresh Holiday Cache (priority fallback)   │   │
│  │  ① Online API (tool.bitefu.net)                  │   │
│  │  ② Local library (chinesecalendar)               │   │
│  │  ③ Weekday fallback (Mon‑Fri = workday)          │   │
│  └──────────────────────────────────────────────────┘   │
│                         ▼                               │
│  ┌──────────────────────────────────────────────────┐   │
│  │          Shutdown Decision Logic                  │   │
│  │  ■ Check global lock → permanently disabled?     │   │
│  │  ■ Check temporary lock → skip tonight?          │   │
│  │  ■ Query cache → is today a workday?             │   │
│  │  ■ Yes → execute shutdown -h now                 │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│        Web Control Panel (Python HTTP Server)            │
│        Port: 6788 (configurable) / password protected   │
└─────────────────────────────────────────────────────────┘
```

### File Layout

```
/opt/shutdown-ctrl/                 # Program directory
├── web.py                          # Web control panel
├── update_cc.sh                    # Library upgrade script
└── update_cc.log                   # Upgrade log

/usr/local/bin/
└── auto_shutdown_full.sh           # Core shutdown script

/etc/systemd/system/
└── shutdown-web.service            # Web service unit

/var/cache/
└── holiday_flat.json               # Holiday cache

/var/log/
├── auto_shutdown.log               # Shutdown execution log
└── auto_shutdown_refresh.log       # Cache refresh log

Lock files:
├── /etc/no_shutdown_all.lock       # Global disable lock
└── /tmp/no_shutdown.lock           # Temporary disable lock
```

---

## 4. File and Directory Structure

### Core Scripts

| File | Description | Permissions |
|------|-------------|-------------|
| `install_shutdown_all_fixed.sh` | Installation script (v2.0+) | 755 |
| `uninstall_shutdown_all_fixed.sh` | Uninstall script (v2.0+) | 755 |
| `/usr/local/bin/auto_shutdown_full.sh` | Core shutdown script | 755 |
| `/opt/shutdown-ctrl/web.py` | Web control panel | 755 |
| `/opt/shutdown-ctrl/update_cc.sh` | Library upgrade script | 755 |

### Configuration Files

| File | Description | Format |
|------|-------------|--------|
| `/var/cache/holiday_flat.json` | Holiday cache | JSON |
| `/etc/no_shutdown_all.lock` | Global disable lock | empty |
| `/tmp/no_shutdown.lock` | Temporary disable lock | empty |

### Log Files

| File | Description | Rotation |
|------|-------------|----------|
| `/var/log/auto_shutdown.log` | Daily shutdown log | automatic |
| `/var/log/auto_shutdown_refresh.log` | Cache refresh log | automatic |
| `/opt/shutdown-ctrl/update_cc.log` | Library upgrade log | automatic |

### Cron Jobs

```bash
# View all scheduled tasks
crontab -l | grep -E "auto_shutdown|update_cc"

# Task list
01 00 * * *  /usr/local/bin/auto_shutdown_full.sh          # Daily shutdown
00 12 * * 1  /usr/local/bin/auto_shutdown_full.sh --refresh # Weekly refresh
00 03 1 12 * /opt/shutdown-ctrl/update_cc.sh               # Yearly upgrade (1st)
00 03 15 12 * /opt/shutdown-ctrl/update_cc.sh              # Yearly upgrade (15th)
```

---

## 5. Installation Guide

### System Requirements
- Ubuntu 22.04 / 24.04 (or Debian 11+)
- Root or sudo privileges
- Internet connection (for first‑time dependencies)
- At least 100 MB free disk space

### Steps

#### 1. Download the installation script
```bash
wget -O install_shutdown_all_fixed.sh https://your-server/install_shutdown_all_fixed.sh
# or copy from local source
```

#### 2. Make it executable
```bash
chmod +x install_shutdown_all_fixed.sh
```

#### 3. Run the installer
```bash
sudo ./install_shutdown_all_fixed.sh
```

#### 4. Interactive configuration
During installation you will be prompted:
```
Enter web panel port (default 6788): [press Enter to use default]
Enter web panel password (default Admin@123456): [change it for security]
```

#### 5. Installation complete
You will see:
```
=============================================
✅ Installation completed successfully!
🌐 Access URL: http://192.168.1.100:6788
🔑 Password: Admin@123456
...
=============================================
```

### Non‑interactive Installation (Automation)
You can preset defaults by editing the script or using pipeline input:
```bash
# Modify default values in the script
DEFAULT_PORT="8080"
DEFAULT_PWD="MySecurePass123"

# Or use echo to feed input
echo -e "8080\nMySecurePass123" | sudo ./install_shutdown_all_fixed.sh
```

---

## 6. Web Control Panel

### Access
1. Open browser: `http://<server-ip>:<port>`
2. Enter the password set during installation.

### Panel Features

#### Status Area
| Element | Description |
|---------|-------------|
| System status | Current mode (normal / temporary disabled / globally disabled) |
| Next shutdown | Estimated next shutdown date |
| Cache status | Number of cached days and year |
| Today’s judgement | Shows if today is a workday |

#### Action Buttons
| Button | Function | Scope | Persistence |
|--------|----------|-------|-------------|
| **Skip tonight** | Skip tonight’s shutdown | Single use | Only today |
| **Restore tonight** | Cancel temporary skip | Single use | Immediate |
| **Permanently disable** | Completely disable shutdown | Global | Manual restore required |
| **Restore auto‑shutdown** | Re‑enable shutdown | Global | Immediate |
| **Manual refresh cache** | Update holiday data | Global | Immediate |

### Panel UI Example

```
┌──────────────────────────────────────────────────────┐
│            Auto Shutdown Control Center              │
├──────────────────────────────────────────────────────┤
│ Current System Status                               │
│ ✅ Auto‑shutdown is enabled normally                │
│ ⏰ Next shutdown: 2026-06-22 00:01                  │
├──────────────────────────────────────────────────────┤
│ 📅 Cache: 365 days (2026)                           │
│ 📌 Today(2026-06-20): holiday/weekend               │
│ [Manual Refresh Cache]                              │
├──────────────────────────────────────────────────────┤
│ Tonight Control (single‑shot)                       │
│ [Skip Tonight]  [Restore Tonight]                   │
│                                                      │
│ Global Control (permanent)                          │
│ [Permanently Disable]  [Restore Auto‑Shutdown]     │
├──────────────────────────────────────────────────────┤
│ Instructions: ...                                   │
└──────────────────────────────────────────────────────┘
```

---

## 7. Manual Commands

### Holiday Cache Management
```bash
# Manually refresh cache (no shutdown)
/usr/local/bin/auto_shutdown_full.sh --refresh

# View current cache content
cat /var/cache/holiday_flat.json | jq '.'

# Count cached entries
cat /var/cache/holiday_flat.json | jq '. | length'

# Check today’s workday status
cat /var/cache/holiday_flat.json | jq '."'$(date +%Y-%m-%d)'"'
```

### Web Service Management
```bash
# Start service
systemctl start shutdown-web

# Stop service
systemctl stop shutdown-web

# Restart service
systemctl restart shutdown-web

# Check status
systemctl status shutdown-web

# View service logs
journalctl -u shutdown-web -f

# Enable on boot (enabled by default)
systemctl enable shutdown-web

# Disable on boot
systemctl disable shutdown-web
```

### Lock File Management
```bash
# Temporarily disable tonight
touch /tmp/no_shutdown.lock

# Cancel temporary disable
rm -f /tmp/no_shutdown.lock

# Permanently disable (all dates)
touch /etc/no_shutdown_all.lock

# Restore auto‑shutdown
rm -f /etc/no_shutdown_all.lock
```

### Crontab Management
```bash
# View current cron jobs
crontab -l

# Manually trigger immediate shutdown (use with caution)
/usr/local/bin/auto_shutdown_full.sh

# Test shutdown logic without actually shutting down
# (edit the script to comment out the shutdown command, or use --refresh)
```

---

## 8. Uninstallation

### Using the Uninstall Script (Recommended)
```bash
# Download the uninstall script
wget -O uninstall_shutdown_all_fixed.sh https://your-server/uninstall_shutdown_all_fixed.sh

# Make executable
chmod +x uninstall_shutdown_all_fixed.sh

# Run (confirmation required)
sudo ./uninstall_shutdown_all_fixed.sh
```

### Manual Complete Cleanup
If the uninstall script fails, you can manually remove everything:
```bash
#!/bin/bash
# Manual full uninstall

# 1. Stop services
systemctl stop shutdown-web 2>/dev/null
systemctl disable shutdown-web 2>/dev/null
pkill -f web.py 2>/dev/null

# 2. Delete files
rm -rf /opt/shutdown-ctrl
rm -f /usr/local/bin/auto_shutdown_full.sh
rm -f /etc/systemd/system/shutdown-web.service
rm -f /var/cache/holiday_flat.json
rm -f /etc/no_shutdown_all.lock
rm -f /tmp/no_shutdown.lock
rm -f /var/log/auto_shutdown.log
rm -f /var/log/auto_shutdown_refresh.log

# 3. Clean crontab
crontab -l 2>/dev/null | grep -v -E "auto_shutdown|update_cc|shutdown-ctrl" | crontab -

# 4. Uninstall Python package (optional)
pip3 uninstall -y chinesecalendar --break-system-packages 2>/dev/null

# 5. Reload systemd
systemctl daemon-reload

echo "Manual cleanup completed"
```

### Post‑uninstall Verification
```bash
# Check service
systemctl status shutdown-web 2>&1 | grep "not found"

# Check files
ls -la /opt/shutdown-ctrl 2>&1 | grep "No such file"

# Check crontab
crontab -l | grep -E "auto_shutdown|update_cc"

# Check firewall (if using ufw)
ufw status | grep 6788
```

---

## 9. Logging and Monitoring

### Log Files Overview

| Log File | Content | View Command |
|----------|---------|--------------|
| `/var/log/auto_shutdown.log` | Daily shutdown execution | `tail -f /var/log/auto_shutdown.log` |
| `/var/log/auto_shutdown_refresh.log` | Cache refresh records | `tail -f /var/log/auto_shutdown_refresh.log` |
| `/opt/shutdown-ctrl/update_cc.log` | Library upgrade records | `tail -f /opt/shutdown-ctrl/update_cc.log` |
| `journalctl -u shutdown-web` | Web service logs | `journalctl -u shutdown-web -f` |

### Log Example
```bash
# Normal shutdown log
[2026-06-20 00:01:05] ==================== Refresh holiday cache ====================
[2026-06-20 00:01:05] Current year: 2026
[2026-06-20 00:01:06] ✅ Online API request successful
[2026-06-20 00:01:06] ✅ API parsed successfully, cached 365 days
[2026-06-20 00:01:06] ==== Cache preview (first 10 entries) ====
[2026-06-20 00:01:06] ==================== Shutdown decision ====================
[2026-06-20 00:01:06] Current date: 2026-06-20
[2026-06-20 00:01:06] Is workday today: false
[2026-06-20 00:01:06] ⏸️  Holiday/weekend, skipping shutdown
```

### Monitoring Script
```bash
# Create a monitoring script
cat > /usr/local/bin/check_shutdown.sh << 'EOF'
#!/bin/bash
echo "=== Shutdown System Status ==="
echo "Time: $(date)"

systemctl is-active shutdown-web && echo "✅ Web service: running" || echo "❌ Web service: stopped"

CACHE_COUNT=$(jq '. | length' /var/cache/holiday_flat.json 2>/dev/null || echo "0")
echo "📅 Cache entries: ${CACHE_COUNT}"

[ -f /etc/no_shutdown_all.lock ] && echo "🔒 Global lock: enabled" || echo "✅ Global lock: disabled"
[ -f /tmp/no_shutdown.lock ] && echo "🔒 Temporary lock: enabled" || echo "✅ Temporary lock: disabled"

CRON_COUNT=$(crontab -l 2>/dev/null | grep -c "auto_shutdown" || echo "0")
echo "⏰ Cron jobs: ${CRON_COUNT}"
EOF

chmod +x /usr/local/bin/check_shutdown.sh
```

---

## 10. Troubleshooting

### Common Issues & Solutions

#### 1. Web Panel Not Accessible
**Symptoms**: Browser cannot open `http://IP:port`

**Check steps**:
```bash
systemctl status shutdown-web
ss -tlnp | grep 6788
ufw status
journalctl -u shutdown-web -n 50
/opt/shutdown-ctrl/web.py   # manual start test
```

**Solutions**:
```bash
systemctl restart shutdown-web
ufw allow 6788/tcp
# If using cloud, check security group rules
```

---

#### 2. Incorrect Holiday Recognition
**Symptoms**: Shutdown executed on weekends or public holidays

**Check**:
```bash
cat /var/cache/holiday_flat.json | jq '."'$(date +%Y-%m-%d)'"'
/usr/local/bin/auto_shutdown_full.sh --refresh
tail -20 /var/log/auto_shutdown_refresh.log
```

**Fix**: Force fallback to weekday rule
```bash
python3 << 'PYEOF'
import datetime, json
cache = {}
year = datetime.date.today().year
start = datetime.date(year, 1, 1)
end = datetime.date(year, 12, 31)
cur = start
while cur <= end:
    cache[cur.strftime("%Y-%m-%d")] = cur.weekday() < 5
    cur += datetime.timedelta(days=1)
with open("/var/cache/holiday_flat.json", "w") as f:
    json.dump(cache, f)
PYEOF
```

---

#### 3. Cron Jobs Not Executing
**Symptoms**: Auto‑shutdown does not run at 00:01

**Check**:
```bash
crontab -l | grep auto_shutdown
systemctl status cron
grep CRON /var/log/syslog | tail -20
/usr/local/bin/auto_shutdown_full.sh   # manual test
```

**Fix**:
```bash
systemctl restart cron
(crontab -l 2>/dev/null | grep -v auto_shutdown) | crontab -
echo "01 00 * * * /usr/local/bin/auto_shutdown_full.sh >> /var/log/auto_shutdown.log 2>&1" | crontab -
```

---

#### 4. Python Package Installation Fails (externally‑managed‑environment)
**Cause**: PEP 668 protection in Ubuntu 24.04+

**Solutions**:
```bash
# Method 1: Use --break-system-packages (used by script)
pip3 install chinesecalendar --break-system-packages

# Method 2: Use a virtual environment
python3 -m venv /opt/shutdown-ctrl/venv
source /opt/shutdown-ctrl/venv/bin/activate
pip3 install chinesecalendar

# Method 3: Use pipx
pipx install chinesecalendar
```

---

#### 5. Corrupted Cache File
**Symptoms**: `jq: parse error` or empty cache

**Fix**:
```bash
rm -f /var/cache/holiday_flat.json
/usr/local/bin/auto_shutdown_full.sh --refresh
# Or manual fallback
echo "{}" > /var/cache/holiday_flat.json
/usr/local/bin/auto_shutdown_full.sh --refresh
```

---

#### 6. Disk Space Full
**Symptoms**: Log files consume all space

**Fix**:
```bash
du -sh /var/log/auto_shutdown*.log
> /var/log/auto_shutdown.log
> /var/log/auto_shutdown_refresh.log

# Set up log rotation
cat > /etc/logrotate.d/auto_shutdown << 'EOF'
/var/log/auto_shutdown.log
/var/log/auto_shutdown_refresh.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
EOF
```

---

## 11. Changelog

### v2.0.0 - 2026-06-20 🎉

#### 🔥 Critical Fixes
- Fixed holiday cache parsing failure (API data not correctly written to cache)
- Fixed crontab duplication and leftover tasks
- Improved uninstallation completeness

#### ✨ New Features
- Cache status display on web panel (days, year, today’s judgement)
- Manual cache refresh button on web panel
- Enhanced logging (structured, timestamped)
- Automatic cache initialisation on first install
- Service status verification

#### 🔒 Security Enhancements
- Confirmation prompt for uninstallation
- Automatic crontab backup
- Firewall rule reminder

#### 📝 Documentation
- Detailed troubleshooting guide
- Monitoring script example
- Architecture diagram and data flow

---

### v1.2.0 - 2026-03-01
- Annual automatic library upgrade (December)
- Retry mechanism on upgrade failure (1st and 15th)

### v1.1.0 - 2026-01-15
- Web control panel
- Temporary and global disable functions
- Password‑protected access

### v1.0.0 - 2025-12-01
- Initial release with core shutdown logic
- Multi‑level holiday data sources
- Crontab scheduling

---

## 12. Security Recommendations

### 1. Network Access
```bash
# Restrict to local network
ufw allow from 192.168.0.0/16 to any port 6788

# Or use SSH tunnel (recommended)
ssh -L 6788:localhost:6788 user@server
# Then access http://localhost:6788
```

### 2. Password Management
- **Always change the default password** during installation.
- Use a strong password (uppercase, lowercase, numbers, special characters).
- Rotate passwords regularly (quarterly recommended).

### 3. Permissions
```bash
chmod 750 /opt/shutdown-ctrl/web.py
chmod 750 /usr/local/bin/auto_shutdown_full.sh

# Create a dedicated user
useradd -r -s /bin/bash shutdown-ctrl
chown -R shutdown-ctrl:shutdown-ctrl /opt/shutdown-ctrl
```

### 4. Log Auditing
```bash
# Check for failed login attempts
grep "Password Error" /var/log/auto_shutdown.log

# Monitor suspicious accesses
tail -f /var/log/auto_shutdown.log | grep -E "Password Error|403"
```

---

## 13. FAQ

**Q1: Can I customise the shutdown time?**  
A: Yes. Edit the crontab:
```bash
crontab -e
# Change "01 00 * * *" to your desired time, e.g., "30 23 * * *" (23:30)
```

**Q2: How do I add custom holidays?**  
A: Manually edit the cache file:
```bash
jq '."2026-12-25" = false' /var/cache/holiday_flat.json > /tmp/tmp.json
mv /tmp/tmp.json /var/cache/holiday_flat.json
```

**Q3: Does it support multiple servers?**  
A: Currently single‑server only; multi‑server management is planned for future releases.

**Q4: How can I test without actually shutting down?**  
A: Use `--refresh` mode:
```bash
/usr/local/bin/auto_shutdown_full.sh --refresh
# Only refreshes cache, does not shut down
```

**Q5: Does the cache expire?**  
A: Cache is yearly, automatically refreshed weekly and upgraded annually. Make sure system time is correct.

**Q6: Can I switch to another API source?**  
A: Yes. Edit the script:
```bash
vim /usr/local/bin/auto_shutdown_full.sh
# Change the url variable to your preferred API endpoint
```

**Q7: How to completely remove Python packages after uninstall?**  
A:
```bash
pip3 list | grep chinese
pip3 uninstall chinesecalendar --break-system-packages
pip3 cache purge
```

---

## Appendix

### A. Compatibility Matrix

| OS | Version | Status |
|----|---------|--------|
| Ubuntu | 22.04 LTS | ✅ Fully supported |
| Ubuntu | 24.04 LTS | ✅ Fully supported |
| Debian | 11 (Bullseye) | ✅ Fully supported |
| Debian | 12 (Bookworm) | ✅ Fully supported |
| CentOS | 7+ | ⚠️ Package manager commands differ |

### B. Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LISTEN_PORT` | Web panel port | 6788 |
| `ACCESS_PWD` | Web panel password | Admin@123456 |
| `API_TIMEOUT` | API timeout (seconds) | 20 |
| `MAX_RETRY` | API retry count | 2 |

### C. Useful Links

- [chinesecalendar documentation](https://github.com/LKI/chinese-calendar)
- [Systemd service configuration](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Crontab syntax reference](https://crontab.guru/)

---

## Contributing & Feedback

For issues or suggestions, please open an Issue or Pull Request.

**Maintainer**: System Operations Team  
**Last Updated**: 2026-06-20  
**Version**: v2.0.0

---

**License**: MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---