
---

## 📚 完整版 README

```markdown
# auto-shutdown 自动关机系统

> 一套基于 Linux 的智能自动定时关机系统，支持中国节假日识别、Web 可视化控制面板、年度自动升级。

[![版本](https://img.shields.io/badge/版本-v2.0.0-blue.svg)](https://github.com/your-repo)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange.svg)](https://ubuntu.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

---

## 📖 目录

- [一、项目简介](#一项目简介)
- [二、核心特性](#二核心特性)
- [三、系统架构](#三系统架构)
- [四、文件与目录说明](#四文件与目录说明)
- [五、安装教程](#五安装教程)
- [六、Web 控制面板](#六web-控制面板)
- [七、手动常用命令](#七手动常用命令)
- [八、卸载教程](#八卸载教程)
- [九、日志与监控](#九日志与监控)
- [十、故障排查](#十故障排查)
- [十一、更新日志](#十一更新日志)
- [十二、安全建议](#十二安全建议)
- [十三、常见问题](#十三常见问题)

---

## 一、项目简介

一套基于 **Linux + Python + Shell + Systemd + Crontab** 实现的**服务器/设备自动定时关机系统**。

### 适用场景
- 💻 个人电脑/服务器定时关机
- 🏢 办公室电脑节能管理
- 🖥️ 无人值守设备自动维护
- 🌙 夜间自动关机节省电力

### 核心工作流程
1. 每天凌晨 00:01 自动判断**今天是否为工作日**
2. **工作日** → 执行自动关机
3. **节假日/周末** → 跳过关机
4. Web 面板提供**临时跳过**和**永久禁用**控制

---

## 二、核心特性

### 🎯 智能节假日识别
- **多级数据源**：在线 API → 本地节假日库 → 周规则兜底
- **自动降级**：网络异常时自动切换备用方案
- **年度自动升级**：每年 12 月自动更新节假日库

### 🌐 Web 可视化面板
- 实时查看系统状态和下次关机时间
- 一键设置「今晚不关机」或「永久关闭」
- 缓存状态可视化（数据天数、年份、今日判断）
- 手动刷新节假日缓存

### 🔧 灵活控制机制
- **临时禁用**：仅今晚不关机，次日自动恢复
- **全局禁用**：永久关闭自动关机，需手动恢复
- **缓存刷新**：随时更新节假日数据

### 📊 完善的日志系统
- 每日关机执行日志（`/var/log/auto_shutdown.log`）
- 每周缓存刷新日志（`/var/log/auto_shutdown_refresh.log`）
- 库升级日志（`/opt/shutdown-ctrl/update_cc.log`）

### 🛡️ 高可用设计
- Systemd 服务自动重启
- 多级数据源容灾
- 缓存有效性自动验证
- 定时任务防重复机制

---

## 三、系统架构

### 数据流架构

```
┌─────────────────────────────────────────────────────────┐
│                    定时触发 (Crontab)                    │
│        每日 00:01 / 每周一 12:00 / 每年12月             │
└────────────────────┬────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│              核心脚本 (auto_shutdown_full.sh)            │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │          刷新节假日缓存 (优先级降级)              │   │
│  │  ① 在线 API (tool.bitefu.net)                   │   │
│  │  ② 本地库 (chinesecalendar)                    │   │
│  │  ③ 周规则兜底 (周一至周五=工作日)               │   │
│  └──────────────────────────────────────────────────┘   │
│                         ▼                               │
│  ┌──────────────────────────────────────────────────┐   │
│  │             关机判断逻辑                         │   │
│  │  ■ 检查全局锁 → 永久禁用？                      │   │
│  │  ■ 检查临时锁 → 今晚跳过？                      │   │
│  │  ■ 查询缓存 → 今天工作日？                      │   │
│  │  ■ 是 → 执行 shutdown -h now                   │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Web 控制面板 (Python HTTP Server)           │
│         端口: 6788 (可配置) / 密码保护                  │
└─────────────────────────────────────────────────────────┘
```

### 文件架构

```
/opt/shutdown-ctrl/                 # 程序主目录
├── web.py                          # Web 控制面板
├── update_cc.sh                    # 节假日库升级脚本
└── update_cc.log                   # 升级日志

