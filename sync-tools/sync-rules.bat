@echo off
chcp 65001 >nul
title Flux-Panel 规则同步

set DIR=%~dp0
set CONFIG=%DIR%sync-config.json

if not exist "%CONFIG%" (
    echo [ERROR] 配置文件不存在: %CONFIG%
    echo.
    echo 请先运行生成配置:
    echo   %~dp0sync-rules.ps1 -NewConfig
    pause
    exit /b 1
)

echo [INFO] 正在同步转发规则...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0sync-rules.ps1' -Config '%~dp0sync-config.json'" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo [WARN] 同步过程中出现错误，请检查日志
    pause
) else (
    echo.
    echo [OK] 同步完成
    timeout /t 3 /nobreak >nul
)
