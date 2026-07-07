# openresty-le-setup.py

给「编译安装的 OpenResty」自动配 Let's Encrypt HTTPS 的一体化脚本。

OpenResty 不像官方 nginx 那样有 certbot 插件能自动改配置、自动跳转 HTTPS，
这个脚本把「建 webroot 目录 → 插入 acme-challenge location → reload → certbot webroot 签发证书
→ 把 80 端口块拆成跳转 + 443 端口 SSL 块 → 再次 reload」这一整套操作串成一条命令。

## 功能

- 自动定位指定域名在 OpenResty 配置里对应的 `server{}` 块（按 `server_name` 搜索 `conf-dir`/`conf-file`）。
- 自动创建并授权 webroot 目录（`/var/www/_letsencrypt` 默认），供 certbot `--webroot` 方式验证使用。
- 自动在该域名的 80 端口块里插入 `/.well-known/acme-challenge/` location（若已存在则跳过，幂等）。
- 若证书不存在，自动执行 `certbot certonly --webroot ...` 签发（已存在则跳过，不会重复申请）。
- 用 `--webroot` 签发后，证书的续期方式自动就是 `webroot`，**不需要停 OpenResty、不需要额外 pre/post hook**，`certbot.timer` 到期自动续期即可。
- 自动把原来的 80 端口反代块拆分成两块：
  - 80 端口：保留 `listen`/`server_name` + acme-challenge location + 301 跳转到 https。
  - 443 端口：复制原有内容（含反代 location 等），补上 `ssl_certificate`/`ssl_certificate_key` 等指令。
- 每次写文件前都会：打印 unified diff、非 `--yes` 时交互确认、写入前自动备份 `.bak`、写入后跑 `openresty -t` 测试，失败自动回滚，成功才 reload。
- 支持 `--dry-run` 全程预览，不实际签发证书、不写文件。

## 前提条件

1. 域名已经在 OpenResty 里有一个**单纯的 80 端口 server{} 块**（比如已有的反代配置），且该 conf 文件里域名对应的是**顶层、不嵌套**的 `server{}` 块。
2. 域名已经解析到本机公网 IP，且防火墙/安全组已放行 80 端口（certbot webroot 验证走明文 HTTP）。
3. Python 3（certbot 本身依赖它，一般已装好）、certbot 已安装。

## 用法

```bash
# 1. 如果之前用 --standalone 签发过，先删掉旧证书（会一并清掉旧的续期配置）
certbot delete --cert-name <domain>

# 2. dry-run 预览会做的改动（不会真正签发证书、不会写文件）
sudo python3 openresty-le-setup.py <domain> \
  --email you@example.com \
  --conf-file /path/to/domain.conf \
  --dry-run

# 3. 确认无误后正式执行
sudo python3 openresty-le-setup.py <domain> \
  --email you@example.com \
  --conf-file /path/to/domain.conf
```

不加 `--conf-file` 时，脚本会在下列默认目录里按 `server_name` 自动搜索匹配的 conf 文件：

```
/etc/openresty/conf.d
/usr/local/openresty/nginx/conf/conf.d
/usr/local/openresty/nginx/conf/vhost
/etc/nginx/conf.d
```

也可以用多个 `--conf-dir DIR` 指定额外搜索路径。

## 参数说明

| 参数 | 说明 |
|---|---|
| `domain`（必填） | 要处理的域名 |
| `--email` | certbot 注册邮箱；不填则用 `--register-unsafely-without-email` |
| `--webroot` | ACME 验证用的 webroot 目录，默认 `/var/www/_letsencrypt` |
| `--conf-dir` | 搜索 conf 文件的目录，可重复传多个 |
| `--conf-file` | 直接指定要改的 conf 文件，跳过自动搜索 |
| `--force` | 即使检测到该 server 块已经监听 443，也继续处理 |
| `--dry-run` | 只打印将要做的改动和将要执行的 certbot 命令，不实际写入/签发 |
| `--yes` | 跳过交互确认，直接写入（仍会先备份） |

## 执行流程

1. **阶段 0**：确保 `--webroot` 目录存在，并尝试根据 `nginx.conf` 里的 `user` 指令自动 `chown` 给 OpenResty 运行用户。
2. **阶段 1**：定位域名对应的 `server{}` 块，若还没有 acme-challenge location 就插入，写文件、测试、reload。
3. **签发证书**：若 `/etc/letsencrypt/live/<domain>` 不存在，执行 `certbot certonly --webroot -w <webroot> -d <domain>`。
4. **阶段 2**：重新读取该 server 块，拆分成「80 跳转」+「443 ssl」两块，写文件、测试、reload。

## 注意事项

- 若该 server 块已经监听 443（判断为已配置过 HTTPS），脚本默认直接跳过，加 `--force` 可强制重新处理。
- `--dry-run` 模式下阶段 2 会被整体跳过（因为需要真实签发出来的证书路径），这是设计如此，不是 bug。
- 脚本假设「一个域名 = 一个未嵌套的顶层 `server{}` 块」。如果一个 conf 文件里塞了多个 `server_name` 共用一块，或者用 `include` 拆得很碎，生成的 diff 可能不完全符合预期，**务必先跑 `--dry-run` 人工核对**再正式执行。
- 若运行时提示"未能从 nginx.conf 检测到运行用户"，说明脚本没找到你编译安装时的主配置文件路径，需要手动确认/`chown` `webroot` 目录给 OpenResty worker 的运行用户，否则 certbot 验证可能因权限问题失败。
- 每次写入都会生成同目录下的 `xxx.conf.<时间戳>.bak` 备份，出问题可以直接拿它覆盖回去手动排查。

## 彻底删除某个域名的证书 / 取消续期

certbot 没有单独的"取消续期"命令，直接删除证书 lineage 即可，会一并清掉对应的续期配置：

```bash
certbot delete --cert-name <domain>
```

会删除：
- `/etc/letsencrypt/live/<domain>/`
- `/etc/letsencrypt/archive/<domain>/`
- `/etc/letsencrypt/renewal/<domain>.conf`

全局的 `certbot.timer` 不用动，它以后不会再碰这个已删除的域名。
