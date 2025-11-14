# 3proxy Docker 部署安装指南

基于 `deploy.sh` 快速部署脚本的完整安装和使用说明。

## 目录

- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [安装步骤](#安装步骤)
- [使用方法](#使用方法)
- [配置说明](#配置说明)
- [常用命令](#常用命令)
- [故障排除](#故障排除)

## 系统要求

### 必需软件

- **Docker** (版本 20.10 或更高)
- **Docker Compose** (新版本 Docker 已包含，或独立安装 docker-compose)
- **Bash** (Linux/macOS) 或 **PowerShell** (Windows)

### 检查 Docker 环境

```bash
# 检查 Docker 版本
docker --version

# 检查 Docker Compose（新版本）
docker compose version

# 或检查 docker-compose（旧版本）
docker-compose --version
```

## 快速开始

### 1. 下载脚本

确保 `deploy.sh` 文件在项目目录中。

### 2. 添加执行权限

```bash
chmod +x deploy.sh
```

### 3. 运行部署脚本

```bash
./deploy.sh
```

脚本会自动：
- 创建配置文件
- 生成随机密码
- 启动 Docker 容器

## 安装步骤

### 步骤 1: 准备环境

确保 Docker 和 Docker Compose 已安装并运行：

```bash
# 启动 Docker 服务（如果未运行）
sudo systemctl start docker  # Linux
# 或
sudo service docker start    # 某些 Linux 发行版
```

### 步骤 2: 运行部署脚本

```bash
./deploy.sh
```

### 步骤 3: 查看部署信息

部署成功后，脚本会显示：
- 服务端口信息
- 登录凭据（用户名和密码）
- 流量限制配置

**⚠️ 重要：请妥善保存自动生成的密码！**

## 使用方法

### 基本用法

```bash
# 使用默认配置
./deploy.sh

# 查看帮助信息
./deploy.sh --help
```

### 自定义端口

支持两种参数格式：

#### 方式 1: 空格分隔

```bash
./deploy.sh --http-port 3128 --socks-port 1080 --admin-port 8080
```

#### 方式 2: 等号格式

```bash
./deploy.sh --http-port=3128 --socks-port=1080 --admin-port=8080
```

#### 方式 3: 环境变量

```bash
HTTP_PORT=3128 SOCKS_PORT=1080 ADMIN_PORT=8080 ./deploy.sh
```

### 自定义用户和密码

```bash
# 指定管理员用户名和密码
./deploy.sh --admin-user admin --admin-pass mypassword

# 指定代理用户名和密码
./deploy.sh --proxy-user user1 --proxy-pass mypassword

# 完整示例
./deploy.sh \
  --http-port=3128 \
  --socks-port=1080 \
  --admin-port=8080 \
  --admin-user=admin \
  --admin-pass=mypassword \
  --proxy-user=user1 \
  --proxy-pass=mypassword
```

### 参数说明

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `--http-port` | HTTP 代理端口 | 3128 | `--http-port=8888` |
| `--socks-port` | SOCKS5 代理端口 | 1080 | `--socks-port=9999` |
| `--admin-port` | 管理面板端口 | 8080 | `--admin-port=9090` |
| `--admin-user` | 管理员用户名 | admin | `--admin-user=myadmin` |
| `--admin-pass` | 管理员密码 | 自动生成 | `--admin-pass=mypass` |
| `--proxy-user` | 代理用户名 | user1 | `--proxy-user=myuser` |
| `--proxy-pass` | 代理用户密码 | 自动生成 | `--proxy-pass=mypass` |
| `-h, --help` | 显示帮助信息 | - | `./deploy.sh --help` |

## 配置说明

### 目录结构

部署后会创建以下目录结构：

```
.
├── deploy.sh              # 部署脚本
├── docker-compose.yml     # Docker Compose 配置
├── conf/                  # 配置文件目录
│   ├── 3proxy.cfg        # 主配置文件
│   ├── passwd            # 用户密码文件
│   ├── counters          # 流量限制配置
│   └── bandlimiters      # 带宽限制配置
└── data/                 # 数据目录
    └── count/            # 流量计数器数据
```

### 配置文件说明

#### 1. `conf/3proxy.cfg` - 主配置文件

包含 DNS、日志、用户、代理服务等配置。

#### 2. `conf/passwd` - 用户密码文件

格式：`用户名:密码类型:密码`

密码类型：
- `CL` - 明文密码（默认）
- `CR` - MD5 crypt 格式（推荐）
- `NT` - NT 格式（MD4）

示例：
```
admin:CL:admin123
user1:CL:password1
```

#### 3. `conf/counters` - 流量限制配置

默认限制：**10GB/月** (10240 MB)

可以修改限制类型：
- `D` - 每天
- `W` - 每周
- `M` - 每月（默认）
- `H` - 每小时

#### 4. `conf/bandlimiters` - 带宽限制配置

默认不限制带宽，可按需启用。

### 使用加密密码

#### 方法 1: 在容器内生成

```bash
# 进入容器
docker exec -it 3proxy /bin/sh

# 生成 MD5 crypt 密码
mycrypt $$ mypassword
# 输出: CR:$1$12345$hashedpassword

# 生成 NT 密码
mycrypt mypassword
# 输出: NT:BD7DFBF29A93F93C63CB84790DA00E63
```

#### 方法 2: 编辑 passwd 文件

```bash
# 编辑密码文件
vi ./conf/passwd

# 使用加密密码（注意：包含 $ 符号需要用引号）
admin:CR:$1$abc123$xyz789
```

## 常用命令

### 容器管理

```bash
# 查看容器状态
docker ps | grep 3proxy

# 查看日志
docker logs -f 3proxy

# 查看最近 100 行日志
docker logs --tail 100 3proxy

# 停止服务
docker compose down

# 重启服务
docker compose restart

# 停止并删除容器
docker compose down -v
```

### 配置管理

```bash
# 修改配置后重启
docker compose restart

# 重新加载配置（无需重启）
# 3proxy 支持配置热重载，修改配置文件后会自动重新加载
```

### 用户管理

#### 添加新用户

编辑 `./conf/passwd` 文件：

```bash
# 添加新用户（明文密码）
echo "newuser:CL:newpassword" >> ./conf/passwd

# 或使用加密密码
docker exec -it 3proxy sh -c "mycrypt \$\$ newpassword"
# 然后将输出添加到 passwd 文件
```

#### 添加用户流量限制

编辑 `./conf/counters` 文件：

```bash
# 添加新用户的流量限制（编号必须唯一）
countin "3/newuser" M 10240 newuser * * *
```

## 访问服务

### HTTP 代理

- **地址**: `http://你的服务器IP:3128`
- **认证**: 用户名/密码（在 `passwd` 文件中配置）

### SOCKS5 代理

- **地址**: `你的服务器IP:1080`
- **认证**: 用户名/密码（在 `passwd` 文件中配置）

### 管理面板

- **地址**: `http://你的服务器IP:8080`
- **用户名**: admin（或你配置的管理员用户名）
- **密码**: 部署时显示的密码

## 流量限制

### 默认配置

- **限制**: 10GB/月 (10240 MB)
- **类型**: 每月 (M)
- **配置文件**: `./conf/counters`

### 修改流量限制

编辑 `./conf/counters` 文件：

```bash
# 修改为每天 1GB
countin "1/admin" D 1024 admin * * *

# 修改为每周 5GB
countin "1/admin" W 5120 admin * * *
```

### 禁用流量限制

如果不需要流量限制，可以：

1. **注释掉 counter 配置**（在 `3proxy.cfg` 中）
2. **删除 counters 文件内容**（保留空文件或删除 include 行）

## 带宽限制

默认不限制带宽。如需启用，编辑 `./conf/bandlimiters`：

```bash
# 限制每个用户带宽为 10Mbps
bandlimin 10485760 * * * *

# 限制特定用户带宽为 1Mbps
bandlimin 1048576 user1 * * * *
```

带宽单位：**bits per second (bps)**
- 1Mbps = 1048576 bps
- 10Mbps = 10485760 bps

## 故障排除

### 问题 1: 容器无法启动

**检查 Docker 状态：**
```bash
docker ps -a | grep 3proxy
docker logs 3proxy
```

**常见原因：**
- 端口被占用
- 配置文件语法错误
- 权限问题

### 问题 2: 无法访问管理面板

**检查：**
1. 容器是否运行：`docker ps | grep 3proxy`
2. 端口是否正确映射：`docker port 3proxy`
3. 防火墙是否开放端口

### 问题 3: 代理连接失败

**检查：**
1. 用户名和密码是否正确
2. 查看日志：`docker logs -f 3proxy`
3. 检查 ACL 配置（`allow` 规则）

### 问题 4: 流量统计不工作

**检查：**
1. `/count` 目录权限是否正确
2. 查看日志是否有权限错误
3. 检查 `counters` 配置文件语法

### 问题 5: 密码文件权限错误

如果遇到权限问题，确保文件可读：

```bash
chmod 644 ./conf/passwd
chmod 644 ./conf/3proxy.cfg
```

## 安全建议

1. **使用强密码**：避免使用默认密码
2. **使用加密密码**：使用 `CR` 或 `NT` 类型而非 `CL`
3. **限制访问**：配置 ACL 规则限制访问来源
4. **定期更新**：保持 Docker 镜像和系统更新
5. **备份配置**：定期备份配置文件

## 高级配置

### 修改默认流量限制

编辑 `deploy.sh` 文件，修改以下变量：

```bash
TRAFFIC_LIMIT="10240"        # 10GB = 10240 MB
TRAFFIC_LIMIT_TYPE="M"       # M=每月, D=每天, W=每周
```

### 使用自定义 Docker 镜像

修改 `deploy.sh` 中的镜像名称：

```bash
IMAGE_NAME="your-registry/3proxy:tag"
```

### 添加更多 DNS 服务器

编辑 `./conf/3proxy.cfg`：

```
nserver 8.8.8.8
nserver 8.8.4.4
nserver 1.1.1.1
```

## 卸载

```bash
# 停止并删除容器
docker compose down

# 删除数据目录（可选）
rm -rf ./data ./conf docker-compose.yml
```

## 支持与帮助

- **官方文档**: https://3proxy.org/
- **GitHub**: https://github.com/z3APA3A/3proxy
- **Wiki**: https://github.com/3proxy/3proxy/wiki

## 许可证

(c) 2002-2025 by Vladimir '3APA3A' Dubrovin <3proxy@3proxy.org>

请查看项目 LICENSE 文件了解详细信息。

