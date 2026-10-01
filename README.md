# Caddy custom：Cloudflare DNS + Layer 4

为 `1910965005/caddy-custom` 准备的自定义 Caddy Docker 项目。GitHub Actions 编译并发布镜像，VPS 只负责拉取和运行。

```text
ghcr.io/1910965005/caddy-custom:latest
```

## 已包含的功能

| 项目 | 配置 |
| --- | --- |
| Caddy 核心 | 每次构建读取官方 `caddy:2` 的具体稳定版本 |
| Cloudflare 模块 | `github.com/caddy-dns/cloudflare`，模块名 `dns.providers.cloudflare` |
| Layer 4 模块 | `github.com/mholt/caddy-l4`，支持 TCP/UDP 代理 |
| 构建平台 | 仅 `linux/amd64`，使用原生 x86_64 runner，无 QEMU |
| 构建方式 | 官方 builder + `xcaddy`，最终镜像基于同版本官方 runtime |
| 自动运行 | `main` 上构建相关文件更新、手动运行、每日 UTC 20:23 / 北京时间 04:23 |
| 运行端口 | `80/tcp`、`443/tcp`、`443/udp` |
| 敏感信息 | VPS 的 `.env` / 容器环境变量；构建无需 Cloudflare Token |
| 配置与证书 | `./config` 只读挂载；`/data` 和 `/config` 使用持久化 volume |

Cloudflare DNS 模块用于 DNS-01 证书验证；它不会自动开启 Cloudflare CDN 代理。L4 模块在镜像中始终可用，默认站点先提供 HTTPS，按后面的步骤启用 L4 端口。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `Dockerfile` | 编译两个模块，并替换官方镜像中的 Caddy 二进制 |
| `.github/workflows/build.yml` | 解析官方版本、构建、验证、发布 GHCR |
| `.github/dependabot.yml` | 每月检查 Actions 依赖更新 |
| `compose.yaml` | VPS 运行配置，只有 `image`，无需本地 `build` |
| `compose.l4.yaml` | 可选的额外 TCP/UDP 端口映射 |
| `config/Caddyfile` | HTTPS、Cloudflare DNS 验证和 HTTP/3 示例 |
| `config/layer4.caddy.example` | 独立端口的 TCP/UDP 代理示例 |
| `.env.example` | VPS 环境变量模板 |
| `.gitignore` / `.dockerignore` | 排除 `.env`、运行数据和无关构建上下文 |
| `scripts/` / `ci/` | 构建输入解析、镜像验证和连接测试 |

## 1. 上传 GitHub 并完成首次构建

目标仓库：<https://github.com/1910965005/caddy-custom>。

如果仓库已经由助手创建并上传，直接到仓库的 **Actions** 查看 `Build and publish Caddy custom`。首次 push 会启动构建，也可以选择 **Run workflow** 手动运行。

如果手动上传：解压压缩包，上传 **`caddy-custom` 目录内的文件和子目录**，让 `Dockerfile` 和 `compose.yaml` 位于仓库根目录。不要只把 ZIP 文件放到仓库中；务必包含 `.github/workflows/build.yml` 等隐藏目录。

也可以在已登录正确 GitHub 账号、已配置 Git 提交身份的电脑上执行：

```bash
cd caddy-custom
gh auth status
gh api user --jq .login
# 确认输出为 1910965005，然后创建空的新仓库并推送。
git init -b main
git add .
git commit -m "Add Caddy Cloudflare DNS and Layer 4 Docker build"
gh repo create 1910965005/caddy-custom --public --source=. --remote=origin --push
```

以上创建命令只用于仓库尚不存在的情况。已有仓库应先检查内容再合并此项目。

Workflow 内使用 GitHub 自动提供的 `GITHUB_TOKEN` 和 `packages: write` 权限，不需要添加 GHCR PAT，也不需要创建 Cloudflare Token 的 GitHub Secret。如果 Actions 被禁用，需要在仓库中先启用 Actions。

镜像构建完会先加载到 runner，检查实际平台、核心版本和三个关键模块，再验证两套部署配置并实际测试 HTTP、HTTPS、TCP 代理和 UDP 代理。全部通过才推送镜像；失败的构建不会替换 `latest`。

HTTP/3 通过 Caddy 的 `h3` 配置和 UDP 端口启用；CI 的连接测试不包含完整 QUIC/HTTP/3 握手，也不验证真实的 Cloudflare Token 或公网证书签发。

### 首次发布后处理 GHCR 可见性

GHCR 新发布的包默认是 **Private**，即使 GitHub 源码仓库是 Public。

要在 VPS 匿名拉取，首次构建成功后，进入 GitHub 个人页面的 **Packages → caddy-custom → Package settings → Change visibility → Public**。这是镜像包的设置，与源码仓库可见性分开。公开包时无需把服务器 `.env` 上传到 GitHub。

