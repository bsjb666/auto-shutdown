#!/bin/bash
set -e

# ======================默认配置(回车直接使用)======================
DEFAULT_PORT=6788
DEFAULT_PASSWORD="admin123"
DEFAULT_CRON_TIME="01 00 * * *"   # 每天00:01
LOG_FILE="/var/log/auto_shutdown.log"
UPDATE_LOG="/var/log/auto_shutdown_update.log"
CONFIG_FILE="/opt/shutdown-ctrl/config.env"
LOCK_TMP="/tmp/no_shutdown.lock"
LOCK_GLB="/etc/no_shutdown_all.lock"
# =================================================================

if [[ $(id -u) -ne 0 ]]; then
    echo -e "\033[31m错误：必须使用root用户执行！\033[0m"
    exit 1
fi

echo -e "\033[34m======================================================\033[0m"
echo -e "\033[32m  自动关机系统 - 最终稳定版 (无开机自检)  \033[0m"
echo -e "\033[34m======================================================\033[0m"
echo -e "\033[36m请设置Web面板端口、管理密码和关机触发时间，直接回车使用默认值\033[0m"
echo ""

# 交互式输入端口
while true; do
    read -rp "请输入Web端口(默认${DEFAULT_PORT}，范围1-65535)：" INPUT_PORT
    if [[ -z "${INPUT_PORT}" ]]; then
        PORT=${DEFAULT_PORT}
        break
    fi
    if [[ "${INPUT_PORT}" =~ ^[0-9]+$ ]] && (( INPUT_PORT >= 1 && INPUT_PORT <= 65535 )); then
        PORT=${INPUT_PORT}
        break
    else
        echo -e "\033[31m端口非法，请输入1~65535纯数字\033[0m"
    fi
done
echo -e "\033[32m选定端口：${PORT}\033[0m"
echo ""

# 交互式输入密码
while true; do
    read -rsp "请输入管理密码(默认${DEFAULT_PASSWORD})：" INPUT_PWD
    echo ""
    if [[ -z "${INPUT_PWD}" ]]; then
        PASSWORD=${DEFAULT_PASSWORD}
        break
    fi
    read -rsp "再次确认密码：" CONFIRM_PWD
    echo ""
    if [[ "${INPUT_PWD}" == "${CONFIRM_PWD}" ]]; then
        PASSWORD=${INPUT_PWD}
        break
    else
        echo -e "\033[31m两次密码不一致，请重新输入\033[0m"
        echo ""
    fi
done
echo -e "\033[32m密码配置完成\033[0m"
echo ""

# 交互式输入cron时间
read -rp "请输入关机触发时间(cron表达式，默认 ${DEFAULT_CRON_TIME})：" INPUT_CRON
if [[ -z "${INPUT_CRON}" ]]; then
    CRON_TIME=${DEFAULT_CRON_TIME}
else
    # 简单校验：检查是否包含5个字段
    if [[ $(echo "${INPUT_CRON}" | awk '{print NF}') -eq 5 ]]; then
        CRON_TIME=${INPUT_CRON}
    else
        echo -e "\033[31m无效的cron表达式，使用默认值\033[0m"
        CRON_TIME=${DEFAULT_CRON_TIME}
    fi
fi
echo -e "\033[32m关机触发时间：${CRON_TIME}\033[0m"
echo -e "\033[34m======================================================\033[0m"
echo ""

# 1. 端口占用检测
echo -e "\033[36m[1/7] 检测端口占用...\033[0m"
if ss -tulpn | grep ":${PORT}" >/dev/null 2>&1;then
    echo -e "\033[31m端口${PORT}已被占用，请更换端口重新执行脚本\033[0m"
    exit 1
fi

# 2. 安装依赖
echo -e "\033[36m[2/7] 安装系统与Python依赖...\033[0m"
apt update -y
apt install -y python3 python3-pip
pip3 install --upgrade chinesecalendar --break-system-packages

# 3. 创建目录与配置文件
echo -e "\033[36m[3/7] 创建程序目录与配置文件...\033[0m"
mkdir -p /opt/shutdown-ctrl
printf "PORT=%s\nPASSWORD=%s\nLOCK_TMP=%s\nLOCK_GLB=%s\nLOG_FILE=%s\nUPDATE_LOG=%s\n" \
    "${PORT}" "${PASSWORD}" "${LOCK_TMP}" "${LOCK_GLB}" "${LOG_FILE}" "${UPDATE_LOG}" > ${CONFIG_FILE}