/usr/local/bin/
└── auto_shutdown_full.sh           # 核心关机脚本

/etc/systemd/system/
└── shutdown-web.service            # Web 面板自启服务

/var/cache/
└── holiday_flat.json               # 节假日缓存

/var/log/
├── auto_shutdown.log               # 关机执行日志
└── auto_shutdown_refresh.log       # 缓存刷新日志

锁文件：
├── /etc/no_shutdown_all.lock       # 全局禁用锁
└── /tmp/no_shutdown.lock           # 临时禁用锁
```

---

## 四、文件与目录说明

### 核心脚本

| 文件 | 说明 | 权限 |
|------|------|------|
| `install_shutdown_all_fixed.sh` | 安装脚本（v2.0+） | 755 |
| `uninstall_shutdown_all_fixed.sh` | 卸载脚本（v2.0+） | 755 |
| `/usr/local/bin/auto_shutdown_full.sh` | 核心关机脚本 | 755 |
| `/opt/shutdown-ctrl/web.py` | Web 控制面板 | 755 |
| `/opt/shutdown-ctrl/update_cc.sh` | 库升级脚本 | 755 |

### 配置文件

| 文件 | 说明 | 格式 |
|------|------|------|
| `/var/cache/holiday_flat.json` | 节假日缓存 | JSON |
| `/etc/no_shutdown_all.lock` | 全局禁用锁 | 空文件 |
| `/tmp/no_shutdown.lock` | 临时禁用锁 | 空文件 |

### 日志文件

| 文件 | 说明 | 轮转 |
|------|------|------|
| `/var/log/auto_shutdown.log` | 每日关机日志 | 自动 |
| `/var/log/auto_shutdown_refresh.log` | 缓存刷新日志 | 自动 |
| `/opt/shutdown-ctrl/update_cc.log` | 库升级日志 | 自动 |

### 定时任务

```bash
# 查看所有定时任务
crontab -l | grep -E "auto_shutdown|update_cc"

# 任务列表
01 00 * * *  /usr/local/bin/auto_shutdown_full.sh          # 每日关机
00 12 * * 1  /usr/local/bin/auto_shutdown_full.sh --refresh # 每周刷新
00 03 1 12 * /opt/shutdown-ctrl/update_cc.sh               # 年度升级(1日)
00 03 15 12 * /opt/shutdown-ctrl/update_cc.sh              # 年度升级(15日)
```

---

## 五、安装教程

### 系统要求
- Ubuntu 22.04 / 24.04 (或 Debian 11+)
- root 权限或 sudo 权限
- 网络连接（首次安装需要下载依赖）
- 至少 100MB 可用磁盘空间

### 安装步骤

#### 1. 下载安装脚本

```bash
wget -O install_shutdown_all_fixed.sh https://your-server/install_shutdown_all_fixed.sh
# 或从本地复制
```

#### 2. 赋予执行权限

```bash
chmod +x install_shutdown_all_fixed.sh
```

#### 3. 执行安装

```bash
sudo ./install_shutdown_all_fixed.sh
```

#### 4. 交互配置

安装过程中会提示：

```
请输入面板监听端口(默认 6788): [按回车使用默认]
请输入面板访问密码(默认 Admin@123456): [建议修改]
```

#### 5. 安装完成

安装完成后会显示：

```
=============================================
✅ 全部安装完成！
🌐 访问地址：http://192.168.1.100:6788
🔑 登录密码：Admin@123456
...
=============================================
```

### 一键安装（非交互）

如需自动化部署，可以预设参数：

```bash
# 修改脚本中的默认值
DEFAULT_PORT="8080"
DEFAULT_PWD="MySecurePass123"

# 或使用管道输入
echo -e "8080\nMySecurePass123" | sudo ./install_shutdown_all_fixed.sh
```

---

## 六、Web 控制面板

### 访问面板

1. 浏览器打开：`http://服务器IP:端口`
2. 输入安装时设置的密码

### 面板功能介绍

#### 状态区域

| 元素 | 说明 |
|------|------|
| 系统状态 | 显示当前运行模式（正常/临时禁用/全局禁用） |
| 下次关机时间 | 显示下一次预计关机日期 |
| 缓存状态 | 显示缓存天数和年份 |
| 今日判断 | 显示今天是否为工作日 |

