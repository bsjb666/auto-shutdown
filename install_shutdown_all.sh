#!/bin/bash
set -euo pipefail

# ==================== 全局配置 ====================
DEFAULT_PORT="6788"
DEFAULT_PWD="Admin@123456"
GLOBAL_LOCK="/etc/no_shutdown_all.lock"
TEMP_LOCK="/tmp/no_shutdown.lock"
CACHE_FILE="/var/cache/holiday_flat.json"
APP_DIR="/opt/shutdown-ctrl"
WEB_SCRIPT="${APP_DIR}/web.py"
SHUTDOWN_BIN="/usr/local/bin/auto_shutdown_full.sh"
UPD_SCRIPT="${APP_DIR}/update_cc.sh"
UPD_LOG="${APP_DIR}/update_cc.log"
LOG_DAILY="/var/log/auto_shutdown.log"
LOG_WEEKLY="/var/log/auto_shutdown_refresh.log"
SERVICE_FILE="/etc/systemd/system/shutdown-web.service"

# 权限校验
if [[ $(id -u) -ne 0 ]]; then
    echo "请使用 root / sudo 执行本脚本"
    exit 1
fi

echo "============================================="
echo "        自动关机系统 一键完整安装            "
echo "  架构：API优先 + 本地库降级 + 年度自动升级  "
echo "  版本：v2.0 (修复缓存解析Bug)              "
echo "============================================="

# 交互配置端口、密码
read -p "请输入面板监听端口(默认 ${DEFAULT_PORT}): " LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-${DEFAULT_PORT}}

read -p "请输入面板访问密码(默认 ${DEFAULT_PWD}): " ACCESS_PWD
ACCESS_PWD=${ACCESS_PWD:-${DEFAULT_PWD}}

# 1. 创建目录
echo -e "\n[1/9] 创建程序目录"
mkdir -p "${APP_DIR}"

# 2. 安装系统依赖 + 本地节假日库（兼容 PEP 668）
echo "[2/9] 安装系统依赖 & 节假日组件"
apt update -y
apt install -y curl jq python3 python3-pip python3-full
# 绕过系统环境保护安装包
pip3 install chinesecalendar --break-system-packages

# 3. 编写 chinesecalendar 自动升级脚本（每年12月执行，加兼容参数）
echo "[3/9] 部署库自动升级脚本"
cat > "${UPD_SCRIPT}" <<'EOF'
#!/bin/bash
LOG_FILE="/opt/shutdown-ctrl/update_cc.log"
echo "===== $(date '+%Y-%m-%d %H:%M:%S') 执行自动升级 =====" >> ${LOG_FILE}
python3 -m pip install -U chinesecalendar --break-system-packages >> ${LOG_FILE} 2>&1
python3 -c "import chinese_calendar; print('当前库版本:', chinese_calendar.__version__)" >> ${LOG_FILE} 2>&1
echo "===== 升级完成 =====" >> ${LOG_FILE}
echo "" >> ${LOG_FILE}
EOF
chmod +x "${UPD_SCRIPT}"

# 4. 编写核心定时关机脚本（修复版 - API解析使用jq直接生成JSON）
echo "[4/9] 部署定时关机核心脚本（修复版）"
cat > "${SHUTDOWN_BIN}" <<'EOF'
#!/bin/bash
set -euo pipefail

