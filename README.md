# 🔧 n8n + Traefik 一键部署脚本（Ubuntu/Debian 专属，证书验证增强版）
A user-friendly automation script designed for beginners and developers to quickly set up **n8n (automation tool)** + **Traefik (reverse proxy)** on Ubuntu/Debian servers, with automatic HTTPS certificate issuance and domain binding.

## 核心功能 | Core Features
- 🚀 全自动安装 Docker 及 Compose 插件，无需手动配置环境 | Auto-install Docker & Docker Compose Plugin (no manual environment setup)
- 🔒 自动申请 Let's Encrypt 免费 HTTPS 证书（90天有效期+自动续期）| Auto-apply for free Let's Encrypt HTTPS certificates (90-day validity + auto-renewal)
- 🌐 支持自定义域名绑定，强制 HTTP 转 HTTPS，访问更安全 | Custom domain binding with forced HTTP-to-HTTPS redirect for secure access
- 📦 数据持久化存储（n8n 流程配置不丢失），兼容无旧配置场景 | Persistent data storage (n8n workflows preserved) + compatibility with fresh servers
- ✅ 内置证书有效性校验、DEBUG 日志，问题排查更简单 | Built-in certificate validation, DEBUG logs, and simplified troubleshooting
- 👤 自定义 n8n 登录账号密码，开箱即用 | Customizable n8n login credentials (ready to use out of the box)

## 适用场景 | Use Case
需要快速搭建可视化自动化工具（n8n），且希望通过自定义域名安全访问的用户（无需专业运维知识）。  
Users who want to quickly set up the visual automation tool (n8n) and access it securely via a custom domain (no professional DevOps knowledge required).

---

## 快速部署命令 | Quick Deployment Commands
### 中文版（中文提示）| Chinese Version (Chinese Prompts)
```bash
# 无残留部署（兼容全新服务器，无需前置文件）
rm -rf ~/n8n-docker deploy-n8n-CN.sh && curl -fsSL https://raw.githubusercontent.com/LeonSGP43/n8n-deploy-script-ubuntu2510/refs/heads/main/deploy-n8n-ubuntu2510-CN.sh -o deploy-n8n-CN.sh && chmod +x deploy-n8n-CN.sh && sed -i 's/set -euo pipefail/set -eo pipefail/' deploy-n8n-CN.sh && sed -i '/备份旧配置/d' deploy-n8n-CN.sh && ./deploy-n8n-CN.sh
```

### 英文版（English Prompts）
```bash
# Clean deployment (compatible with fresh servers, no preconditions)
rm -rf ~/n8n-docker deploy-n8n-EN.sh && curl -fsSL https://raw.githubusercontent.com/LeonSGP43/n8n-deploy-script-ubuntu2510/refs/heads/main/deploy-n8n-ubuntu2510-EN.sh -o deploy-n8n-EN.sh && chmod +x deploy-n8n-EN.sh && sed -i 's/set -euo pipefail/set -eo pipefail/' deploy-n8n-EN.sh && sed -i '/Backing up old configuration files/d' deploy-n8n-EN.sh && ./deploy-n8n-EN.sh
```

---

## 关键检查命令 | Key Verification Commands
部署后执行以下命令，快速验证服务状态、证书有效性等（复制即可执行）：

### 1. 检查服务是否正常运行 | Check Service Status
```bash
cd ~/n8n-docker && docker compose ps
```
- 正常结果：`n8n-docker-n8n-1` 和 `n8n-docker-traefik-1` 状态均为 `Up`（运行中）

### 2. 验证 HTTPS 证书是否生效 | Verify HTTPS Certificate
```bash
cd ~/n8n-docker && docker compose logs traefik | grep -i "Certificates obtained"
```
- 正常结果：显示 `Certificates obtained for domains [你的域名]`，证明证书申请成功

### 3. 查看证书详细信息（有效期/签发机构）| Check Certificate Details
```bash
cd ~/n8n-docker && docker exec -it n8n-docker-traefik-1 sh -c 'cat /letsencrypt/acme.json | jq -r .Certificates[0].Certificate | base64 -d | openssl x509 -text -noout | grep -E "Issuer|Not After|Subject"'
```

### 4. 测试域名访问连通性 | Test Domain Connectivity
```bash
# 替换为你的域名（替换成你的实际域名）
curl -v https://你的域名/
```
- 正常结果：显示 `SSL certificate verify ok`（SSL 证书验证通过）

### 5. 重启服务（如需）| Restart Services (If Needed)
```bash
cd ~/n8n-docker && docker compose restart
```

### 6. 查看错误日志（排查问题用）| Check Error Logs (For Troubleshooting)
```bash
# 查看 Traefik 证书相关日志
cd ~/n8n-docker && docker compose logs traefik | grep -iE "acme|cert|error"

# 查看 n8n 运行日志
cd ~/n8n-docker && docker compose logs n8n | grep -i error
```

---

## 重要说明 | Important Notes
1. 命令兼容性：支持 Ubuntu 20.04+/Debian 11+，无需前置文件，全新服务器可直接运行，不会因“文件不存在”报错；
2. 前置条件：服务器需开放 80/443 端口（安全组配置），自定义域名需完成 A 记录解析（指向服务器公网 IP）；
3. 数据备份：如需保留旧流程数据，部署前执行 `cp -r ~/n8n-docker/n8n_data ~/n8n_data_backup`，部署后恢复即可；
4. 证书续期：证书有效期 90 天，Traefik 自动续期，无需手动操作。

