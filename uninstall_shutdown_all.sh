#!/bin/bash
set -euo pipefail

# ==================== 全局配置 ====================
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
echo "        版本：v2.0 (彻底清理版)              "
echo "============================================="

# 确认卸载
read -p "确认要卸载自动关机系统吗？(y/N): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    echo "卸载已取消"
    exit 0
fi

echo ""
echo "开始卸载..."

# 1. 停止并禁用Web服务
echo "[1/7] 停止并禁用Web服务"
systemctl stop shutdown-web 2>/dev/null || echo "  ⚠️ 服务未运行或已停止"
systemctl disable shutdown-web 2>/dev/null || echo "  ⚠️ 服务未启用或已禁用"
pkill -f "web.py" 2>/dev/null || echo "  ⚠️ 未找到运行中的web.py进程"

# 2. 删除服务文件
echo "[2/7] 删除系统服务配置"
rm -f "${SERVICE_FILE}"
systemctl daemon-reload
echo "  ✅ 服务文件已删除"

# 3. 删除程序文件
echo "[3/7] 删除程序目录与脚本"
if [ -d "${APP_DIR}" ]; then
    rm -rf "${APP_DIR}"
    echo "  ✅ 程序目录已删除: ${APP_DIR}"
else
    echo "  ℹ️  程序目录不存在: ${APP_DIR}"
fi

if [ -f "${SHUTDOWN_BIN}" ]; then
    rm -f "${SHUTDOWN_BIN}"
    echo "  ✅ 主脚本已删除: ${SHUTDOWN_BIN}"
else
    echo "  ℹ️  主脚本不存在: ${SHUTDOWN_BIN}"
fi

# 4. 清理定时任务（彻底清理）
echo "[4/7] 清理定时任务"
# 先备份当前crontab
BACKUP_CRON="/tmp/crontab_backup_$(date +%Y%m%d_%H%M%S).txt"
crontab -l 2>/dev/null > "${BACKUP_CRON}" || echo "  ℹ️  当前无crontab"
echo "  ℹ️  已备份当前crontab到: ${BACKUP_CRON}"

# 清理所有相关任务
(crontab -l 2>/dev/null || true) \
| grep -v "auto_shutdown_full.sh" \
| grep -v "update_cc.sh" \
| grep -v "shutdown-ctrl" \
| crontab - 2>/dev/null || true

# 验证清理结果
REMAINING=$(crontab -l 2>/dev/null | grep -E "auto_shutdown|update_cc|shutdown-ctrl" || true)
if [ -z "${REMAINING}" ]; then
    echo "  ✅ 定时任务已全部清理"
else
    echo "  ⚠️ 仍有残留定时任务:"
    echo "${REMAINING}"
    echo "  请手动检查: crontab -l"
fi

# 5. 清理缓存、锁、日志
echo "[5/7] 清理缓存、锁文件、日志"
FILES_TO_CLEAN=(
    "${CACHE_FILE}"
    "${GLOBAL_LOCK}"
    "${TEMP_LOCK}"
    "${LOG_DAILY}"
    "${LOG_WEEKLY}"
    "/tmp/no_shutdown.lock"  # 额外的临时锁路径
    "/tmp/_tmp_cache.tmp"    # 临时缓存文件
)

for file in "${FILES_TO_CLEAN[@]}"; do
    if [ -f "${file}" ]; then
        rm -f "${file}"
        echo "  ✅ 已删除: ${file}"
    else
        echo "  ℹ️  文件不存在: ${file}"
    fi
done

# 6. 卸载Python包（增加确认和重试）
echo "[6/7] 卸载Python节假日库"
if pip3 show chinesecalendar >/dev/null 2>&1; then
    echo "  发现已安装的 chinesecalendar 包"
    read -p "  是否卸载 chinesecalendar？(y/N): " UNINSTALL_PKG
    if [[ "${UNINSTALL_PKG}" =~ ^[Yy]$ ]]; then
        if pip3 uninstall -y chinesecalendar --break-system-packages 2>/dev/null; then
            echo "  ✅ chinesecalendar 已卸载"
        else
            echo "  ⚠️  常规卸载失败，尝试强制卸载..."
            # 尝试不带 --break-system-packages 参数
            if pip3 uninstall -y chinesecalendar 2>/dev/null; then
                echo "  ✅ chinesecalendar 已卸载"
            else
                echo "  ⚠️  卸载失败，请手动执行:"
                echo "     pip3 uninstall chinesecalendar --break-system-packages"
            fi
        fi
    else
        echo "  ℹ️  跳过卸载 chinesecalendar"
    fi
else
    echo "  ℹ️  chinesecalendar 未安装"
fi

# 7. 防火墙端口清理（提示）
echo "[7/7] 防火墙端口清理（手动操作）"
CURRENT_PORT=$(grep -oP 'PORT = \K\d+' /opt/shutdown-ctrl/web.py 2>/dev/null || echo "未知")
if [[ "${CURRENT_PORT}" != "未知" ]]; then
    echo "  ℹ️  检测到Web面板端口: ${CURRENT_PORT}"
    echo "  如需删除防火墙规则，请执行:"
    echo "    ufw delete allow ${CURRENT_PORT}/tcp"
else
    echo "  ℹ️  未检测到端口配置，请手动检查防火墙规则"
fi

echo ""
echo "============================================="
echo "✅ 卸载完成！"
echo ""
echo "📋 清理摘要："
echo "  ✅ systemd服务已删除"
echo "  ✅ 程序文件已删除"
echo "  ✅ 定时任务已清理"
echo "  ✅ 缓存/锁/日志已清理"
echo "  ⚠️  请手动处理防火墙规则（如需要）"
echo "  ℹ️  crontab备份保存在: ${BACKUP_CRON}"
echo ""
echo "🔍 验证清理结果："
echo "  systemctl status shutdown-web  # 应该显示未找到"
echo "  crontab -l                     # 应该没有相关条目"
echo "  ls /opt/shutdown-ctrl          # 应该不存在"
echo "============================================="  .