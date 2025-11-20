## 🔧 n8n + Traefik One-Click Ubuntu Deployment Script (Certificate Verification Enhanced)
A user-friendly automation script designed for beginners and developers to quickly set up **n8n (automation tool)** + **Traefik (reverse proxy)** on Linux servers (Ubuntu/Debian), with automatic HTTPS certificate issuance and domain binding.

Core Features:
- 🚀 Auto-install Docker & Docker Compose Plugin (no manual environment configuration);
- 🔒 Auto-apply for free HTTPS certificates from Let's Encrypt (90-day validity + auto-renewal);
- 🌐 Custom domain binding with forced HTTP-to-HTTPS redirect for secure access;
- 📦 Persistent data storage (n8n workflows won’t be lost) + automatic backup of old configurations;
- ✅ Built-in certificate validation, DEBUG logs, and simplified troubleshooting;
- 👤 Customizable n8n login credentials (ready to use out of the box).

Use Case: Users who want to quickly set up the visual automation tool (n8n) and access it securely via a custom domain (no professional DevOps knowledge required).

## English
```curl -fsSL https://raw.githubusercontent.com/LeonSGP43/n8n-deploy-script-ubuntu2510/refs/heads/main/deploy-n8n-ubuntu2510-EN.sh | bash```

---
## 🔧 n8n + Traefik 一键Unbuntu部署脚本（带证书验证增强版）
这是一个专为小白和开发者设计的自动化部署脚本，可快速在 Linux 服务器（Ubuntu/Debian）上搭建 **n8n 自动化工具** + **Traefik 反向代理** 环境，并自动完成 HTTPS 证书申请与域名绑定。

核心功能：
- 🚀 全自动安装 Docker 及 Compose 插件，无需手动配置环境；
- 🔒 自动向 Let's Encrypt 申请免费 HTTPS 证书，支持 90 天自动续期；
- 🌐 绑定自定义域名，强制 HTTP 转 HTTPS，保障访问安全；
- 📦 数据持久化存储（n8n 流程配置不丢失），旧配置自动备份；
- ✅ 内置证书有效性校验、DEBUG 日志，问题排查更简单；
- 👤 支持自定义 n8n 登录账号密码，开箱即用。

适用场景：需要快速搭建可视化自动化工具（n8n），且希望通过域名安全访问的用户（无需专业运维知识）。
## Chinese 中文版
```curl -fsSL https://raw.githubusercontent.com/LeonSGP43/n8n-deploy-script-ubuntu2510/refs/heads/main/deploy-n8n-ubuntu2510-CN.sh | bash```