如果保留私有镜像，在 VPS 先用具有 `read:packages` 权限的 **PAT (classic)** 登录一次：

```bash
read -rsp 'GHCR Token: ' GHCR_TOKEN
printf '\n'
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u 1910965005 --password-stdin
unset GHCR_TOKEN
```

Docker 会保存登录信息，后续仍可直接 `pull` / `up`。如果出现 `permission_denied: write_package`，检查工作流权限，以及已有同名 Package 是否已关联到当前仓库并授予 Actions 写权限。

## 2. VPS 首次部署

VPS 需要 x86_64 Linux、Docker Engine 和 Docker Compose v2。无需安装 Go 或 xcaddy。防火墙 / 安全组需要允许 `80/tcp`、`443/tcp`、`443/udp`。

首次镜像发布成功、可见性或登录配置完成后：

```bash
git clone https://github.com/1910965005/caddy-custom.git
cd caddy-custom
cp .env.example .env
chmod 600 .env
```

用编辑器修改 `.env`，至少填写：

```dotenv
DOMAIN=你的真实域名
ACME_EMAIL=你的邮箱地址
CF_API_TOKEN=你的Cloudflare_API_Token
CADDY_IMAGE=ghcr.io/1910965005/caddy-custom:latest
```

Cloudflare API Token 使用单 Token 方式，权限为：

- **Zone → Zone → Read**
- **Zone → DNS → Edit**
- Zone Resources 限定为 Caddy 管理的具体域名区域。

使用 API Token，不要使用 Global API Key。域名的权威 DNS 应在对应 Cloudflare 区域；浏览器访问还需要正确的 A/AAAA 记录。DNS-01 验证本身不要求 CA 连接 VPS 的 80 或 443 端口。

启动：

```bash
docker compose pull
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose up -d
docker compose logs --tail=100 -f caddy
```

首次启动后 Caddy 会申请证书。访问 `https://你的真实域名`，默认页面返回 `Caddy custom is running.`。`.env.example` 中的域名和邮箱只是示例，必须替换。

要代理 HTTP 应用，在 `config/Caddyfile` 中将 `respond` 行替换为例如：

```caddyfile
reverse_proxy host.docker.internal:8080
```

`host.docker.internal` 已映射到宿主机网关。如果宿主机应用只监听 `127.0.0.1`，容器通过网关地址无法访问它；应让后端监听容器可达的地址。代理其他容器时，加入同一个 Docker 网络并使用后端服务名。

## 3. 日常升级与配置修改

在项目目录执行：

```bash
docker compose pull && docker compose up -d
```

GitHub 自动构建只更新 GHCR 镜像；VPS 执行这条命令后才更新正在运行的容器。升级镜像会重新创建容器，通常会有短暂重启。

修改 `config/Caddyfile` 后，可以在运行中的容器内重新加载：

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

修改 `.env` 后应执行 `docker compose up -d`，使容器获得新的环境变量；仅 `caddy reload` 不会更改容器环境。

示例使用整个 `config` 目录挂载，编辑器替换配置文件后，容器也能看到新内容。管理 API 保持容器内默认回环地址，没有映射宿主机的 2019 端口。

证书和账户信息持久保存在 `/data` 的 volume，配置状态在 `/config` 的 volume。正常 `pull`、`up -d`、`down` 不删除它们。**`docker compose down -v` 会删除 volume**，需要保留证书时不要使用该命令。迁移已有 Caddy 时，应复用或迁移原有 `/data`，避免把原证书数据遗留在旧 volume 中。

## 4. 启用 Layer 4 TCP / UDP 代理

示例监听 TCP `15432`、UDP `15182`，保留 HTTP 的 80 和 HTTPS / HTTP/3 的 443。

```bash
cp config/layer4.caddy.example config/layer4.caddy
```

在 `config/Caddyfile` 的全局 `{ ... }` 块中取消这一行的注释：

```caddyfile
import /etc/caddy/layer4.caddy
```

在 `.env` 设置容器能够连接的后端：

```dotenv
L4_TCP_UPSTREAM=10.0.0.10:5432
L4_UDP_UPSTREAM=10.0.0.10:51820
L4_TCP_PORT=15432
L4_UDP_PORT=15182
L4_BIND_ADDRESS=0.0.0.0
```

上述 IP 和端口是示例。默认 `L4_BIND_ADDRESS=127.0.0.1` 只供 VPS 本机访问；设为 `0.0.0.0` 才向外部开放。端口开放范围应与你的实际服务访问范围一致。

使用两份 Compose 文件启动：

```bash
docker compose -f compose.yaml -f compose.l4.yaml pull
docker compose -f compose.yaml -f compose.l4.yaml run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose -f compose.yaml -f compose.l4.yaml up -d
```