ONLY_REFRESH="false"
if [[ $# -ge 1 && "$1" == "--refresh" ]]; then
    ONLY_REFRESH="true"
fi

# 全局路径
GLOBAL_LOCK="/etc/no_shutdown_all.lock"
TEMP_LOCK="/tmp/no_shutdown.lock"
CACHE_FILE="/var/cache/holiday_flat.json"
API_TIMEOUT=20
MAX_RETRY=2
CUR_YEAR=$(date +%Y)
# chinesecalendar 基准支持年份
CC_START_YEAR=2004
CC_END_YEAR=2026

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

init_empty_cache() {
    echo "{}" > "${CACHE_FILE}"
    chmod 644 "${CACHE_FILE}"
}

http_get() {
    local url="$1"
    local retry=0
    local res=""
    while (( retry < MAX_RETRY )); do
        res=$(curl -s --max-time "${API_TIMEOUT}" "${url}")
        if [[ "${res}" =~ ^\{ ]]; then
            echo "${res}"
            return 0
        fi
        log_info "API请求失败，重试 ${retry}/${MAX_RETRY}"
        ((retry++))
        sleep 1
    done
    return 1
}

# 方案1：优先在线API bitefu（修复版 - 使用jq直接生成完整JSON）
refresh_by_api() {
    log_info "尝试从在线API获取节假日数据..."
    local url="https://tool.bitefu.net/jiari/?d=${CUR_YEAR}&json=1"
    local raw
    raw=$(http_get "${url}") || return 1

    log_info "API请求成功，开始解析数据..."
    
    # 使用jq直接生成完整的JSON缓存，避免子shell变量作用域问题
    # API返回格式：{"2026": {"0101": 1, "0102": 2, ...}} 
    # 1=节假日, 2=工作日调休(当作工作日), 其他=节假日
    if echo "${raw}" | jq -e --arg y "${CUR_YEAR}" '.[$y]' > /dev/null 2>&1; then
        echo "${raw}" | jq --arg y "${CUR_YEAR}" '
            .[$y] // {} 
            | to_entries 
            | map({
                key: ($y + "-" + (.key[0:2] + "-" + .key[2:4])),
                value: (.value == "1" or .value == "3" or .value == "4")
            })
            | from_entries
        ' > "${CACHE_FILE}"
        
        chmod 644 "${CACHE_FILE}"
        
        # 验证缓存是否生成成功
        local count=$(jq '. | length' "${CACHE_FILE}" 2>/dev/null || echo "0")
        if [[ "${count}" -gt 0 ]]; then
            log_info "✅ API解析成功，缓存了 ${count} 天的数据"
            return 0
        else
            log_info "⚠️  API解析结果为空，尝试降级"
            return 1
        fi
    else
        log_info "⚠️  API返回数据格式异常"
        return 1
    fi
}

# 方案2：降级到本地 chinesecalendar 库
refresh_by_local_lib() {
    log_info "切换至本地 chinesecalendar 节假日库..."
    init_empty_cache
    python3 - <<PYEOF
import datetime
from chinese_calendar import is_workday
import json
cache = {}
year = int("${CUR_YEAR}")
start = datetime.date(year, 1, 1)
end = datetime.date(year, 12, 31)
delta = datetime.timedelta(days=1)
current = start
while current <= end:
    d_str = current.strftime("%Y-%m-%d")
    cache[d_str] = is_workday(current)
    current += delta
with open("${CACHE_FILE}", "w", encoding="utf-8") as f:
    json.dump(cache, f)
PYEOF
    log_info "✅ 本地库生成缓存完成"
    return 0
}

# 方案3：年份超限兜底：周一至周五为工作日
refresh_by_week() {
    log_info "年份超出本地库支持范围，启用周规则兜底(周一~周五=工作日)..."
    init_empty_cache
    python3 - <<PYEOF
import datetime
import json
cache = {}
year = int("${CUR_YEAR}")
start = datetime.date(year, 1, 1)
end = datetime.date(year, 12, 31)
delta = datetime.timedelta(days=1)
current = start
while current <= end:
    d_str = current.strftime("%Y-%m-%d")
    # weekday() 0-4 工作日，5-6 周末
    cache[d_str] = current.weekday() < 5
    current += delta
with open("${CACHE_FILE}", "w", encoding="utf-8") as f:
    json.dump(cache, f)
PYEOF
    log_info "✅ 周规则兜底缓存完成"
    return 0
}

# ==================== 执行刷新逻辑 ====================
log_info "==================== 刷新节假日缓存 ===================="
log_info "当前年份：${CUR_YEAR}"

REFRESH_SUCCESS=false

if refresh_by_api; then
    REFRESH_SUCCESS=true
    log_info "✅ 在线API 请求成功"
elif [[ ${CUR_YEAR} -ge ${CC_START_YEAR} && ${CUR_YEAR} -le ${CC_END_YEAR} ]]; then
    log_info "❌ API失败，使用本地节假日库"
    if refresh_by_local_lib; then
        REFRESH_SUCCESS=true
    fi
else
    log_info "⚠️  年份超出本地库范围，启用周规则兜底"
    if refresh_by_week; then
        REFRESH_SUCCESS=true
    fi
fi

# 验证缓存有效性
if [[ "${REFRESH_SUCCESS}" == "true" ]]; then
    CACHE_COUNT=$(jq '. | length' "${CACHE_FILE}" 2>/dev/null || echo "0")
    if [[ "${CACHE_COUNT}" -eq 0 ]]; then
        log_info "⚠️  缓存生成失败（空文件），使用紧急兜底"
        refresh_by_week
        REFRESH_SUCCESS=true
    fi
fi

log_info "==== 缓存内容预览（前10条） ===="
jq 'to_entries | .[:10] | from_entries' "${CACHE_FILE}" 2>/dev/null || echo "缓存读取失败"

if [[ "${ONLY_REFRESH}" == "true" ]]; then
    log_info "缓存刷新完成，不执行关机（--refresh模式）"
    exit 0
fi

# ==================== 关机判定逻辑 ====================
log_info "==================== 关机判定 ===================="
if [ -f "${GLOBAL_LOCK}" ]; then
    log_info "🔒 全局禁用锁存在，不执行关机"
    exit 0
fi
if [ -f "${TEMP_LOCK}" ]; then
    log_info "🔒 临时禁用锁存在，清理临时锁，本次不关机"
    rm -f "${TEMP_LOCK}"
    exit 0
fi

TODAY=$(date +%Y-%m-%d)
log_info "当前日期：${TODAY}"

# 从缓存获取今日是否工作日，若缓存不存在或读取失败则默认为true
IS_WORK=$(jq -r --arg t "${TODAY}" '.[$t] // true' "${CACHE_FILE}" 2>/dev/null || echo "true")
log_info "当日是否工作日：${IS_WORK}"

if [[ "${IS_WORK}" == "true" ]]; then
    log_info "✅ 执行自动关机"
    /sbin/shutdown -h now
else
    log_info "⏸️  节假日/周末，跳过关机"
    exit 0
fi
EOF
chmod +x "${SHUTDOWN_BIN}"

# 5. 部署Python Web控制面板（精简无歧义版 + 缓存状态显示）
echo "[5/9] 部署Web控制面板（精简无歧义版）"
cat > "${WEB_SCRIPT}" <<EOF
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import os
import json
import datetime

PORT = ${LISTEN_PORT}
PWD_KEY = "${ACCESS_PWD}"
LOCK_TMP = "${TEMP_LOCK}"
LOCK_GLB = "${GLOBAL_LOCK}"
CACHE_FILE = "${CACHE_FILE}"

class Handler(BaseHTTPRequestHandler):
    def _html(self, content):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(content.encode("utf-8"))

    def _text(self, content):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(content.encode("utf-8"))

    def _403(self):
        self.send_response(403)
        self.end_headers()
        self.wfile.write(b"Password Error")

    def do_GET(self):
        path = self.path
        qs = {}
        if "?" in path:
            pth, q = path.split("?", 1)
            for kv in q.split("&"):
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    qs[k] = v
            path = pth

        pwd = qs.get("p", "")

        if path == "/":
            html = """
<html>
<head><meta charset="utf-8"></head>
<body style="text-align:center;margin-top:100px;font-family:微软雅黑;">
<h2>自动关机控制中心</h2>
<input type="password" id="pw" placeholder="请输入密码">
<br><br>
<button onclick="location='/main?p='+document.getElementById('pw').value" style="padding:10px 20px;">登录</button>
</body>
</html>
            """
            self._html(html)
            return

        if path == "/main":
            if pwd != PWD_KEY:
                self._403()
                return
            
            # 读取锁文件状态
            has_tmp_lock = os.path.exists(LOCK_TMP)
            has_glb_lock = os.path.exists(LOCK_GLB)

            # 读取缓存信息
            today = datetime.date.today()
            today_str = today.strftime("%Y-%m-%d")
            is_workday = True
            cache_days = 0
            cache_year = "未知"
            try:
                with open(CACHE_FILE, "r", encoding="utf-8") as f:
                    cache = json.load(f)
                cache_days = len(cache)
                is_workday = cache.get(today_str, True)
                if cache_days > 0:
                    # 尝试提取年份
                    first_key = next(iter(cache.keys()))
                    if len(first_key) >= 4:
                        cache_year = first_key[:4]
            except Exception:
                pass

            # 计算下次关机日期
            next_shutdown_text = "无法获取，请刷新缓存"
            try:
                delta = datetime.timedelta(days=1)
                next_day = today + delta
                for _ in range(365):
                    nd_str = next_day.strftime("%Y-%m-%d")
                    nd_work = True
                    try:
                        nd_work = cache.get(nd_str, True)
                    except:
                        pass
                    if nd_work:
                        next_shutdown_text = f"{next_day.strftime('%Y-%m-%d')} 凌晨00:01"
                        break
                    next_day += delta
            except:
                pass

            # 状态说明文案
            if has_glb_lock:
                status_text = "❌ 自动关机已永久关闭（全局禁用）"
                next_shutdown_text = "永久不执行关机"
            elif has_tmp_lock:
                status_text = "⏸️ 临时设置：今晚不关机，明晚自动恢复"
            else:
                status_text = "✅ 自动关机已正常开启"

            html = f"""
<html>
<head>
<meta charset="utf-8">
<title>自动关机控制中心</title>
<style>
    body {{ font-family: "微软雅黑", Arial; text-align: center; margin-top: 80px; line-height: 1.8; }}
    .status-box {{ background: #f5f5f5; padding: 20px; margin: 20px auto; width: 60%; border-radius: 8px; }}
    .btn-group {{ margin-top: 30px; }}
    button {{ padding: 10px 20px; margin: 10px; font-size: 16px; cursor: pointer; border: none; border-radius: 4px; }}
    .btn-red {{ background: #ff4d4f; color: white; }}
    .btn-green {{ background: #52c41a; color: white; }}
    .btn-blue {{ background: #1890ff; color: white; }}
    .note {{ font-size: 14px; color: #666; margin-top: 20px; text-align: left; width: 60%; margin-left: auto; margin-right: auto; }}
    .cache-info {{ background: #e6f7ff; padding: 10px; margin: 10px auto; width: 60%; border-radius: 4px; border: 1px solid #91d5ff; }}
</style>
</head>
<body>
    <h1>自动关机控制中心</h1>

    <div class="status-box">
        <h3>当前系统状态</h3>
        <p>{status_text}</p>
        <p>⏰ 下次关机时间：{next_shutdown_text}</p>
    </div>

    <div class="cache-info">
        <p>📅 缓存状态：{cache_days} 天数据（{cache_year}年）</p>
        <p>📌 今天({today_str})：{"工作日" if is_workday else "节假日/周末"}</p>
        <p><a href="/refresh_cache?p={pwd}" style="color: #1890ff;">点击手动刷新缓存</a></p>
    </div>

    <div class="btn-group">
        <h4>今晚关机控制（单次生效，仅影响今天）</h4>
        <button class="btn-red" onclick="location='/tmp_off?p={pwd}'">今晚不关机（仅今天有效）</button>
        <button class="btn-green" onclick="location='/tmp_on?p={pwd}'">恢复今晚关机（取消临时设置）</button>

        <br><br>
        <h4>全局关机控制（永久生效，所有日期都受影响）</h4>
        <button class="btn-red" onclick="location='/glb_off?p={pwd}'">永久关闭自动关机（所有日期都不关机）</button>
        <button class="btn-green" onclick="location='/glb_on?p={pwd}'">恢复自动关机（按工作日/节假日规则执行）</button>
    </div>

    <div class="note">
        <h4>使用说明：</h4>
        <p>1. 系统会自动识别法定节假日/周末，这些日期不会关机；工作日凌晨00:01会自动关机。</p>
        <p>2. 「今晚不关机」只影响当天，第二天会自动恢复正常规则，无需手动恢复。</p>
        <p>3. 「永久关闭自动关机」会一直不关机，需要点击「恢复自动关机」才能重新启用。</p>
        <p>4. 节假日数据优先从网络接口获取，网络异常时会自动使用本地库兜底。</p>
        <p>5. 缓存数据包含全年日期，如果发现日期判断错误，可点击「手动刷新缓存」。</p>
    </div>
</body>
</html>
            """
            self._html(html)
            return

        if path == "/refresh_cache":
            if pwd != PWD_KEY:
                self._403()
                return
            # 调用刷新脚本
            import subprocess
            try:
                result = subprocess.run(
                    ["/usr/local/bin/auto_shutdown_full.sh", "--refresh"],
                    capture_output=True,
                    text=True,
                    timeout=60
                )
                self._text(f"缓存刷新完成\n\nSTDOUT:\n{result.stdout}\n\nSTDERR:\n{result.stderr}")
            except Exception as e:
                self._text(f"缓存刷新失败: {str(e)}")
            return

        if path == "/tmp_off":
            if pwd != PWD_KEY:
                self._403()
                return
            open(LOCK_TMP, "a").close()
            self._text("操作成功：今晚不执行自动关机，明天自动恢复")
            return

        if path == "/tmp_on":
            if pwd != PWD_KEY:
                self._403()
                return
            try:
                os.unlink(LOCK_TMP)
            except OSError:
                pass
            self._text("操作成功：今晚按正常规则执行关机")
            return

        if path == "/glb_off":
            if pwd != PWD_KEY:
                self._403()
                return
            open(LOCK_GLB, "a").close()
            self._text("操作成功：永久关闭自动关机，所有日期都不执行")
            return

        if path == "/glb_on":
            if pwd != PWD_KEY:
                self._403()
                return
            try:
                os.unlink(LOCK_GLB)
            except OSError:
                pass
            self._text("操作成功：恢复自动关机，按工作日/节假日规则执行")
            return

        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"Not Found")

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()
EOF
chmod +x "${WEB_SCRIPT}"

# 6. Web系统服务
echo "[6/9] 配置Web自启服务"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Auto Shutdown Web Control
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${WEB_SCRIPT}
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# 7. 配置全部定时任务（修复版 - 先清理再添加）
echo "[7/9] 配置定时任务（关机+缓存刷新+年度自动升级）"
CRON_DAILY="01 00 * * * ${SHUTDOWN_BIN} >> ${LOG_DAILY} 2>&1"
CRON_WEEKLY="00 12 * * 1 ${SHUTDOWN_BIN} --refresh >> ${LOG_WEEKLY} 2>&1"
CRON_UPD1="00 03 1 12 * ${UPD_SCRIPT}"
CRON_UPD2="00 03 15 12 * ${UPD_SCRIPT}"

# 先清理所有相关任务
(crontab -l 2>/dev/null || true) \
| grep -v "auto_shutdown_full.sh" \
| grep -v "update_cc.sh" \
| crontab - 2>/dev/null || true

# 再添加新任务（使用追加方式避免覆盖）
(crontab -l 2>/dev/null || true; echo "${CRON_DAILY}") | crontab -
(crontab -l 2>/dev/null || true; echo "${CRON_WEEKLY}") | crontab -
(crontab -l 2>/dev/null || true; echo "${CRON_UPD1}") | crontab -
(crontab -l 2>/dev/null || true; echo "${CRON_UPD2}") | crontab -

echo "定时任务配置完成"
crontab -l | grep -E "auto_shutdown|update_cc" || echo "⚠️ 未找到定时任务"

# 8. 初始化缓存 & 放行防火墙
echo "[8/9] 初始化节假日缓存 & 放行端口"

# 初始化空缓存
echo "{}" > "${CACHE_FILE}"
chmod 644 "${CACHE_FILE}"

# 执行首次缓存刷新
echo "执行首次缓存刷新..."
if "${SHUTDOWN_BIN}" --refresh; then
    echo "✅ 缓存初始化成功"
else
    echo "⚠️ 缓存初始化失败（API和本地库都不可用），使用周规则兜底"
    # 手动执行周规则兜底
    python3 - <<PYEOF
import datetime
import json
cache = {}
year = datetime.date.today().year
start = datetime.date(year, 1, 1)
end = datetime.date(year, 12, 31)
delta = datetime.timedelta(days=1)
current = start
while current <= end:
    d_str = current.strftime("%Y-%m-%d")
    cache[d_str] = current.weekday() < 5
    current += delta
with open("${CACHE_FILE}", "w", encoding="utf-8") as f:
    json.dump(cache, f)
PYEOF
    echo "✅ 周规则兜底缓存生成完成"
fi

# 放行防火墙
ufw allow ${LISTEN_PORT}/tcp 2>/dev/null || true
ufw reload 2>/dev/null || true

# 9. 启动Web服务
echo "[9/9] 启动Web控制面板"
systemctl daemon-reload
systemctl start shutdown-web
systemctl enable shutdown-web

# 验证服务状态
if systemctl is-active --quiet shutdown-web; then
    echo "✅ Web服务运行正常"
else
    echo "⚠️ Web服务启动失败，请检查日志：journalctl -u shutdown-web -n 50"
fi

# 完成提示
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo -e "\n============================================="
echo "✅ 全部安装完成！"
echo "🌐 访问地址：http://${LOCAL_IP}:${LISTEN_PORT}"
echo "🔑 登录密码：${ACCESS_PWD}"
echo ""
echo "⏰ 定时规则："
echo "   1. 每日 00:01 自动判断并执行关机"
echo "   2. 每周一 12:00 刷新节假日缓存"
echo "   3. 每年12月1日、15日 03:00 自动升级节假日库（双次防失败）"
echo ""
echo "🔧 优先级架构："
echo "   在线API(bitefu) → 本地chinesecalendar库 → 周规则兜底"
echo ""
echo "📊 验证缓存："
echo "   cat ${CACHE_FILE} | jq '. | length'  # 查看缓存天数"
echo "   cat ${CACHE_FILE} | jq '.\"$(date +%Y-%m-%d)\"'  # 查看今天是否工作日"
echo ""
echo "🐛 如果遇到问题，查看日志："
echo "   tail -f ${LOG_DAILY}"
echo "   tail -f ${LOG_WEEKLY}"
echo "============================================="