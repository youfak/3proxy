# 3proxy 快速部署脚本 (PowerShell)
# 使用方法: 
#   .\deploy.ps1
#   .\deploy.ps1 -HttpPort 3128 -SocksPort 1080 -AdminPort 8080
#   .\deploy.ps1 -AdminUser admin -AdminPass mypass -ProxyUser user1 -ProxyPass mypass
#   或使用环境变量: $env:HTTP_PORT="3128"; $env:ADMIN_PASS="mypass"; .\deploy.ps1

param(
    [int]$HttpPort = 0,
    [int]$SocksPort = 0,
    [int]$AdminPort = 0,
    [string]$AdminUser = "",
    [string]$AdminPass = "",
    [string]$ProxyUser = "",
    [string]$ProxyPass = ""
)

# 配置变量（可根据需要修改）
$ConfigDir = ".\conf"
$ImageName = "youfak/3proxy:latest"
$ContainerName = "3proxy"

# 端口配置（可通过命令行参数或环境变量设置，未设置则使用默认值）
if ($HttpPort -eq 0) {
    $HttpPort = if ($env:HTTP_PORT) { $env:HTTP_PORT } else { "3128" }
}
if ($SocksPort -eq 0) {
    $SocksPort = if ($env:SOCKS_PORT) { $env:SOCKS_PORT } else { "1080" }
}
if ($AdminPort -eq 0) {
    $AdminPort = if ($env:ADMIN_PORT) { $env:ADMIN_PORT } else { "8080" }
}

