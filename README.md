# Caddy Custom

官方 Caddy + Cloudflare DNS 插件，由 GitHub Actions 构建并发布至 GHCR。

- 镜像：`ghcr.io/1910965005/caddy-custom:latest`
- 架构：`linux/amd64`、`linux/arm64`
- Caddy 输入版本：`2.11.9`（Dockerfile 中的 CADDY_TAG）
- Cloudflare 插件提交：`a8737d095ad5a48ca031cea6ab704057dbc2d250`
- 插件模块：`dns.providers.cloudflare`

## 构建方式

官方 `caddy:<version>-builder` 内运行 xcaddy，将二进制复制到官方
`caddy:<version>-alpine`。编译在 runner 本机架构进行，Go 交叉编译目标架构，
CGO 关闭；目标镜像通过 QEMU 执行版本与插件检查。
本项目是自定义衍生镜像，并非 Caddy 官方发布产物。

## 发布和验证

提交 Dockerfile、配置、测试脚本或工作流到 main 自动构建。
也可在 [Actions](https://github.com/1910965005/caddy-custom/actions) 中选择
Build and publish Caddy → Run workflow → main。

工作流先构建 AMD64 测试镜像，检查插件、配置、HTTP 响应，
通过后才推送 AMD64/ARM64 多架构镜像。发布后按 digest 拉取并运行两种架构的模块检查。
PR 只测试、不登录或发布。所有第三方 Actions 固定完整提交 SHA。

标签：
- latest：最近一次发布。
- build-运行编号-尝试编号：对应一次构建。
- digest：精确锁定产物，见每次成功运行的 Summary。

CI 使用自动提供的 GITHUB_TOKEN，权限为 contents:read、packages:write。
公开插件的构建不需要 Cloudflare Token。

## 第一次拉取

GHCR 包首次发布可能是 Private。到个人主页 Packages → caddy-custom →
Package settings 检查可见性；需要匿名拉取则设为 Public。
仓库 Public 不代表镜像包 Public。

私有镜像需先使用至少包含 read:packages 的 PAT classic 登录：
```bash
read -rsp 'GitHub PAT: ' CR_PAT
echo
printf '%s' "$CR_PAT" | docker login ghcr.io -u 1910965005 --password-stdin
unset CR_PAT
```

```bash
docker pull ghcr.io/1910965005/caddy-custom:latest
docker run --rm ghcr.io/1910965005/caddy-custom:latest caddy version
docker run --rm ghcr.io/1910965005/caddy-custom:latest caddy list-modules
docker buildx imagetools inspect ghcr.io/1910965005/caddy-custom:latest
```

## 部署：先测试 HTTP

服务器需已安装 Docker Engine、Compose 插件，80/443 未被其他服务占用。

```bash
git clone https://github.com/1910965005/caddy-custom.git
cd caddy-custom
cp .env.example .env
chmod 600 .env
docker compose pull
docker compose up -d
curl http://127.0.0.1
docker compose logs --tail=100 caddy
```

默认配置只提供 HTTP 测试响应，不申请证书。/data 与 /config 使用命名卷持久化。
生产配置通过 conf 目录挂载，不打包进镜像。

## 启用 Cloudflare DNS 验证和 HTTPS

1. 域名 DNS Zone 由 Cloudflare 管理。
2. 创建 API Token：目标 Zone 的 Zone:Read、DNS:Edit。
3. 在服务器 .env 填写 CLOUDFLARE_API_TOKEN。不要提交 Token。
4. 将 examples/Caddyfile.cloudflare 复制为 conf/Caddyfile。
5. 修改其中邮箱和 example.com 为真实值。
6. 为公网访问设置正确 DNS 记录、防火墙与 80/443 端口。
7. 执行：

```bash
docker compose up -d --force-recreate caddy
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose logs -f caddy
```

DNS-01 通过 TXT 记录验证域名。公网访问能否成功还取决于 DNS、路由和防火墙。
CI 不使用你的真实 DNS 凭据，不测试真实证书签发。

如需反向代理，将 respond 改为 `reverse_proxy app:3000`；
app 应为同一 Docker 网络里的真实服务名。容器内 localhost 指向自身。

仅编辑 Caddyfile 后：
```bash
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```
修改 .env 后需要重新创建容器以更新环境变量。

## 更新与回退

修改 Dockerfile 的 CADDY_TAG 或 CLOUDFLARE_REF，然后提交到 main。
Dependabot 每周检查 Docker 基础镜像及 Actions 更新；
插件提交需要手动更新。没有自动合并或自动部署服务器。

```bash
docker compose pull caddy
docker compose up -d caddy
```

restart 不会应用新镜像。回退时把 .env 的 CADDY_IMAGE 改为旧 build 标签或 digest，
再 pull 与 up -d。不要使用 down -v 删除证书数据卷。

当前固定核心版本、插件提交、Actions SHA；基础镜像标签及传递依赖仍可能变化，
这并非逐字节可复现构建。生产部署用镜像 digest 锁定实际产物。

## 增减插件

Dockerfile 的 xcaddy 命令每个插件增加一条 `--with Go路径@版本或提交`。
同步修改 Dockerfile 和 scripts/smoke-test.sh 中的模块断言。
模块 ID 与 Go 路径不同，以插件 README 为准。
当前关闭 CGO；需要 C 库的其他插件必须另行调整构建与运行依赖。

## 常见问题

| 现象 | 检查 |
| --- | --- |
| GHCR 推送 403 | packages:write、包设置 Manage Actions access、组织策略 |
| 拉取 unauthorized | 包可见性、PAT 的 read:packages、账号权限 |
| 模块不存在 | 是否拉取并重建容器；插件检查是否通过 |
| 版本断言失败 | 插件依赖是否升级 Caddy 核心；调整兼容版本 |
| DNS 验证失败 | Token Zone 权限、环境变量、TXT 记录与 DNS 查询 |
| ARM64 不支持 | 确认使用本仓库多架构镜像和正确标签 |

## 官方参考

- [官方 Caddy 镜像](https://hub.docker.com/_/caddy)
- [xcaddy](https://github.com/caddyserver/xcaddy)
- [Cloudflare 插件](https://github.com/caddy-dns/cloudflare)
- [GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
