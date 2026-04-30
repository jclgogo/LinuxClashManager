# clash-manager

基于 **mihomo (Clash Meta)** 的 Linux 代理管理脚本。  
适用系统：OpenCloudOS 9 / RHEL 9 / CentOS Stream 9 · 架构：x86_64

---

## 文件说明

```
clash-manager.sh     # 管理脚本
```

运行后自动创建：

```
/etc/mihomo/
├── config.yaml           # 从订阅 URL 下载的配置文件
└── .subscription_url     # 保存的订阅链接（权限 600）

/etc/systemd/system/mihomo.service   # systemd 守护进程
/var/log/mihomo.log                  # 运行日志
```

---

## 前置条件

mihomo 二进制已安装：

```bash
ls -lh /usr/local/bin/mihomo
mihomo -v
```

如未安装，下载 x86_64 版本：

```bash
curl -L -o /tmp/mihomo.gz \
  https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-amd64-v1.19.24.gz
gunzip /tmp/mihomo.gz
sudo mv /tmp/mihomo-linux-amd64-v1.19.24 /usr/local/bin/mihomo
sudo chmod +x /usr/local/bin/mihomo
```

---

## 快速开始

```bash
# 1. 赋予执行权限
chmod +x clash-manager.sh

# 2. 以 root 运行
sudo bash clash-manager.sh
```

### 首次使用流程

```
运行脚本
  → 选 3（粘贴订阅链接，自动下载 config.yaml）
  → 选 1（启动，自动创建 systemd 守护进程）
  → 选 5（查看代理端口和环境变量设置方法）
```

---

## 菜单功能

| 选项 | 功能 | 说明 |
|------|------|------|
| 1 | 开启 | 启动 mihomo，首次会自动创建 systemd 服务 |
| 2 | 关闭 | 停止服务 |
| 3 | 更新订阅 | 重新下载配置，运行中自动重启生效 |
| 4 | 查看日志 | 显示最近 50 行运行日志 |
| 5 | 代理变量 | 显示 export 命令，让终端走代理 |

---

## 状态面板说明

每次进入菜单显示：

```
✓ mihomo 已安装  v1.19.24
✓ 服务状态：运行中
▸ 进程 PID：12345
▸ 订阅链接：https://xxx...
✓ 配置文件：更新于 2025-01-01 12:00:00
▸ Mixed 端口：127.0.0.1:7890  (http+socks5)
```

---

## 设置系统代理

mihomo 启动后，终端程序还需要手动设置代理环境变量。  
脚本选项 **5** 会自动读取配置端口并显示命令：

```bash
# 临时生效（当前终端）
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890

# 取消代理
unset http_proxy https_proxy all_proxy

# 永久写入（所有新终端生效）
echo 'export http_proxy=http://127.0.0.1:7890' >> ~/.bashrc
echo 'export https_proxy=http://127.0.0.1:7890' >> ~/.bashrc
source ~/.bashrc
```

> 端口号以 config.yaml 中 `mixed-port` 或 `port` 的值为准，常见为 7890。

---

## systemd 常用命令

```bash
# 查看服务状态
systemctl status mihomo

# 查看实时日志
journalctl -u mihomo -f

# 开机自启（脚本首次启动时已自动设置）
systemctl enable mihomo

# 取消开机自启
systemctl disable mihomo
```

---

## 常见问题

**Q：启动失败怎么排查？**
```bash
tail -50 /var/log/mihomo.log
# 或
journalctl -u mihomo -n 50 --no-pager
```

**Q：订阅更新后没生效？**  
脚本在更新订阅时会自动重启服务。如手动修改了配置文件：
```bash
systemctl restart mihomo
```

**Q：curl/wget 走不了代理？**  
先在终端执行选项 5 提示的 `export` 命令，再运行 curl。

**Q：想换订阅链接？**  
直接选菜单 3，粘贴新链接即可，旧链接会被覆盖。

---

## 卸载

```bash
systemctl stop mihomo
systemctl disable mihomo
rm /etc/systemd/system/mihomo.service
systemctl daemon-reload
rm -rf /etc/mihomo
rm /usr/local/bin/mihomo
rm /var/log/mihomo.log
```