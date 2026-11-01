# 抖音 Playwright 数据采集工具 - Windows 安装脚本
# 使用方法: 右键 → 使用 PowerShell 运行

$ErrorActionPreference = "Stop"

Write-Host "=== 抖音 Playwright 数据采集工具 安装 ===" -ForegroundColor Cyan

# 检查 Python
$pythonVersion = python --version 2>$null
if (-not $pythonVersion) {
    Write-Host "错误: 未找到 Python，请先安装 Python 3.10+" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Python: $pythonVersion"

# 检查 Node.js
$nodeVersion = node --version 2>$null
if (-not $nodeVersion) {
    Write-Host "错误: 未找到 Node.js，请先安装 Node.js 18+" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Node.js: $nodeVersion"

# 安装 Python 依赖
Write-Host "`n正在安装 Python 依赖..." -ForegroundColor Yellow
pip install -r requirements.txt

# 安装 Playwright 浏览器
Write-Host "`n正在安装 Playwright Chromium..." -ForegroundColor Yellow
playwright install chromium

# 创建数据目录
New-Item -ItemType Directory -Force -Path "data\output" >$null

Write-Host "`n=== 安装完成 ===" -ForegroundColor Green
Write-Host "使用方法:" -ForegroundColor Cyan
Write-Host "  1. 登录: python cli/main.py auth"
Write-Host "  2. 验证: python cli/main.py check-auth"
Write-Host "  3. 抓取博主: python cli/main.py blogger <URL> --top 10"
Write-Host "  4. 抓取视频: python cli/main.py video <URL>"
