# soga Alpine Linux 安装和使用指南

## 目录
1. [系统要求](#系统要求)
2. [安装步骤](#安装步骤)
3. [配置说明](#配置说明)
4. [服务管理](#服务管理)
5. [常见问题](#常见问题)
6. [卸载方法](#卸载方法)

---

## 系统要求

- **操作系统**: Alpine Linux (推荐最新版本)
- **架构**: x86_64 (amd64) 或 aarch64 (arm64)
- **权限**: root 用户
- **网络**: 能够访问 GitHub

---

## 安装步骤

### 1. 下载安装脚本

```bash
wget https://raw.githubusercontent.com/Miku-programm/soga_alpine/refs/heads/main/soga-alpine-install.sh && chmod 777 soga-alpine-install.sh && ./soga-alpine-install.sh
```

#### 或者使用 curl

```
curl https://raw.githubusercontent.com/Miku-programm/soga_alpine/refs/heads/main/soga-alpine-install.sh && chmod 777 soga-alpine-install.sh && ./soga-alpine-install.sh
```

### 2. 赋予执行权限

```bash
chmod +x soga-alpine-install.sh
```

### 3. 运行安装脚本

```bash
./soga-alpine-install.sh
```

安装脚本会自动完成以下操作：
- 检测系统环境和架构
- 安装必要的依赖包（wget, curl, ca-certificates, openrc, gcompat）
- 下载最新版本的 soga
- 创建 OpenRC 服务
- 创建管理脚本

---

## 配置说明

### 配置文件位置

主配置文件: `/etc/soga/soga.conf`

### 基础配置示例

```ini
# 面板类型 (sspanel, v2board, pmpanel, proxypanel 等)
type=sspanel

# 面板地址
server_host=https://your-panel.com

# API 密钥
api_key=your_api_key_here

# 节点 ID
node_id=1

# 日志级别 (debug, info, warn, error)
log_level=info

# 日志文件目录
log_file_dir=/var/log/soga

# 日志保留天数
log_file_retention_days=7
```

### 编辑配置文件

```bash
vi /etc/soga/soga.conf
```

**重要**: 修改配置文件后需要重启服务才能生效

---

## 服务管理

### 使用 soga 命令 (推荐)

安装完成后，可以使用 `soga` 命令进行管理，完全兼容官方命令行方式：

```bash
# 显示管理菜单（交互式）
soga

# 启动服务
soga start

# 停止服务
soga stop

# 重启服务
soga restart

# 查看状态
soga status

# 设置开机自启
soga enable

# 取消开机自启
soga disable

# 查看日志
soga log

# 更新到最新版本
soga update

# 更新到指定版本
soga update v2.12.5

# 显示配置文件
soga config

# 自动设置配置项
soga config type=sspanel node_id=1

# 查看版本
soga version

# 卸载 soga
soga uninstall
```

### 所有可用命令

```
soga                    - 显示管理菜单 (功能更多)
soga start              - 启动 soga
soga stop               - 停止 soga
soga restart            - 重启 soga
soga enable             - 设置 soga 开机自启
soga disable            - 取消 soga 开机自启
soga log                - 查看 soga 日志
soga update             - 更新 soga 最新版
soga update x.x.x       - 安装 soga 指定版本
soga config             - 显示配置文件内容
soga config xx=xx yy=yy - 自动设置配置文件
soga uninstall          - 卸载 soga
soga version            - 查看 soga 版本
```

### 直接使用 OpenRC 命令（不推荐）

如果你熟悉 OpenRC，也可以直接使用：

```bash
rc-service soga start
rc-service soga stop
rc-service soga restart
rc-update add soga default
rc-update del soga default
```

---

## 查看日志

### 实时查看日志

```bash
tail -f /var/log/soga/output.log
```

### 查看错误日志

```bash
tail -f /var/log/soga/error.log
```

### 使用管理脚本查看日志

```bash
soga-manager
# 选择选项 5
```

---

## 常见问题

### 1. 启动失败

**问题**: 服务无法启动

**解决方法**:
- 检查配置文件是否正确: `cat /etc/soga/soga.conf`
- 查看错误日志: `cat /var/log/soga/error.log`
- 确保 API 地址和密钥正确
- 检查节点 ID 是否存在

### 2. glibc 兼容性问题

**问题**: 提示缺少 glibc 库

**解决方法**:
```bash
apk add gcompat
```

### 3. 无法连接到面板

**问题**: 日志显示无法连接到面板

**解决方法**:
- 检查网络连接
- 确认面板地址正确
- 检查防火墙设置
- 验证 API 密钥

### 4. 端口被占用

**问题**: 端口已被使用

**解决方法**:
```bash
# 查看端口占用
netstat -tulpn | grep <端口号>

# 或使用 ss 命令
ss -tulpn | grep <端口号>
```

### 5. 日志文件过大

**问题**: 日志占用大量磁盘空间

**解决方法**:
- 配置文件中设置 `log_file_retention_days` 来自动清理旧日志
- 手动清理: `rm -f /var/log/soga/*.log`

---

## 目录结构

```
/usr/local/bin/soga              # soga 主程序
/usr/local/bin/soga-manager      # 管理脚本
/etc/soga/                       # 配置目录
    ├── soga.conf                # 主配置文件
    ├── blockList                # 屏蔽规则
    └── dns.yml                  # DNS 配置
/etc/init.d/soga                 # OpenRC 服务脚本
/var/log/soga/                   # 日志目录
    ├── output.log               # 标准输出日志
    └── error.log                # 错误日志
```

---

## 卸载方法

### 方法一: 使用管理脚本

```bash
soga-manager
# 选择选项 9 (卸载 soga)
```

### 方法二: 手动卸载

```bash
# 停止服务
rc-service soga stop

# 移除开机自启
rc-update del soga default

# 删除文件
rm -f /etc/init.d/soga
rm -f /usr/local/bin/soga
rm -f /usr/local/bin/soga-manager
rm -rf /etc/soga
rm -rf /var/log/soga
```

---

## 更新 soga

```bash
# 重新运行安装脚本即可更新到最新版本
./soga-alpine-install.sh

# 或者手动下载新版本
cd /tmp
wget https://github.com/vaxilu/soga/releases/download/<version>/soga-linux-amd64.tar.gz
tar -xzf soga-linux-amd64.tar.gz
cd soga
cp soga /usr/local/bin/
rc-service soga restart
```

---

## 支持的面板类型

- sspanel
- v2board
- pmpanel
- proxypanel
- v2raysocks
- soga-v1

---

## 支持的协议

- VMess
- VLESS
- Trojan
- Shadowsocks
- ShadowsocksR

---

## 注意事项

1. **备份配置**: 更新前请备份 `/etc/soga/soga.conf`
2. **安全性**: 妥善保管 API 密钥
3. **防火墙**: 确保节点端口已开放
4. **时间同步**: 某些协议需要服务器时间同步
5. **资源监控**: 定期检查系统资源使用情况

---

## 性能优化建议

1. 根据用户数量调整 `user_conn_limit`
2. 启用日志自动清理，避免磁盘占满
3. 合理设置 `report_interval`，减少 API 请求频率
4. 使用 VLESS 协议替代 VMess，降低内存占用



## 许可证

本安装脚本遵循 MIT 许可证
soga 项目许可证请参考原项目