#### 操作按钮

| 按钮 | 功能 | 生效范围 | 持久性 |
|------|------|----------|--------|
| **今晚不关机** | 跳过今晚关机 | 单次 | 仅当天 |
| **恢复今晚关机** | 取消临时跳过 | 单次 | 立即生效 |
| **永久关闭自动关机** | 完全禁用关机 | 全局 | 需手动恢复 |
| **恢复自动关机** | 重新启用关机 | 全局 | 立即生效 |
| **手动刷新缓存** | 更新节假日数据 | 全局 | 立即生效 |

### 面板截图示例

```
┌──────────────────────────────────────────────────────┐
│              自动关机控制中心                         │
├──────────────────────────────────────────────────────┤
│ 当前系统状态                                        │
│ ✅ 自动关机已正常开启                               │
│ ⏰ 下次关机时间：2026-06-22 凌晨00:01              │
├──────────────────────────────────────────────────────┤
│ 📅 缓存状态：365 天数据（2026年）                   │
│ 📌 今天(2026-06-20)：节假日/周末                    │
│ [手动刷新缓存]                                      │
├──────────────────────────────────────────────────────┤
│ 今晚关机控制（单次生效）                            │
│ [今晚不关机]  [恢复今晚关机]                       │
│                                                      │
│ 全局关机控制（永久生效）                            │
│ [永久关闭]  [恢复自动关机]                         │
├──────────────────────────────────────────────────────┤
│ 使用说明：...                                       │
└──────────────────────────────────────────────────────┘
```

---

## 七、手动常用命令

### 节假日缓存管理

```bash
# 手动刷新节假日缓存（不执行关机）
/usr/local/bin/auto_shutdown_full.sh --refresh

# 查看当前缓存内容
cat /var/cache/holiday_flat.json | jq '.'

# 查看缓存数据条数
cat /var/cache/holiday_flat.json | jq '. | length'

# 查看今天是否为工作日
cat /var/cache/holiday_flat.json | jq '."'$(date +%Y-%m-%d)'"'
```

### Web 服务管理

```bash
# 启动服务
systemctl start shutdown-web

# 停止服务
systemctl stop shutdown-web

# 重启服务
systemctl restart shutdown-web

# 查看服务状态
systemctl status shutdown-web

# 查看服务日志
journalctl -u shutdown-web -f

# 开机自启（默认已启用）
systemctl enable shutdown-web

# 禁用开机自启
systemctl disable shutdown-web
```

### 锁文件管理

```bash
# 临时禁用今晚关机
touch /tmp/no_shutdown.lock

# 取消临时禁用
rm -f /tmp/no_shutdown.lock

# 永久禁用（所有日期）
touch /etc/no_shutdown_all.lock

# 恢复自动关机
rm -f /etc/no_shutdown_all.lock
```

### 定时任务管理

```bash
# 查看当前定时任务
crontab -l

# 手动触发立即关机（慎用）
/usr/local/bin/auto_shutdown_full.sh

# 测试关机逻辑（不真正关机）
# 编辑脚本注释掉 shutdown 命令
# 或使用 --refresh 模式测试缓存
```

---

## 八、卸载教程

### 使用卸载脚本（推荐）

```bash
# 下载卸载脚本
wget -O uninstall_shutdown_all_fixed.sh https://your-server/uninstall_shutdown_all_fixed.sh

# 赋予执行权限
chmod +x uninstall_shutdown_all_fixed.sh

# 执行卸载（需要确认）
sudo ./uninstall_shutdown_all_fixed.sh
```

### 手动完全清理

如果卸载脚本执行失败，可以手动清理：

```bash
#!/bin/bash
# 完全手动卸载

# 1. 停止服务
systemctl stop shutdown-web 2>/dev/null
systemctl disable shutdown-web 2>/dev/null
pkill -f web.py 2>/dev/null

# 2. 删除文件
rm -rf /opt/shutdown-ctrl
rm -f /usr/local/bin/auto_shutdown_full.sh
rm -f /etc/systemd/system/shutdown-web.service
rm -f /var/cache/holiday_flat.json
rm -f /etc/no_shutdown_all.lock
rm -f /tmp/no_shutdown.lock
rm -f /var/log/auto_shutdown.log
rm -f /var/log/auto_shutdown_refresh.log

# 3. 清理crontab
crontab -l 2>/dev/null | grep -v -E "auto_shutdown|update_cc|shutdown-ctrl" | crontab -

# 4. 卸载Python包（可选）
pip3 uninstall -y chinesecalendar --break-system-packages 2>/dev/null

# 5. 重载systemd
systemctl daemon-reload

echo "手动清理完成"
```

