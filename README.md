# auto-shutdown
一套基于 Linux 的自动关机系统，支持中国节假日识别、Web 控制面板、年度自动升级。


# 自动关机系统 - 使用文档（README）
## 一、项目简介
一套基于 Linux + Python + Shell + Systemd + Crontab 实现的**服务器/设备自动定时关机系统**
核心能力：
1. 自动识别**法定节假日/周末/工作日**，工作日凌晨自动关机，节假日跳过关机
2. 数据源优先级：在线节假日API → 本地节假日库 → 简易周规则兜底
3. 自带 Web 可视化控制面板，状态清晰、操作简单
4. 内置定时缓存刷新、节假日库年度自动升级
5. 支持**临时今晚不关机**、**永久关闭自动关机**两种控制模式

适配系统：Ubuntu 22.04 / 24.04（已兼容 Python PEP 668 系统环境保护）

---

## 二、文件与目录说明
### 1. 核心路径
```
/opt/shutdown-ctrl/          # 程序主目录
├─ web.py                     # Web 控制面板
├─ update_cc.sh               # 节假日库自动升级脚本
└─ update_cc.log              # 升级日志

/usr/local/bin/auto_shutdown_full.sh  # 关机主逻辑脚本

/etc/systemd/system/shutdown-web.service  # Web 面板自启服务

/var/cache/holiday_flat.json  # 节假日缓存文件
/etc/no_shutdown_all.lock     # 全局禁用锁（永久不关机）
/tmp/no_shutdown.lock         # 临时禁用锁（仅当晚不关机）

/var/log/auto_shutdown.log         # 每日关机执行日志
/var/log/auto_shutdown_refresh.log # 节假日缓存刷新日志
```

### 2. Crontab 定时任务（自动创建）
1. `01 00 * * *` 每日 00:01 执行关机判断
2. `00 12 * * 1` 每周一 12:00 刷新节假日缓存
3. `00 03 1 12 *` 每年12月1日 03:00 升级节假日库
4. `00 03 15 12 *` 每年12月15日 03:00 二次升级（防单次失败）

---

## 三、安装教程
### 1. 准备文件
将脚本保存为：`install_shutdown_all.sh`

### 2. 赋予执行权限
```bash
chmod +x install_shutdown_all.sh
```

### 3. 执行安装（必须 root/sudo）
```bash
sudo ./install_shutdown_all.sh
```

### 4. 安装交互说明
- 端口：默认 `6788`，可自定义
- 登录密码：默认 `Admin@123456`，可自定义

### 5. 安装完成提示
记录页面输出的：**访问地址 + 登录密码**，用于后台管理。

---

## 四、访问 & 使用 Web 控制面板
1. 浏览器打开：
   ```
   http://服务器IP:端口
   ```
2. 输入安装时设置的密码登录

### 页面状态说明（无歧义精简版）
- **✅ 自动关机已正常开启**：系统按规则运行，工作日正常关机、节假日不关机
- **⏸️ 临时设置：今晚不关机，明晚自动恢复**：仅当晚跳过关机，次日自动恢复规则
- **❌ 自动关机已永久关闭（全局禁用）**：全程不执行自动关机，需手动恢复

- **下次关机时间**：直观显示下一次自动关机的**日期 + 凌晨00:01**

### 按钮功能说明
#### 1. 今晚关机控制（单次生效）
- **今晚不关机**：仅当前当晚跳过关机，第二天自动恢复
- **恢复今晚关机**：取消临时禁用，恢复正常规则

#### 2. 全局关机控制（永久生效）
- **永久关闭自动关机**：所有日期都不再自动关机
- **恢复自动关机**：取消全局禁用，重新启用整套规则

### 底部使用说明
1. 自动识别法定节假日/周末，对应日期不关机；工作日凌晨 00:01 关机
2. 临时设置仅当日有效，无需手动恢复
3. 永久关闭需手动点击恢复才能重新启用
4. 节假日数据优先走网络接口，网络异常自动切换本地库兜底

