#!/bin/bash
set -e
if [[ $(id -u) -ne 0 ]]; then
    echo "必须root用户运行"
    exit 1
fi
echo "开始卸载自动关机系统..."
systemctl stop shutdown-web || true
systemctl disable shutdown-web || true
rm -f /etc/systemd/system/shutdown-web.service
systemctl daemon-reload

rm -rf /opt/shutdown-ctrl
rm -f /usr/local/bin/auto_shutdown_full.sh
rm -f /etc/logrotate.d/auto_shutdown

NEW_CRONTAB=$(crontab -l 2>/dev/null | grep -v "auto_shutdown_full.sh")
echo "$NEW_CRONTAB" | crontab -

rm -f /tmp/no_shutdown.lock /etc/no_shutdown_all.lock
if command -v ufw &>/dev/null && [ -f /opt/shutdown-ctrl/config.env ];then
    REAL_PORT=$(cat /opt/shutdown-ctrl/config.env | grep "^PORT=" | cut -d= -f2)
    ufw delete allow ${REAL_PORT}/tcp || true
fi
echo "卸载完成，关机日志文件未删除，手动删除执行：rm -rf /var/log/auto_shutdown.log*"