chmod 600 ${CONFIG_FILE}

# 4. 部署库自动更新脚本
echo -e "\033[36m[4/7] 部署库自动更新脚本...\033[0m"
cat > /opt/shutdown-ctrl/update_lib.sh << EOF
#!/bin/bash
echo "===== \$(date '+%Y-%m-%d %H:%M:%S') 开始更新 chinesecalendar =====" >> ${UPDATE_LOG}
pip3 install --upgrade chinesecalendar --break-system-packages >> ${UPDATE_LOG} 2>&1
if [ \$? -eq 0 ]; then
    echo "更新成功" >> ${UPDATE_LOG}
else
    echo "更新失败" >> ${UPDATE_LOG}
fi
echo "当前版本：" >> ${UPDATE_LOG}
python3 -c "import chinesecalendar; print(chinesecalendar.__version__)" >> ${UPDATE_LOG} 2>&1
echo "===== 更新结束 =====" >> ${UPDATE_LOG}
EOF
chmod +x /opt/shutdown-ctrl/update_lib.sh

# 5. 部署关机判断脚本（Python）
echo -e "\033[36m[5/7] 部署关机判断脚本...\033[0m"
cat > /usr/local/bin/shutdown_check.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import datetime
import subprocess

config = {}
with open("/opt/shutdown-ctrl/config.env", "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line and "=" in line:
            k, v = line.split("=", 1)
            config[k] = v

LOCK_TMP = config["LOCK_TMP"]
LOCK_GLB = config["LOCK_GLB"]
LOG_FILE = config["LOG_FILE"]

def log(msg):
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")

def main():
    if os.path.exists(LOCK_GLB):
        log("全局禁用锁存在，跳过关机")
        return
    if os.path.exists(LOCK_TMP):
        log("临时锁存在，清除锁，今晚不关机")
        os.remove(LOCK_TMP)
        return

    try:
        from chinese_calendar import is_workday
        today = datetime.date.today()
        is_work = is_workday(today)
    except ImportError:
        is_work = today.weekday() < 5
        log("chinesecalendar库未安装，使用周规则降级")

    log(f"今日是否为工作日: {is_work}")
    if is_work:
        log("执行关机")
        subprocess.Popen(["/sbin/shutdown", "-h", "now"])
    else:
        log("周末/节假日，跳过关机")

if __name__ == "__main__":
    main()
EOF
chmod +x /usr/local/bin/shutdown_check.py

# 6. 配置 cron 任务（仅用户指定的时间，无 @reboot）
echo -e "\033[36m[6/7] 配置定时任务...\033[0m"
# 清理旧任务
(crontab -l 2>/dev/null | grep -v -E "shutdown_check.py|update_lib.sh") | crontab - 2>/dev/null || true
# 添加关机判断任务
(crontab -l 2>/dev/null; echo "${CRON_TIME} /usr/bin/python3 /usr/local/bin/shutdown_check.py >> ${LOG_FILE} 2>&1") | crontab -
# 添加库更新任务（每年12月12日12:00）
(crontab -l 2>/dev/null; echo "0 12 12 12 * /opt/shutdown-ctrl/update_lib.sh") | crontab -
echo "定时任务已添加"

# 7. 部署 Web 面板（密码输入框版，支持特殊字符）
echo -e "\033[36m[7/7] 部署Web面板...\033[0m"
cat > /opt/shutdown-ctrl/web.py << 'EOF'
#!/usr/bin/env python3
import os, subprocess, urllib.parse
config = {}
with open("/opt/shutdown-ctrl/config.env","r",encoding="utf-8") as f:
    for line in f.readlines():
        line = line.strip()
        if line and "=" in line:
            k,v = line.split("=",1)
            config[k] = v
PORT = int(config["PORT"])
PASSWORD = config["PASSWORD"]
LOCK_TMP = config["LOCK_TMP"]
LOCK_GLB = config["LOCK_GLB"]
LOG_FILE = config["LOG_FILE"]
UPDATE_LOG = config["UPDATE_LOG"]

from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def resp(self, code, msg, ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(msg.encode("utf-8"))

    def get_post_data(self):
        length = int(self.headers.get("Content-Length",0))
        data = self.rfile.read(length).decode("utf-8")
        return dict(urllib.parse.parse_qsl(data, keep_blank_values=True))

    def do_GET(self):
        path = self.path.split('?')[0]
        if path == "/":
            html = '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>自动关机控制面板</title>
<style>
body {font-family: Arial, sans-serif; text-align:center; margin-top:80px; background:#f8f9fa;}
.box {background:#fff; padding:30px; border-radius:12px; box-shadow:0 2px 12px #00000014; max-width:400px; margin:0 auto;}
input {padding:10px; width:80%; margin:10px 0; border:1px solid #ccc; border-radius:4px; font-size:16px;}
button {padding:12px 22px; margin:8px; font-size:15px; border:none; border-radius:6px; cursor:pointer; transition:0.2s;}
.btn-primary {background:#1890ff; color:#fff;}
.btn-red {background:#ff4d4f; color:#fff;}
.btn-green {background:#52c41a; color:#fff;}
.btn-blue {background:#1890ff; color:#fff;}
.info {background:#f0f2f5; padding:15px; border-radius:8px; margin:15px 0; font-size:16px;}
.tip {color:#888; font-size:13px; margin-top:20px;}
#login-area, #control-area {display: none;}
#login-area {display: block;}
</style>
</head>
<body>
<div class="box" id="login-area">
<h2>自动关机控制面板</h2>
<p>请输入管理密码登录</p>
<input type="password" id="pwd-input" placeholder="密码" autofocus>
<br>
<button class="btn-primary" onclick="login()">登录</button>
<div id="login-error" style="color:red; margin-top:10px;"></div>
</div>

<div class="box" id="control-area" style="display:none;">
<h2>自动关机控制面板</h2>
<div class="info">
<p>当前状态：<span id="status">加载中...</span></p>
<p>今日类型：<span id="today_info">-</span></p>
</div>
<div>
<button class="btn-red" onclick="runCmd('tmp_off')">今晚不关机</button>
<button class="btn-green" onclick="runCmd('tmp_on')">恢复今晚自动关机</button>
<button class="btn-red" onclick="runCmd('glb_off')">永久关闭自动关机</button>
<button class="btn-green" onclick="runCmd('glb_on')">恢复全局自动关机</button>
<button class="btn-blue" onclick="getState()">刷新状态</button>
<button class="btn-blue" onclick="logout()">退出登录</button>
</div>
<div class="tip">密码保存在本地浏览器，退出登录后清除</div>
</div>

<script>
function showControl() {
    document.getElementById('login-area').style.display = 'none';
    document.getElementById('control-area').style.display = 'block';
    getState();
}

async function login() {
    const pwd = document.getElementById('pwd-input').value;
    if (!pwd) {
        document.getElementById('login-error').innerText = '请输入密码';
        return;
    }
    try {
        const params = new URLSearchParams();
        params.append('p', pwd);
        const res = await fetch('/status', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: params
        });
        if (res.status === 403) {
            document.getElementById('login-error').innerText = '密码错误，请重试';
            return;
        }
        if (res.ok) {
            localStorage.setItem('shutdown_pwd', pwd);
            showControl();
        } else {
            document.getElementById('login-error').innerText = '未知错误，请重试';
        }
    } catch(e) {
        document.getElementById('login-error').innerText = '网络请求失败';
    }
}

function logout() {
    localStorage.removeItem('shutdown_pwd');
    document.getElementById('login-area').style.display = 'block';
    document.getElementById('control-area').style.display = 'none';
    document.getElementById('pwd-input').value = '';
    document.getElementById('login-error').innerText = '';
}

function getPwd() {
    return localStorage.getItem('shutdown_pwd');
}

async function postReq(url, data) {
    const pwd = getPwd();
    if (!pwd) {
        alert('请重新登录');
        logout();
        return;
    }
    const params = new URLSearchParams();
    params.append('p', pwd);
    for (let k in data) params.append(k, data[k]);
    const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params
    });
    if (res.status === 403) {
        alert('密码过期或错误，请重新登录');
        logout();
        return;
    }
    return await res.text();
}

async function runCmd(cmd) {
    const ret = await postReq('/action', {cmd:cmd});
    if (ret !== undefined) {
        alert(ret);
        getState();
    }
}

async function getState() {
    try {
        const stat = await postReq('/status', {});
        const day = await postReq('/today', {});
        if (stat !== undefined && day !== undefined) {
            document.getElementById('status').innerText = stat;
            document.getElementById('today_info').innerText = day;
        }
    } catch(e) {
        alert('获取状态失败，请重试');
    }
}

window.onload = function() {
    const pwd = getPwd();
    if (pwd) {
        (async () => {
            try {
                const params = new URLSearchParams();
                params.append('p', pwd);
                const res = await fetch('/status', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: params
                });
                if (res.ok) {
                    showControl();
                } else {
                    logout();
                }
            } catch(e) {
                logout();
            }
        })();
    }
};
</script>
</body>
</html>'''
            self.resp(200, html, "text/html; charset=utf-8")
            return
        self.resp(404, "页面不存在")

    def do_POST(self):
        path = self.path
        params = self.get_post_data()
        input_pwd = params.get("p","")
        if input_pwd != PASSWORD:
            self.resp(403, "密码错误"); return

        if path == "/action":
            cmd = params.get("cmd","")
            msg = ""
            if cmd == "tmp_off":
                open(LOCK_TMP,'a').close()
                os.chmod(LOCK_TMP, 0o600)
                msg = "操作成功：今晚不执行自动关机"
            elif cmd == "tmp_on":
                try: os.unlink(LOCK_TMP); msg = "操作成功：今晚恢复自动关机"
                except: msg = "无需操作，临时锁不存在"
            elif cmd == "glb_off":
                open(LOCK_GLB,'a').close()
                os.chmod(LOCK_GLB, 0o600)
                msg = "操作成功：永久关闭全部自动关机"
            elif cmd == "glb_on":
                try: os.unlink(LOCK_GLB); msg = "操作成功：恢复全局自动关机"
                except: msg = "无需操作，全局锁不存在"
            else: msg = "无效操作指令"
            self.resp(200, msg)
            return

        if path == "/status":
            if os.path.exists(LOCK_GLB):
                stat = "❌ 永久禁用自动关机"
            elif os.path.exists(LOCK_TMP):
                stat = "⏸️ 临时跳过今晚关机"
            else:
                stat = "✅ 自动关机正常启用"
            self.resp(200, stat)
            return

        if path == "/today":
            try:
                res = subprocess.run(
                    ["python3","-c",
                     "import datetime; from chinese_calendar import is_workday; print('工作日' if is_workday(datetime.date.today()) else '周末/法定节假日')"],
                    capture_output=True, text=True, timeout=10
                )
                day_info = res.stdout.strip()
            except Exception as e:
                day_info = "日历库读取异常"
            self.resp(200, day_info)
            return
        self.resp(404, "接口不存在")

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()
EOF
chmod +x /opt/shutdown-ctrl/web.py

# 配置 systemd 服务
cat > /etc/systemd/system/shutdown-web.service << EOF
[Unit]
Description=Shutdown Web Control
After=network.target
[Service]
ExecStart=/usr/bin/python3 /opt/shutdown-ctrl/web.py
Restart=on-failure
RestartSec=5
User=root
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable shutdown-web
systemctl start shutdown-web

# 防火墙放行
if command -v ufw &> /dev/null; then
    ufw allow ${PORT}/tcp comment "shutdown web"
    ufw reload 2>/dev/null || true
fi

# 输出信息（修正后的描述）
echo -e "\033[34m======================================================\033[0m"
echo -e "\033[32m✅ 全部组件安装完成！\033[0m"
echo -e "\033[36m访问地址：\033[0m"
for ip in $(hostname -I); do
    echo "  http://${ip}:${PORT}"
done
echo -e "\033[36m管理密码：${PASSWORD}\033[0m"
echo -e "\033[36m定时关机：每日 ${CRON_TIME}\033[0m"
echo -e "\033[36m库更新：每年12月12日12:00 自动更新 chinesecalendar\033[0m"
echo -e "\033[36m运行日志：${LOG_FILE}\033[0m"
echo -e "\033[36m更新日志：${UPDATE_LOG}\033[0m"
echo -e "\033[36m服务命令：\033[0m"
echo "  systemctl status shutdown-web  查看面板状态"
echo "  systemctl restart shutdown-web 重启面板"
echo "  tail -f ${LOG_FILE} 实时查看关机日志"
echo -e "\033[34m======================================================\033[0m"