### 卸载后验证

```bash
# 检查服务
systemctl status shutdown-web 2>&1 | grep "not found"

# 检查文件
ls -la /opt/shutdown-ctrl 2>&1 | grep "No such file"

# 检查crontab
crontab -l | grep -E "auto_shutdown|update_cc"

# 检查防火墙（如使用ufw）
ufw status | grep 6788
```

---

## 九、日志与监控

### 日志文件说明

| 日志文件 | 内容 | 查看命令 |
|----------|------|----------|
| `/var/log/auto_shutdown.log` | 每日关机执行记录 | `tail -f /var/log/auto_shutdown.log` |
| `/var/log/auto_shutdown_refresh.log` | 缓存刷新记录 | `tail -f /var/log/auto_shutdown_refresh.log` |
| `/opt/shutdown-ctrl/update_cc.log` | 库升级记录 | `tail -f /opt/shutdown-ctrl/update_cc.log` |
| `journalctl -u shutdown-web` | Web 服务日志 | `journalctl -u shutdown-web -f` |

### 日志示例

```bash
# 正常关机日志
[2026-06-20 00:01:05] ==================== 刷新节假日缓存 ====================
[2026-06-20 00:01:05] 当前年份：2026
[2026-06-20 00:01:06] ✅ 在线API 请求成功
[2026-06-20 00:01:06] ✅ API解析成功，缓存了 365 天的数据
[2026-06-20 00:01:06] ==== 缓存内容预览（前10条） ====
[2026-06-20 00:01:06] ==================== 关机判定 ====================
[2026-06-20 00:01:06] 当前日期：2026-06-20
[2026-06-20 00:01:06] 当日是否工作日：false
[2026-06-20 00:01:06] ⏸️  节假日/周末，跳过关机
```

### 监控建议

```bash
# 创建监控脚本
cat > /usr/local/bin/check_shutdown.sh << 'EOF'
#!/bin/bash
# 检查关机系统状态

echo "=== 关机系统状态检查 ==="
echo "时间: $(date)"

# 检查Web服务
systemctl is-active shutdown-web && echo "✅ Web服务: 运行中" || echo "❌ Web服务: 已停止"

# 检查缓存
CACHE_COUNT=$(jq '. | length' /var/cache/holiday_flat.json 2>/dev/null || echo "0")
echo "📅 缓存天数: ${CACHE_COUNT}"

# 检查锁文件
[ -f /etc/no_shutdown_all.lock ] && echo "🔒 全局锁: 已启用" || echo "✅ 全局锁: 未启用"
[ -f /tmp/no_shutdown.lock ] && echo "🔒 临时锁: 已启用" || echo "✅ 临时锁: 未启用"

# 检查定时任务
CRON_COUNT=$(crontab -l 2>/dev/null | grep -c "auto_shutdown" || echo "0")
echo "⏰ 定时任务: ${CRON_COUNT} 个"
EOF

chmod +x /usr/local/bin/check_shutdown.sh
```

---

## 十、故障排查

### 常见问题及解决方案

#### 1. Web 面板无法访问

**症状**：浏览器无法打开 `http://IP:端口`

**排查步骤**：
```bash
# 检查服务状态
systemctl status shutdown-web

# 检查端口监听
ss -tlnp | grep 6788

# 检查防火墙
ufw status
iptables -L -n | grep 6788

# 查看服务日志
journalctl -u shutdown-web -n 50

# 手动启动测试
/opt/shutdown-ctrl/web.py
```

**解决方案**：
```bash
# 重启服务
systemctl restart shutdown-web

# 放行端口
ufw allow 6788/tcp

# 如果使用云服务商，检查安全组规则
```

---

#### 2. 节假日识别错误