# 生成随机密码函数
function Generate-Password {
    $length = 16
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $password = ""
    for ($i = 0; $i -lt $length; $i++) {
        $password += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $password
}

# 用户配置（可通过命令行参数或环境变量设置，未设置则使用默认值或自动生成）
if ([string]::IsNullOrEmpty($AdminUser)) {
    $AdminUser = if ($env:ADMIN_USER) { $env:ADMIN_USER } else { "admin" }
}

if ([string]::IsNullOrEmpty($AdminPass)) {
    if ($env:ADMIN_PASS) {
        $AdminPass = $env:ADMIN_PASS
        $AdminPassGenerated = $false
    } else {
        $AdminPass = Generate-Password
        $AdminPassGenerated = $true
    }
} else {
    $AdminPassGenerated = $false
}

if ([string]::IsNullOrEmpty($ProxyUser)) {
    $ProxyUser = if ($env:PROXY_USER) { $env:PROXY_USER } else { "user1" }
}

if ([string]::IsNullOrEmpty($ProxyPass)) {
    if ($env:PROXY_PASS) {
        $ProxyPass = $env:PROXY_PASS
        $ProxyPassGenerated = $false
    } else {
        $ProxyPass = Generate-Password
        $ProxyPassGenerated = $true
    }
} else {
    $ProxyPassGenerated = $false
}

# 流量限制配置（单位：MB，10GB = 10240 MB）
$TrafficLimit = "10240"
$TrafficLimitType = "M"  # M=每月, D=每天, W=每周

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "3proxy 快速部署脚本" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "端口配置:" -ForegroundColor Cyan
Write-Host "  - HTTP 代理:  ${HttpPort}" -ForegroundColor White
Write-Host "  - SOCKS5 代理: ${SocksPort}" -ForegroundColor White
Write-Host "  - 管理面板:   ${AdminPort}" -ForegroundColor White
Write-Host ""

# 创建配置目录
Write-Host "[1/7] 创建配置目录..." -ForegroundColor Yellow
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# 创建密码文件
Write-Host "[2/7] 创建密码文件..." -ForegroundColor Yellow
$passwdContent = @"
${AdminUser}:CL:${AdminPass}
${ProxyUser}:CL:${ProxyPass}
"@
$passwdContent | Out-File -FilePath "$ConfigDir\passwd" -Encoding utf8 -NoNewline
Write-Host "✓ 密码文件已创建: $ConfigDir\passwd" -ForegroundColor Green
if ($AdminPassGenerated) {
    Write-Host "  - 管理员: ${AdminUser} / ${AdminPass} (自动生成)" -ForegroundColor Gray
} else {
    Write-Host "  - 管理员: ${AdminUser} / ${AdminPass}" -ForegroundColor Gray
}
if ($ProxyPassGenerated) {
    Write-Host "  - 代理用户: ${ProxyUser} / ${ProxyPass} (自动生成)" -ForegroundColor Gray
} else {
    Write-Host "  - 代理用户: ${ProxyUser} / ${ProxyPass}" -ForegroundColor Gray
}

# 创建主配置文件
Write-Host "[3/7] 创建配置文件..." -ForegroundColor Yellow
$configContent = @'
# DNS 配置
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536

# 日志配置（输出到 stdout，方便 docker logs 查看，避免权限问题）
log

# 流量计数器
counter /count/3proxy.3cf

# 从文件加载用户
users $/conf/passwd

# 包含流量限制和带宽限制配置
include /conf/counters
include /conf/bandlimiters

# HTTP/SOCKS 代理配置
auth strong
allow *
proxy -p3128
socks -p1080

# 管理面板配置
flush
auth strong
allow admin
admin -p8080
'@
$configContent | Out-File -FilePath "$ConfigDir\3proxy.cfg" -Encoding utf8 -NoNewline
Write-Host "✓ 配置文件已创建: $ConfigDir\3proxy.cfg" -ForegroundColor Green

# 创建流量限制配置文件
Write-Host "[4/7] 创建流量限制配置..." -ForegroundColor Yellow
$countersContent = @"
# 流量限制配置文件
# 格式: countin "编号/名称" 类型 限制(MB) 用户列表 源地址 目标地址 目标端口 操作
# 类型: D=每天, W=每周, M=每月, H=每小时

# 不统计内网流量（192.168.0.0/16 和 10.0.0.0/8）
nocountin * * 192.168.0.0/16,10.0.0.0/8

# 为每个用户设置 ${TrafficLimit}MB (${TrafficLimitType}) 流量限制
# 注意：需要为每个用户单独配置，编号必须唯一
countin "1/${AdminUser}" ${TrafficLimitType} ${TrafficLimit} ${AdminUser} * * *
countin "2/${ProxyUser}" ${TrafficLimitType} ${TrafficLimit} ${ProxyUser} * * *
"@
$countersContent | Out-File -FilePath "$ConfigDir\counters" -Encoding utf8 -NoNewline
Write-Host "✓ 流量限制配置已创建: $ConfigDir\counters" -ForegroundColor Green
Write-Host "  - 默认限制: ${TrafficLimit}MB/${TrafficLimitType}" -ForegroundColor Gray

# 创建带宽限制配置文件
Write-Host "[5/7] 创建带宽限制配置..." -ForegroundColor Yellow
$bandlimitersContent = @'
# 带宽限制配置文件
# 格式: bandlimin 带宽(bps) 用户列表 源地址 目标地址 目标端口
# 带宽单位: bits per second (bps)
# 例如: 1048576 = 1Mbps, 10485760 = 10Mbps

# 不限制内网带宽
nobandlimin * * 192.168.0.0/16,10.0.0.0/8

# 如果需要限制带宽，取消下面的注释并修改数值
# 示例：限制每个用户带宽为 10Mbps (10485760 bps)
# bandlimin 10485760 * * * *
'@
$bandlimitersContent | Out-File -FilePath "$ConfigDir\bandlimiters" -Encoding utf8 -NoNewline
Write-Host "✓ 带宽限制配置已创建: $ConfigDir\bandlimiters" -ForegroundColor Green

# 创建 docker-compose.yml
Write-Host "[6/7] 创建 docker-compose.yml..." -ForegroundColor Yellow
$composeContent = @"
services:
  3proxy:
    image: ${ImageName}
    container_name: ${ContainerName}
    restart: unless-stopped
    ports:
      - "${HttpPort}:3128"   # HTTP 代理
      - "${SocksPort}:1080"  # SOCKS5 代理
      - "${AdminPort}:8080"  # 管理面板
    volumes:
      - ${ConfigDir}:/usr/local/3proxy/conf
      - ./data:/usr/local/3proxy
    command: >
      sh -c "
        mkdir -p /usr/local/3proxy/count &&
        chmod 777 /usr/local/3proxy/count &&
        /bin/3proxy /etc/3proxy/3proxy.cfg
      "
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
"@
$composeContent | Out-File -FilePath "docker-compose.yml" -Encoding utf8
Write-Host "✓ docker-compose.yml 已创建" -ForegroundColor Green

# 创建数据目录（用于存储计数器数据）
New-Item -ItemType Directory -Path ".\data\count" -Force | Out-Null
# 设置目录权限（Windows 上可能无效，但容器内会处理）
try {
    icacls ".\data\count" /grant Everyone:F 2>$null | Out-Null
} catch {
    # 忽略权限设置错误，容器内会处理
}

# 检测 docker compose 命令
$dockerComposeCmd = $null
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $result = docker compose version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $dockerComposeCmd = "docker compose"
    } else {
        $result = docker-compose --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $dockerComposeCmd = "docker-compose"
        }
    }
}

