# flux-panel 转发面板

基于 [go-gost/gost](https://github.com/go-gost/gost) 和 [go-gost/x](https://github.com/go-gost/x) 的转发管理面板。

---

## 特性

- 支持按 **隧道账号级别** 管理流量转发数量
- 支持 **TCP** 和 **UDP** 协议转发
- 支持两种模式：**端口转发** 与 **隧道转发**
- 支持对 **指定用户的指定隧道进行限速**
- 支持配置 **单向或双向流量计费**
- 提供灵活的转发策略配置

---

## 快速部署

### Docker Compose

**面板端（稳定版）：**
```bash
curl -L https://raw.githubusercontent.com/bqlpfy/flux-panel/refs/heads/main/panel_install.sh -o panel_install.sh && chmod +x panel_install.sh && ./panel_install.sh
```

**节点端（稳定版）：**
```bash
curl -L https://raw.githubusercontent.com/bqlpfy/flux-panel/refs/heads/main/install.sh -o install.sh && chmod +x install.sh && ./install.sh
```

**面板端（开发版）：**
```bash
curl -L https://raw.githubusercontent.com/bqlpfy/flux-panel/refs/heads/beta/panel_install.sh -o panel_install.sh && chmod +x panel_install.sh && ./panel_install.sh
```

**节点端（开发版）：**
```bash
curl -L https://raw.githubusercontent.com/bqlpfy/flux-panel/refs/heads/beta/install.sh -o install.sh && chmod +x install.sh && ./install.sh
```

### 默认管理员账号

| 账号 | 密码 |
|------|------|
| `admin_user` | `admin_user` |

> ⚠️ 首次登录后请立即修改默认密码！

---

## 服务器迁移

1. **旧服务器** — 执行脚本选择 **4**，导出数据库备份
2. **下载备份** — 下载生成的 SQL 文件
3. **上传备份** — 上传至新服务器并改名为 `gost.sql`
4. **新服务器安装** — 执行脚本选择 **1**，安装面板将自动导入备份
