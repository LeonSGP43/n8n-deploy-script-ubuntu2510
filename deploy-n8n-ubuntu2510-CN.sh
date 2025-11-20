#!/bin/bash

set -euo pipefail

# 清除重复的启动命令和冗余配置，优化兼容性，新增证书校验与问题排查能力
echo "====== 🚀 n8n + Traefik 稳定部署脚本（带证书验证增强版） ======"

# 检查依赖工具（jq用于解析acme.json，openssl用于证书校验）
check_dependencies() {
    local missing=()
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    if ! command -v openssl &> /dev/null; then
        missing+=("openssl")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "🔧 正在安装缺失依赖：${missing[*]}"
        apt-get update &> /dev/null
        apt-get install -y "${missing[@]}" &> /dev/null
    fi
}

# 获取用户输入（添加格式校验提示）
read -p "🌐 请输入纯域名（例：n8n.example.com，无需加https://）: " DOMAIN
read -p "📧 请输入邮箱（用于Let's Encrypt证书申请）: " EMAIL
read -p "👤 请输入n8n登录用户名: " N8N_USER
read -p "🔒 请输入n8n登录密码（建议8位以上）: " N8N_PASS

# 安装依赖工具
check_dependencies

# 安装Docker（如未安装，使用官方脚本）
if ! command -v docker &> /dev/null; then
    echo "🔧 正在安装Docker（请稍候）..."
    curl -fsSL https://get.docker.com | bash
    # 启动Docker服务并设置开机自启
    systemctl enable --now docker
fi

# 安装Docker Compose Plugin（适配Docker 20+版本）
if ! docker compose version &> /dev/null; then
    echo "🔧 正在安装Docker Compose插件..."
    apt-get update &> /dev/null
    apt-get install -y docker-compose-plugin &> /dev/null
fi

# 创建工作目录并进入（避免目录冲突）
mkdir -p ~/n8n-docker && cd ~/n8n-docker

# 清理旧配置（避免残留文件影响，保留备份选项）
if [ -f docker-compose.yml ] || [ -d traefik ]; then
    echo "📦 正在备份旧配置文件..."
    mv -f docker-compose.yml docker-compose.old.$(date +%Y%m%d%H%M%S) 2>/dev/null
    mv -f traefik traefik.old.$(date +%Y%m%d%H%M%S) 2>/dev/null
fi

# 创建Traefik相关目录和证书文件（权限关键）
mkdir -p traefik
touch traefik/acme.json
chmod 600 traefik/acme.json  # 证书文件必须600权限，否则申请失败
chown root:root traefik/acme.json  # 确保root权限，避免权限异常

# 创建n8n数据目录（适配容器用户权限）
mkdir -p n8n_data
chown -R 1000:1000 n8n_data  # n8n容器使用node用户（UID=1000）
chmod -R 700 n8n_data

# 写入Docker Compose配置（新增DEBUG日志，优化证书配置）
cat <<EOF > docker-compose.yml
version: '3.8'  # 明确版本，提高兼容性

services:
  traefik:
    image: traefik:v2.11  # 稳定版，兼容证书申请流程
    restart: always
    ports:
      - "80:80"   # HTTP端口（用于证书HTTP-01验证）
      - "443:443" # HTTPS端口（实际访问）
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro  # 只读权限，更安全
      - ./traefik/acme.json:/letsencrypt/acme.json    # 证书存储路径
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # 证书解析器配置
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      # 开启DEBUG日志，便于排查证书问题（生产可改为INFO）
      - "--log.level=DEBUG"
      - "--accesslog=true"  # 开启访问日志
    networks:
      - n8n-network

  n8n:
    image: n8nio/n8n:latest  # 使用n8n最新稳定版
    restart: always
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN/
      - VUE_APP_URL_BASE_API=https://$DOMAIN/
      - NODE_ENV=production
      - TZ=Asia/Shanghai  # 时区配置，避免时间错乱
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      # 强制HTTP跳转到HTTPS，提升安全性
      - "traefik.http.middlewares.n8n-redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.n8n-http.entrypoints=web"
      - "traefik.http.routers.n8n-http.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.n8n-http.middlewares=n8n-redirect"
    volumes:
      - ./n8n_data:/home/node/.n8n
    networks:
      - n8n-network

networks:
  n8n-network:  # 独立网络，隔离性更好
    name: n8n-network
EOF

# 启动服务
echo "🚀 正在启动n8n和Traefik服务..."
docker compose up -d

# 证书验证函数（解析acme.json并校验证书有效性）
verify_certificate() {
    local acme_path="./traefik/acme.json"
    local max_wait=120  # 最大等待2分钟
    local wait_count=0
    local cert_data

    echo -e "\n🔍 正在验证证书申请状态（可能需要30秒）..."

    # 等待证书生成
    while [ $wait_count -lt $max_wait ]; do
        if [ -s "$acme_path" ] && jq '.Certificates | length > 0' "$acme_path" &> /dev/null; then
            cert_data=$(jq -r '.Certificates[0].Certificate' "$acme_path")
            if [ "$cert_data" != "null" ] && [ -n "$cert_data" ]; then
                break
            fi
        fi
        sleep 2
        wait_count=$((wait_count + 2))
        echo -n "."
    done

    if [ $wait_count -ge $max_wait ]; then
        echo -e "\n⚠️  证书申请超时！请执行以下命令查看日志排查："
        echo "docker logs -f traefik | grep -i acme"
        return 1
    fi

    # 解码并校验证书
    echo -e "\n✅ 证书已生成，正在校验详情..."
    echo "$cert_data" | base64 -d | openssl x509 -text -noout > ./traefik/cert_details.txt

    # 提取关键信息
    local issuer=$(grep "Issuer:" ./traefik/cert_details.txt | head -n1 | awk -F: '{print $2-}' | xargs)
    local not_after=$(grep "Not After :" ./traefik/cert_details.txt | awk -F: '{print $2-}' | xargs)
    local subject=$(grep "Subject:" ./traefik/cert_details.txt | head -n1 | awk -F: '{print $2-}' | xargs)

    echo -e "\n📜 证书校验结果："
    echo "签发机构: $issuer"
    echo "有效期至: $not_after"
    echo "绑定域名: $subject"

    # 清理临时文件
    rm -f ./traefik/cert_details.txt
}

# 执行证书验证
verify_certificate

# 部署完成提示（补充证书问题排查方案）
echo -e "\n🎉 部署成功！"
echo "👉 访问地址：https://$DOMAIN"
echo "🔐 登录账号：$N8N_USER"
echo "🔑 登录密码：$N8N_PASS"
echo "📁 项目目录：~/n8n-docker"
echo -e "\n⚠️  关键操作与问题排查："
echo "1. 证书验证命令（手动校验时使用）："
echo "   docker exec -it traefik sh -c 'cat /letsencrypt/acme.json | jq -r .Certificates[0].Certificate | base64 -d | openssl x509 -text -noout'"
echo "2. 查看Traefik详细日志（排查证书问题）："
echo "   docker logs -f traefik | grep -i 'acme\|cert\|tls'"
echo "3. 证书过期预警：证书有效期90天，到期前会自动续期"
echo "4. 若显示证书有效但访问异常，清除浏览器缓存或检查域名解析是否生效"
echo "5. 重置证书：删除traefik/acme.json后重启服务即可重新申请"