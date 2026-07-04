#!/bin/bash
set -e

# ======================默认配置(回车直接使用)======================
DEFAULT_PORT=6788
DEFAULT_PASSWORD="admin123"
CRON_TIME="01 00 * * *"
LOG_FILE="/var/log/auto_shutdown.log"
CONFIG_FILE="/opt/shutdown-ctrl/config.env"
LOCK_TMP="/tmp/no_shutdown.lock"
LOCK_GLB="/etc/no_shutdown_all.lock"
# =================================================================

if [[ $(id -u) -ne 0 ]]; then
    echo -e "\033[31m错误：必须使用root用户执行！\033[0m"
    exit 1
fi

echo -e "\033[34m======================================================\033[0m"
echo -e "\033[32m  自动关机系统 - 新增下次关机日期显示版  \033[0m"
echo -e "\033[34m======================================================\033[0m"
echo -e "\033[36m请设置Web面板端口与管理密码，支持数字/字母/!@#$%^&*等特殊符号，直接回车使用默认值\033[0m"
echo ""

# 交互式输入端口，合法性校验
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

# 交互式输入密码，隐藏输入+二次确认，完整支持特殊符号
while true; do
    read -rsp "请输入管理密码(支持!@#$%^&*等符号，默认${DEFAULT_PASSWORD})：" INPUT_PWD
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
echo -e "\033[34m======================================================\033[0m"
echo ""

# 1. 端口占用检测
echo -e "\033[36m[1/9] 检测端口占用...\033[0m"
if ss -tulpn | grep ":${PORT}" >/dev/null 2>&1;then
    echo -e "\033[31m端口${PORT}已被占用，请更换端口重新执行脚本\033[0m"
    exit 1
fi

# 2. 安装依赖
echo -e "\033[36m[2/9] 安装系统与Python依赖...\033[0m"
apt update -y
apt install -y python3 python3-pip iproute2
pip3 install --upgrade chinesecalendar --break-system-packages

# 3. 生成统一配置文件，完整保留原始密码字符，无多余换行
echo -e "\033[36m[3/9] 创建程序目录与配置文件...\033[0m"
mkdir -p /opt/shutdown-ctrl
rm -f ${CONFIG_FILE}
cat > ${CONFIG_FILE} <<EOF
PORT=${PORT}
PASSWORD=${PASSWORD}
LOCK_TMP=${LOCK_TMP}
LOCK_GLB=${LOCK_GLB}
LOG_FILE=${LOG_FILE}
EOF
chmod 600 ${CONFIG_FILE}

# 4. 定时关机执行脚本
echo -e "\033[36m[4/9] 部署自动关机定时脚本...\033[0m"
cat > /usr/local/bin/auto_shutdown_full.sh << 'EOF'
#!/bin/bash
set -e
source /opt/shutdown-ctrl/config.env
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

fix_lock_perm(){
    [ -f "$1" ] && chmod 600 "$1"
}