if (-not $dockerComposeCmd) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "✗ 错误: 未找到 docker compose 或 docker-compose" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "请安装 Docker Compose:" -ForegroundColor Yellow
    Write-Host "  - 新版本 Docker: docker compose 已包含在内" -ForegroundColor White
    Write-Host "  - 旧版本: 请安装 docker-compose" -ForegroundColor White
    Write-Host ""
    Write-Host "检查命令:" -ForegroundColor Yellow
    Write-Host "  docker compose version" -ForegroundColor White
    Write-Host "  或" -ForegroundColor White
    Write-Host "  docker-compose --version" -ForegroundColor White
    exit 1
}

Write-Host "使用命令: ${dockerComposeCmd}" -ForegroundColor Gray

# 停止并删除旧容器（如果存在）
Write-Host "[7/7] 启动容器..." -ForegroundColor Yellow
$existingContainer = docker ps -a --format '{{.Names}}' | Select-String -Pattern "^${ContainerName}$"
if ($existingContainer) {
    Write-Host "  停止并删除旧容器..." -ForegroundColor Gray
    # 先尝试使用 docker compose down
    Invoke-Expression "${dockerComposeCmd} down" 2>$null
    # 如果还有残留，强制删除容器
    $stillExists = docker ps -a --format '{{.Names}}' | Select-String -Pattern "^${ContainerName}$"
    if ($stillExists) {
        Write-Host "  强制删除残留容器..." -ForegroundColor Gray
        docker stop "${ContainerName}" 2>$null
        docker rm -f "${ContainerName}" 2>$null
    }
}

# 启动容器
Invoke-Expression "${dockerComposeCmd} up -d"

# 等待容器启动
Write-Host "  等待容器启动..." -ForegroundColor Gray
Start-Sleep -Seconds 3

# 检查容器状态
$runningContainer = docker ps --format '{{.Names}}' | Select-String -Pattern "^${ContainerName}$"
if ($runningContainer) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "✓ 部署成功！" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "服务信息：" -ForegroundColor Cyan
    Write-Host "  - HTTP 代理:  ${HttpPort}" -ForegroundColor White
    Write-Host "  - SOCKS5 代理: ${SocksPort}" -ForegroundColor White
    Write-Host "  - 管理面板:   http://localhost:${AdminPort}" -ForegroundColor White
    Write-Host ""
    Write-Host "登录信息：" -ForegroundColor Cyan
    Write-Host "  - 管理员用户名: ${AdminUser}" -ForegroundColor White
    Write-Host "  - 管理员密码: ${AdminPass}" -ForegroundColor White
    if ($AdminPassGenerated -or $ProxyPassGenerated) {
        Write-Host "    ⚠️  密码已自动生成，请妥善保存！" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "代理用户信息：" -ForegroundColor Cyan
    Write-Host "  - 用户名: ${ProxyUser}" -ForegroundColor White
    Write-Host "  - 密码: ${ProxyPass}" -ForegroundColor White
    Write-Host ""
    Write-Host "流量限制：" -ForegroundColor Cyan
    Write-Host "  - 默认限制: ${TrafficLimit}MB/${TrafficLimitType}" -ForegroundColor White
    Write-Host "  - 配置文件: ${ConfigDir}\counters" -ForegroundColor White
    Write-Host ""
    Write-Host "常用命令：" -ForegroundColor Cyan
    Write-Host "  - 查看日志: docker logs -f ${ContainerName}" -ForegroundColor White
    Write-Host "  - 停止服务: ${dockerComposeCmd} down" -ForegroundColor White
    Write-Host "  - 重启服务: ${dockerComposeCmd} restart" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "✗ 部署失败，请检查日志" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "查看日志: docker logs ${ContainerName}" -ForegroundColor Yellow
    exit 1
}