---

## 五、手动常用命令
### 1. 手动刷新节假日缓存
```bash
auto_shutdown_full.sh --refresh
```

### 2. 手动测试关机逻辑（不真正关机，仅输出判断结果）
```bash
# 临时注释关机命令进行测试
cp /usr/local/bin/auto_shutdown_full.sh /tmp/test.sh
sed -i 's/\/sbin\/shutdown -h now/# \/sbin\/shutdown -h now/' /tmp/test.sh
/tmp/test.sh
```

### 3. 启停 Web 面板服务
```bash
# 启动
systemctl start shutdown-web
# 停止
systemctl stop shutdown-web
# 开机自启（默认已开启）
systemctl enable shutdown-web
# 查看运行状态
systemctl status shutdown-web
```

### 4. 查看日志
```bash
# 关机执行日志
tail -f /var/log/auto_shutdown.log
# 缓存刷新日志
tail -f /var/log/auto_shutdown_refresh.log
# 库升级日志
tail -f /opt/shutdown-ctrl/update_cc.log
```

---

## 六、卸载教程（完全清理，无残留）
### 1. 卸载脚本 `uninstall_shutdown_all.sh`
新建文件并写入以下内容：
```bash
#!/bin/bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
    echo "请使用 root / sudo 执行"
    exit 1
fi

echo "===== 开始卸载自动关机系统 ====="

# 1. 停止并删除 systemd 服务
systemctl stop shutdown-web 2>/dev/null || true
systemctl disable shutdown-web 2>/dev/null || true
rm -f /etc/systemd/system/shutdown-web.service
systemctl daemon-reload

# 2. 删除主程序目录
rm -rf /opt/shutdown-ctrl

# 3. 删除主执行脚本
rm -f /usr/local/bin/auto_shutdown_full.sh

# 4. 删除缓存、锁文件
rm -f /var/cache/holiday_flat.json
rm -f /etc/no_shutdown_all.lock
rm -f /tmp/no_shutdown.lock

# 5. 删除日志文件
rm -f /var/log/auto_shutdown.log
rm -f /var/log/auto_shutdown_refresh.log

# 6. 清理 crontab 相关定时
crontab -l 2>/dev/null | grep -v "auto_shutdown_full.sh" | crontab -

# 7. 卸载 Python 节假日库
pip3 uninstall -y chinesecalendar --break-system-packages 2>/dev/null || true

echo "===== 卸载完成，所有文件、服务、定时已清理 ====="
echo "提示：防火墙端口规则需手动删除（见下方说明）"
```

### 2. 执行卸载
```bash
chmod +x uninstall_shutdown_all.sh
sudo ./uninstall_shutdown_all.sh
```

### 3. 手动清理防火墙端口（可选）
查看放行规则：
```bash
ufw status
```
删除对应端口（示例端口 6788）：
```bash
ufw delete allow 6788/tcp
```

---

## 七、异常排查
1. **Web 面板无法访问**
   - 检查服务状态：`systemctl status shutdown-web`
   - 检查防火墙：`ufw status`，确认端口已放行
2. **节假日识别异常**
   - 手动刷新缓存：`auto_shutdown_full.sh --refresh`
   - 检查网络，网络不通会自动降级为本地库
3. **Python 包安装报错（externally-managed-environment）**
   - 脚本已自带 `--break-system-packages` 参数，正常安装即可
4. **定时不执行**
   - 检查系统时间与时区
   - 查看 crontab：`crontab -l`

---

## 八、版本说明
- 界面：精简无歧义版，移除重复提示，仅保留「系统状态 + 下次关机时间」
- 兼容：Ubuntu 新版 Python PEP 668 环境保护
- 策略：在线API > 本地节假日库 > 周一至周五工作日兜底
- 维护：每年12月自动升级节假日库，保证年份兼容性