fix_lock_perm "${LOCK_GLB}"
if [ -f "${LOCK_GLB}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 全局禁用锁存在，跳过关机" >> ${LOG_FILE}
    exit 0
fi

fix_lock_perm "${LOCK_TMP}"
if [ -f "${LOCK_TMP}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 临时锁存在，清除锁，今晚不关机" >> ${LOG_FILE}
    rm -f "${LOCK_TMP}"
    exit 0
fi

IS_WORK=$(python3 - <<PYEOF
import datetime, traceback
try:
    from chinese_calendar import is_workday
    print("True" if is_workday(datetime.date.today()) else "False")
except Exception as e:
    print("ERR")
    with open("/var/log/auto_shutdown.log", "a", encoding="utf-8") as f:
        f.write(f"[{datetime.datetime.now()}] 日历库异常：{traceback.format_exc()}\n")
PYEOF
)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 当日工作日标记: ${IS_WORK}" >> ${LOG_FILE}
if [ "${IS_WORK}" = "ERR" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 日历库故障，安全跳过关机" >> ${LOG_FILE}
    exit 0
fi

if [ "${IS_WORK}" = "True" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 今日工作日，执行关机" >> ${LOG_FILE}
    /sbin/shutdown -h now
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 周末/节假日，跳过关机" >> ${LOG_FILE}
    exit 0
fi
EOF
chmod +x /usr/local/bin/auto_shutdown_full.sh

# 5. Web面板【新增下次关机日期接口+前端展示】
echo -e "\033[36m[5/9] 部署带下次关机日期面板...\033[0m"
cat > /opt/shutdown-ctrl/web.py << 'EOF'
#!/usr/bin/env python3
import os, subprocess, urllib.parse, datetime
config = {}
with open("/opt/shutdown-ctrl/config.env","r",encoding="utf-8") as f:
    for line in f.readlines():
        line = line.rstrip("\n")
        if line and "=" in line:
            k,v = line.split("=",1)
            config[k] = v
PORT = int(config["PORT"])
PASSWORD = config["PASSWORD"]
LOCK_TMP = config["LOCK_TMP"]
LOCK_GLB = config["LOCK_GLB"]
LOG_FILE = config["LOG_FILE"]

from http.server import HTTPServer, BaseHTTPRequestHandler
from chinese_calendar import is_workday

class Handler(BaseHTTPRequestHandler):
    def resp(self, code, msg, ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(msg.encode("utf-8"))

    def get_post_data(self):
        length = int(self.headers.get("Content-Length",0))
        data = self.rfile.read(length).decode("utf-8")
        return urllib.parse.parse_qs(data, keep_blank_values=True)

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
.info {background:#f0f2f5; padding:15px; border-radius:8px; margin:15px 0; font-size:16px; line-height:1.8;}
.tip {color:#888; font-size:13px; margin-top:20px;}
#login-area, #control-area {display: none;}
#login-area {display: block;}
</style>
</head>
<body>
<div class="box" id="login-area">
<h2>自动关机控制面板</h2>
<p>请输入管理密码登录（支持!@#$%^&*空格中文）</p>
<input type="password" id="pwd-input" placeholder="密码" autofocus>
<br>
<button class="btn-primary" onclick="login()">登录</button>
<div id="login-error" style="color:red; margin-top:10px;"></div>
</div>

<div class="box" id="control-area" style="display:none;">
<h2>服务器自动关机控制面板</h2>
<div class="info">
<p>当前状态：<span id="status">加载中...</span></p>
<p>今日类型：<span id="today_info">-</span></p>
<p>下次关机日期：<span id="next_workday">-</span></p>
</div>
<div>
<button class="btn-red" onclick="runCmd('tmp_off')">今晚不关机</button>
<button class="btn-green" onclick="runCmd('tmp_on')">恢复今晚自动关机</button>
<button class="btn-red" onclick="runCmd('glb_off')">永久关闭自动关机</button>
<button class="btn-green" onclick="runCmd('glb_on')">恢复全局自动关机</button>
<button class="btn-blue" onclick="getState()">刷新状态</button>
<button class="btn-blue" onclick="logout()">退出登录</button>
</div>
<div class="tip">密码本地安全存储，完整兼容所有特殊符号</div>
</div>

<script>
function showControl() {
    document.getElementById('login-area').style.display = 'none';
    document.getElementById('control-area').style.display = 'block';
    getState();
}

async function login() {
    const rawPwd = document.getElementById('pwd-input').value;
    document.getElementById('login-error').innerText = '';
    if (!rawPwd) {
        document.getElementById('login-error').innerText = '请输入密码';
        return;
    }
    try {
        const formBody = new URLSearchParams();
        formBody.append('p', rawPwd);
        const res = await fetch('/login', {
            method:'POST',
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: formBody.toString()
        });
        const retText = await res.text();
        if (res.status === 403) {
            document.getElementById('login-error').innerText = '密码错误，请重试';
            localStorage.removeItem('shutdown_pwd');
            return;
        }
        if (retText === "ok") {
            localStorage.setItem('shutdown_pwd', rawPwd);
            showControl();
        } else {
            document.getElementById('login-error').innerText = '登录失败';
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
    return localStorage.getItem('shutdown_pwd') || '';
}

async function postReq(url, data) {
    const rawPwd = getPwd();
    if (!rawPwd) {
        alert('请重新登录');
        logout();
        return null;
    }
    const formBody = new URLSearchParams();
    formBody.append('p', rawPwd);
    for (let key in data) {
        formBody.append(key, data[key]);
    }
    const res = await fetch(url, {
        method:'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: formBody.toString()
    });
    if (res.status === 403) {
        alert('密码错误，请重新登录');
        logout();
        return null;
    }
    return await res.text();
}

async function runCmd(cmd) {
    const ret = await postReq('/action', {cmd:cmd});
    if (ret) {
        alert(ret);
        getState();
    }
}

async function getState() {
    try {
        const stat = await postReq('/status', {});
        const day = await postReq('/today', {});
        const nextDay = await postReq('/next_date', {});
        if (stat && day && nextDay) {
            document.getElementById('status').innerText = stat;
            document.getElementById('today_info').innerText = day;
            document.getElementById('next_workday').innerText = nextDay;
        }
    } catch(e) {
        alert('获取状态失败，请重试');
    }
}

window.onload = function() {
    const rawPwd = getPwd();
    if (rawPwd) {
        (async () => {
            try {
                const formBody = new URLSearchParams();
                formBody.append('p', rawPwd);
                const res = await fetch('/login', {
                    method:'POST',
                    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                    body: formBody.toString()
                });
                const txt = await res.text();
                if (res.ok && txt === "ok") {
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
        params_raw = self.get_post_data()
        input_pwd = params_raw.get("p", [""])[0]
        real_pwd = PASSWORD

        # 专用登录校验接口
        if path == "/login":
            if input_pwd == real_pwd:
                self.resp(200, "ok")
            else:
                self.resp(403, "fail")
            return

        # 全局鉴权拦截所有业务接口
        if input_pwd != real_pwd:
            self.resp(403, "密码错误"); return

        if path == "/action":
            cmd = params_raw.get("cmd", [""])[0]
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
                today = datetime.date.today()
                if is_workday(today):
                    day_info = "工作日"
                else:
                    day_info = "周末/法定节假日"
            except Exception as e:
                day_info = "日历库读取异常"
            self.resp(200, day_info)
            return

        # 新增接口：查找下一个工作日（下次关机日期）
        if path == "/next_date":
            try:
                current = datetime.date.today()
                next_work = None
                # 向后循环365天查找第一个工作日
                for i in range(1, 366):
                    check_day = current + datetime.timedelta(days=i)
                    if is_workday(check_day):
                        next_work = check_day
                        break
                if next_work:
                    date_str = f"{next_work.year}年{next_work.month:02d}月{next_work.day:02d}日 00:01"
                else:
                    date_str = "未查询到有效工作日"
            except Exception as e:
                date_str = "日期计算异常"
            self.resp(200, date_str)
            return

        self.resp(404, "接口不存在")

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()
EOF
chmod +x /opt/shutdown-ctrl/web.py

# 6. Systemd服务
echo -e "\033[36m[6/9] 配置开机自启服务...\033[0m"
cat > /etc/systemd/system/shutdown-web.service << EOF
[Unit]
Description=Auto Shutdown Web Control Service
After=network.target syslog.target
[Service]
EnvironmentFile=${CONFIG_FILE}
ExecStart=/usr/bin/python3 /opt/shutdown-ctrl/web.py
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal+console
StandardError=journal+console
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now shutdown-web

# 7. 定时任务
echo -e "\033[36m[7/9] 配置每日0点01分关机任务...\033[0m"
OLD_CRON=$(crontab -l 2>/dev/null | grep -v "auto_shutdown_full.sh")
echo "$OLD_CRON" > /tmp/new_cron.tmp
echo "${CRON_TIME} /usr/local/bin/auto_shutdown_full.sh >> ${LOG_FILE} 2>&1" >> /tmp/new_cron.tmp
crontab /tmp/new_cron.tmp
rm -f /tmp/new_cron.tmp

# 8. 日志切割
echo -e "\033[36m[8/9] 配置日志自动切割防止占盘...\033[0m"
cat > /etc/logrotate.d/auto_shutdown << EOF
${LOG_FILE} {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 600 root root
}
EOF

# 9. 防火墙放行
echo -e "\033[36m[9/9] 放行端口防火墙...\033[0m"
if command -v ufw &> /dev/null; then
    ufw allow ${PORT}/tcp comment "auto shutdown web panel"
    ufw reload 2>/dev/null || true
fi

# 安装完成输出信息
echo -e "\033[34m======================================================\033[0m"
echo -e "\033[32m✅ 全部组件安装完成！新增下次关机日期显示\033[0m"
echo -e "\033[36m访问地址：\033[0m"
for ip in $(hostname -I); do
    echo "  http://${ip}:${PORT}"
done
echo -e "\033[36m管理密码：${PASSWORD}\033[0m"
echo -e "\033[36m定时关机：每日00:01\033[0m"
echo -e "\033[36m执行日志：${LOG_FILE}\033[0m"
echo -e "\033[36m服务管理命令：\033[0m"
echo "  systemctl status shutdown-web  查看面板运行状态"
echo "  systemctl restart shutdown-web 重启Web控制面板"
echo "  tail -f ${LOG_FILE} 实时查看自动关机执行日志"
echo -e "\033[34m======================================================\033[0m"