**症状**：周末或法定节假日执行了关机

**排查步骤**：
```bash
# 查看缓存内容
cat /var/cache/holiday_flat.json | jq '."'$(date +%Y-%m-%d)'"'

# 手动刷新缓存
/usr/local/bin/auto_shutdown_full.sh --refresh

# 查看刷新日志
tail -20 /var/log/auto_shutdown_refresh.log
```

**解决方案**：
```bash
# 手动执行周规则兜底
python3 << 'PYEOF'
import datetime, json
cache = {}
year = datetime.date.today().year
start = datetime.date(year, 1, 1)
end = datetime.date(year, 12, 31)
current = start
while current <= end:
    cache[current.strftime("%Y-%m-%d")] = current.weekday() < 5
    current += datetime.timedelta(days=1)
with open("/var/cache/holiday_flat.json", "w") as f:
    json.dump(cache, f)
PYEOF

# 验证修复
cat /var/cache/holiday_flat.json | jq '."'$(date +%Y-%m-%d)'"'
```

---

#### 3. 定时任务不执行

**症状**：每天 00:01 系统不自动关机

**排查步骤**：
```bash
# 检查 crontab
crontab -l | grep auto_shutdown

# 检查 cron 服务
systemctl status cron

# 查看系统日志
grep CRON /var/log/syslog | tail -20

# 手动执行测试
/usr/local/bin/auto_shutdown_full.sh
```

**解决方案**：
```bash
# 重启 cron 服务
systemctl restart cron

# 重新添加定时任务
(crontab -l 2>/dev/null | grep -v auto_shutdown) | crontab -
echo "01 00 * * * /usr/local/bin/auto_shutdown_full.sh >> /var/log/auto_shutdown.log 2>&1" | crontab -
```

---

#### 4. Python 包安装失败

**症状**：`externally-managed-environment` 错误

**原因**：Ubuntu 24.04+ 的 PEP 668 保护机制

**解决方案**：
```bash
# 方法1：使用 --break-system-packages（脚本已支持）
pip3 install chinesecalendar --break-system-packages

# 方法2：创建虚拟环境
python3 -m venv /opt/shutdown-ctrl/venv
source /opt/shutdown-ctrl/venv/bin/activate
pip3 install chinesecalendar

# 方法3：使用 pipx
pipx install chinesecalendar
```

---

#### 5. 缓存文件损坏

**症状**：`jq: parse error` 或缓存为空

**解决方案**：
```bash
# 删除损坏的缓存
rm -f /var/cache/holiday_flat.json

# 重新生成
/usr/local/bin/auto_shutdown_full.sh --refresh

# 如果仍然失败，手动生成兜底缓存
echo "{}" > /var/cache/holiday_flat.json
/usr/local/bin/auto_shutdown_full.sh --refresh
```

---

#### 6. 磁盘空间不足

**症状**：日志文件占满磁盘

**解决方案**：
```bash
# 查看日志大小
du -sh /var/log/auto_shutdown*.log

# 清空日志
> /var/log/auto_shutdown.log
> /var/log/auto_shutdown_refresh.log

# 或设置日志轮转
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

## 十一、更新日志

### v2.0.0 - 2026-06-20 🎉

#### 🔥 关键修复
- **修复节假日缓存解析失败**：API 数据无法正确写入缓存文件的严重 Bug
- **修复 Crontab 任务混乱**：新旧任务重复和残留问题
- **修复卸载不彻底**：增加完整清理和验证机制

#### ✨ 新增功能
- Web 面板增加缓存状态显示（天数、年份、今日判断）
- Web 面板增加「手动刷新缓存」按钮
- 增强日志系统（结构化日志、带时间戳）
- 首次安装自动初始化缓存
- 服务状态自动验证

#### 🔒 安全增强
- 卸载操作增加确认机制
- crontab 自动备份
- 增加防火墙规则提示

#### 📝 文档完善
- 增加详细故障排查指南
- 增加监控脚本示例
- 增加架构图和数据流说明

---

### v1.2.0 - 2026-03-01

#### 新增
- 年度自动升级节假日库（每年12月执行）
- 升级失败自动重试（1日和15日双次执行）

#### 优化
- 缓存刷新效率提升
- 错误处理增强

---

### v1.1.0 - 2026-01-15

#### 新增
- Web 可视化控制面板
- 临时禁用和全局禁用功能
- 密码访问控制

---

### v1.0.0 - 2025-12-01

#### 初始版本
- 基础自动关机功能
- 多级节假日数据源
- Crontab 定时任务

---

## 十二、安全建议

### 1. 网络访问安全

```bash
# 仅允许内网访问
ufw allow from 192.168.0.0/16 to any port 6788

