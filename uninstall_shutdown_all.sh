#!/bin/bash
set -e

if [[ $(id -u) -ne 0 ]]; then
    echo "必须root用户运行"
    exit 1
fi

echo "开始卸载自动关机系统..."

PORT=6788
if [ -f "/opt/shutdown-ctrl/config.env" ]; then
    source /opt/shutdown-ctrl/config.env
fi

systemctl stop shutdown-web 2>/dev/null || true
systemctl disable shutdown-web 2>/dev/null || true
rm -f /etc/systemd/system/shutdown-web.service
systemctl daemon-reload

rm -rf /opt/shutdown-ctrl
rm -f /usr/local/bin/shutdown_check.py
rm -f /usr/local/bin/auto_shutdown_full.sh
rm -f /etc/logrotate.d/auto_shutdown

(crontab -l 2>/dev/null | grep -v -E "shutdown_check.py|update_lib.sh") | crontab - 2>/dev/null || true

rm -f /tmp/no_shutdown.lock /etc/no_shutdown_all.lock

if command -v ufw &>/dev/null; then
    ufw delete allow ${PORT}/tcp 2>/dev/null || true
fi

echo "卸载完成。日志文件 /var/log/auto_shutdown*.log 未删除，如需清理：rm -f /var/log/auto_shutdown*.log"