启用后，以后升级也要保留两份 Compose 参数。想继续使用简短的 `docker compose pull && docker compose up -d`，可在 `.env` 添加：

```dotenv
COMPOSE_FILE=compose.yaml:compose.l4.yaml
```

这项配置适用于本项目的 Linux VPS。此后普通 `docker compose` 命令会合并两份文件。

该示例透明转发原始 TCP / UDP 流量，不自动为后端协议增加 TLS，也不自动给 TCP 客户端增加身份验证。后端已有 TLS 时，TCP 代理可以透传其加密数据。

L4 客户端可以连接服务器 IP 或仅 DNS 的域名记录；普通 Cloudflare 橙云网页代理不负责转发这里任意的 TCP / UDP 端口。

不要在独立 `layer4` 服务和 Caddy HTTP 服务中同时绑定同一个 `443/tcp` 或 `443/udp`。需要共用 443 并按 TLS SNI 分流时，使用 L4 的 `listener_wrappers`；UDP 与 QUIC 的处理需单独设计。本项目提供独立端口示例，实际共用端口方案应结合你的协议、SNI 和后端配置。

## 5. 版本、定期构建与回退

每次成功构建发布三个标签：

| 标签 | 用途 |
| --- | --- |
| `latest` | 最近一次通过验证的构建 |
| `caddy-2.x.y` | 指定 Caddy 核心版本；相同版本重建时模块仍可能更新 |
| `build-运行ID-重试次数` | 某一次具体构建，适合回退 |

Actions 的手动运行参数 `caddy_version` 留空时，工作流读取最新官方 `caddy:2`；填写 `2.x.y` 或 `v2.x.y` 可以选定已有官方镜像的稳定版本。构建时固定 runtime 和同版本 builder 的摘要，并确认编译后的 Caddy 版本完全相同。

`cloudflare_ref` 和 `layer4_ref` 默认 `latest`；可在手动构建时指定版本、提交或分支。如果需要长期固定模块，可以修改 workflow 中两个参数的默认值及 `env` 中的回退值。两处都修改后，定期构建也会使用固定引用。

builder 阶段不会复用上一轮编译结果，以确保定期运行确实重新解析模块引用；Go 缓存用于减少重复下载和编译工作。模块若要求更新的 Caddy 核心或发生配置不兼容，构建会失败并保留已发布的 `latest`，可以在日志中定位并选用兼容的模块引用。

GitHub 的 schedule 可能延迟；公开仓库长时间没有活动时，GitHub 可能停用定期工作流（官方文档规定为 60 天）。发现定期构建停止时，在 Actions 重新启用工作流并手动运行一次。请确认默认分支为 `main`。

查看运行中的版本和模块：

```bash
docker compose exec caddy caddy version
docker compose exec caddy caddy list-modules --versions
docker compose exec caddy cat /usr/share/caddy-custom/go-build.txt
```

需要回退时，把 `.env` 的 `CADDY_IMAGE` 改为先前成功构建的 `build-...` 标签，然后执行 `docker compose pull && docker compose up -d`。具体标签可以在 Actions 构建摘要或 GHCR Package 页面找到。

## 6. 常见问题

- **拉取报 denied / unauthorized**：确认已成功发布该镜像；GHCR Package 已设为 Public，或者 VPS 已登录具有读取权限的 Token。
- **找不到 Cloudflare / layer4 模块**：确认 Compose 使用的是 `ghcr.io/1910965005/caddy-custom`，并在容器中检查 `caddy list-modules --versions`。
- **Cloudflare 验证失败**：检查 Token、区域权限、公共 DNS 解析和 DNS 出站连通性。模块会校验 Token 的格式；不要给 Token 再套一层花括号。
- **L4 后端连接失败**：检查容器视角的 IP / 端口；容器的 `127.0.0.1` 指向容器本身。确认启用了 import、附加 Compose 配置与对应端口。
- **HTTP/3 未使用**：确认 `443/udp` 已开放。浏览器支持、网络路径及前置 CDN 都会影响协商结果；通过 Cloudflare 代理访问时，浏览器看到的 HTTP/3 是与 Cloudflare 边缘建立的连接。

## 官方与模块文档

- [官方 Caddy Docker 镜像和自定义模块构建](https://hub.docker.com/_/caddy)
- [Cloudflare DNS 模块与 Token 权限](https://github.com/caddy-dns/cloudflare)
- [Caddy Layer 4 模块](https://github.com/mholt/caddy-l4)
- [Layer 4 监听端口与 wrappers](https://github.com/mholt/caddy-l4/blob/master/docs/servers.md)
- [Caddy 命令与配置验证](https://caddyserver.com/docs/command-line)
- [GHCR 登录、推送和可见性](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub 工作流触发与定期运行](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Cloudflare 代理端口限制](https://developers.cloudflare.com/fundamentals/reference/network-ports/)