# 或使用 SSH 隧道（推荐）
ssh -L 6788:localhost:6788 user@server
# 然后访问 http://localhost:6788
```

### 2. 密码管理

- 安装时**务必修改默认密码**
- 密码应包含大小写字母+数字+特殊字符
- 定期更换密码（建议每季度）

### 3. 权限控制

```bash
# 限制脚本权限
chmod 750 /opt/shutdown-ctrl/web.py
chmod 750 /usr/local/bin/auto_shutdown_full.sh

# 创建专用用户
useradd -r -s /bin/bash shutdown-ctrl
chown -R shutdown-ctrl:shutdown-ctrl /opt/shutdown-ctrl
```

### 4. 日志审计

```bash
# 定期检查登录日志
grep "Password Error" /var/log/auto_shutdown.log

# 监控异常访问
tail -f /var/log/auto_shutdown.log | grep -E "Password Error|403"
```

---

## 十三、常见问题

### Q1: 可以自定义关机时间吗？

**A**: 可以。修改 crontab：
```bash
crontab -e
# 将 "01 00 * * *" 改为所需时间，如 "30 23 * * *" (23:30)
```

### Q2: 如何添加自定义节假日？

**A**: 手动修改缓存文件：
```bash
# 添加自定义节假日
jq '."2026-12-25" = false' /var/cache/holiday_flat.json > /tmp/tmp.json
mv /tmp/tmp.json /var/cache/holiday_flat.json
```

### Q3: 支持多个服务器吗？

**A**: 当前为单机版本，多服务器需要分别安装。未来版本将支持分布式管理。

### Q4: 如何测试而不真正关机？

**A**: 使用 `--refresh` 模式：
```bash
/usr/local/bin/auto_shutdown_full.sh --refresh
# 只刷新缓存，不执行关机
```

### Q5: 缓存数据会过期吗？

**A**: 缓存数据按年存储，每周自动刷新，每年自动升级。建议确保服务器时间正确。

### Q6: 可以切换其他 API 源吗？

**A**: 可以。修改脚本中的 API URL：
```bash
# 编辑脚本
vim /usr/local/bin/auto_shutdown_full.sh
# 修改 url="https://tool.bitefu.net/jiari/?d=${CUR_YEAR}&json=1"
# 替换为其他兼容 API
```

### Q7: 卸载后如何完全清理 Python 包？

**A**: 
```bash
# 查看已安装包
pip3 list | grep chinese

# 强制卸载
pip3 uninstall chinesecalendar --break-system-packages

# 清理 pip 缓存
pip3 cache purge
```

---

## 附录

### A. 兼容性列表

| 系统 | 版本 | 状态 |
|------|------|------|
| Ubuntu | 22.04 LTS | ✅ 完全支持 |
| Ubuntu | 24.04 LTS | ✅ 完全支持 |
| Debian | 11 (Bullseye) | ✅ 完全支持 |
| Debian | 12 (Bookworm) | ✅ 完全支持 |
| CentOS | 7+ | ⚠️ 需修改包管理命令 |

### B. 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `LISTEN_PORT` | Web 面板端口 | 6788 |
| `ACCESS_PWD` | Web 面板密码 | Admin@123456 |
| `API_TIMEOUT` | API 超时时间 | 20秒 |
| `MAX_RETRY` | API 重试次数 | 2次 |

### C. 相关链接

- [chinesecalendar 文档](https://github.com/LKI/chinese-calendar)
- [Systemd 服务配置](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Crontab 语法说明](https://crontab.guru/)

---

## 贡献与反馈

如有问题或建议，请提交 Issue 或 Pull Request。

**维护者**：系统运维团队  
**最后更新**：2026-06-20  
**版本**：v2.0.0

---

**许可证**：MIT License

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
