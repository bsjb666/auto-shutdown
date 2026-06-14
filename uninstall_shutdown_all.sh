#!/bin/bash
set -euo pipefail

GLOBAL_LOCK="/etc/no_shutdown_all.lock"
TEMP_LOCK="/tmp/no_shutdown.lock"
CACHE_FILE="/var/cache/holiday_flat.json"
APP_DIR="/opt/shutdown-ctrl"
SHUTDOWN_BIN="/usr/local/bin/auto_shutdown_full.sh"
LOG_DAILY="/var/log/auto_shutdown.log"
LOG_WEEKLY="/var/log/auto_shutdown_refresh.log"
SERVICE_FILE="/etc/systemd/system/shutdown-web.service"

if [[ $(id -u) -ne 0 ]]; then
    echo "请使用 root / sudo 执行本脚本"
    exit 1
fi

echo "============================================="
echo "        自动关机系统 一键卸载清理            "
echo "============================================="

# 1. 停止Web服务
echo "[1/6] 停止并禁用Web服务"
systemctl stop shutdown-web 2>/dev/null || true
systemctl disable shutdown-web 2>/dev/null || true
pkill -f web.py 2>/dev/null || true

# 2. 删除服务文件
echo "[2/6] 删除系统服务配置"
rm -f "${SERVICE_FILE}"
systemctl daemon-reload

# 3. 删除程序文件
echo "[3/6] 删除程序目录与脚本"
rm -rf "${APP_DIR}"
rm -f "${SHUTDOWN_BIN}"

# 4. 清理定时任务
echo "[4/6] 清理定时任务"
(crontab -l 2>/dev/null || true) \
| grep -v "auto_shutdown_full.sh" \
| grep -v "update_cc.sh" \
| crontab -

# 5. 清理缓存、锁、日志
echo "[5/6] 清理缓存、锁文件、日志"
rm -f "${CACHE_FILE}" "${GLOBAL_LOCK}" "${TEMP_LOCK}"
rm -f "${LOG_DAILY}" "${LOG_WEEKLY}"

echo -e "\n✅ 卸载完成，所有组件已清理"