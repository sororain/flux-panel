# Flux-Panel 转发规则同步工具

## 概述

当面板更换服务器、节点重连或数据迁移后，数据库中的转发规则不会自动同步到 gost 节点。本脚本通过调用面板 API，将所有活跃的转发规则重新推送到对应的节点上。

提供 **两个版本**，配置文件 **完全通用**：
- `sync-rules.sh` — Linux bash 版（也适用于 macOS / WSL）
- `sync-rules.ps1` — Windows PowerShell 版
- `sync-rules.bat` — Windows 快捷版（直接双击运行）

---

## 快速开始

### 1. 生成配置文件

```bash
# Linux
./sync-rules.sh --new-config

# Windows
.\sync-rules.ps1 -NewConfig
```

生成 `sync-config.json`，填入你的信息：

```json
{
    "url": "https://你的面板地址",
    "token": "你的Token值"
}
```

> 也可以使用用户名密码方式：
> ```json
> {
>     "url": "https://你的面板地址",
>     "username": "admin_user",
>     "password": "admin_user"
> }
> ```

### 2. 试运行

```bash
# Linux
./sync-rules.sh -c sync-config.json --dry-run

# Windows
.\sync-rules.ps1 -Config sync-config.json -DryRun
```

### 3. 正式同步

```bash
# Linux
./sync-rules.sh -c sync-config.json

# Windows
.\sync-rules.ps1 -Config sync-config.json
```

---

## 获取 Token（推荐）

1. 打开面板页面，按 `F12` 打开开发者工具
2. 进入 **Application** → **Local Storage**
3. 找到当前站点下的 `token` 项，复制其值

---

## 完整命令参考

### Linux 版

| 命令 | 说明 |
|------|------|
| `./sync-rules.sh -c sync-config.json` | 使用配置文件同步 |
| `./sync-rules.sh -u URL -T TOKEN` | 命令行直接指定 Token |
| `./sync-rules.sh -u URL -U user -P pass` | 命令行直接指定账号密码 |
| `./sync-rules.sh -c sync-config.json --dry-run` | 试运行 |
| `./sync-rules.sh --new-config` | 生成配置模板 |
| `./sync-rules.sh -h` | 查看帮助 |

### Windows 版

| 命令 | 说明 |
|------|------|
| `.\sync-rules.ps1 -Config sync-config.json` | 使用配置文件同步 |
| `.\sync-rules.ps1 -Url URL -Token TOKEN` | 命令行直接指定 Token |
| `.\sync-rules.ps1 -Url URL -Username user -Password pass` | 命令行直接指定账号密码 |
| `.\sync-rules.ps1 -Config sync-config.json -DryRun` | 试运行 |
| `.\sync-rules.ps1 -NewConfig` | 生成配置模板 |
| `.\sync-rules.ps1 -?` | 查看帮助 |

---

## 定时自动同步

### Linux crontab（每6小时）

```bash
crontab -e
```

添加：

```bash
0 */6 * * * /path/to/sync-tools/sync-rules.sh -c /path/to/sync-tools/sync-config.json >> /var/log/flux-sync.log 2>&1
```

### Windows 任务计划程序

1. 打开 **任务计划程序**
2. 创建基本任务 → 触发器选择"每天"，重复间隔设为 **6小时**
3. 操作选择"启动程序"
4. 程序或脚本：`powershell.exe`
5. 添加参数：`-ExecutionPolicy Bypass -File "C:\path\to\sync-tools\sync-rules.ps1" -Config "C:\path\to\sync-tools\sync-config.json"`

---

## 文件结构

```
sync-tools/
├── sync-rules.sh        # Linux bash 版
├── sync-rules.ps1       # Windows PowerShell 版
├── sync-config.json     # 统一配置文件（Linux/Windows 通用）
└── README.md            # 本文件
```

## 环境要求

### Windows 版
- Windows 7 / Windows Server 2012 及以上
- PowerShell 5.0+（Windows 自带）
- 无需额外安装任何软件

### Linux 版
- `bash`（Linux / macOS / WSL）
- `curl`
- `python3`（用于 JSON 解析）
