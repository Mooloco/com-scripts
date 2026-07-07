#!/usr/bin/env python3
"""
用法: sudo openresty-le-setup.py <domain> [--email you@example.com] [--webroot DIR]
                                 [--conf-dir DIR] [--conf-file FILE] [--force]
                                 [--dry-run] [--yes]

前提: 域名已经在 OpenResty 里有一个 80 端口的 server{} 块（比如你已有的反代配置），
      且域名已解析到本机、80 端口可以从公网访问到。

流程:
  1. 找到该域名的 conf 文件和顶层 server{} 块。
  2. 若该块还没有 acme-challenge location，插入一个，reload OpenResty。
  3. 若 /etc/letsencrypt/live/<domain> 不存在证书，用 --webroot 方式签发
     （续期方式自动就是 webroot，无需手动改 renewal 配置、无需停服务）。
  4. 把该 server{} 块拆成: 80 端口只做 acme-challenge + 301 跳转到 https；
     443 端口新增一个 server{}，带上 ssl_certificate 等指令，其余内容照抄原样。
  5. 测试并 reload OpenResty。

每一步写文件前都会先备份 .bak，写之前打印 diff，非 --yes 时会交互确认。
"""
import argparse
import difflib
import os
import re
import shutil
import subprocess
import sys
import datetime

DEFAULT_CONF_DIRS = [
    "/etc/openresty/conf.d",
    "/usr/local/openresty/nginx/conf/conf.d",
    "/usr/local/openresty/nginx/conf/vhost",
    "/etc/nginx/conf.d",
]
LE_LIVE_ROOT = "/etc/letsencrypt/live"
NGINX_MAIN_CONF_CANDIDATES = [
    "/usr/local/openresty/nginx/conf/nginx.conf",
    "/etc/openresty/nginx.conf",
    "/etc/nginx/nginx.conf",
]


def find_openresty_bin():
    for cand in ["openresty", "/usr/local/openresty/bin/openresty",
                 "/usr/local/openresty/nginx/sbin/nginx", "nginx"]:
        found = shutil.which(cand) if not os.path.isabs(cand) else (cand if os.path.exists(cand) else None)
        if found:
            return found
    return None


def test_and_reload(dry_run):
    if dry_run:
        print("[dry-run] 跳过配置测试/reload")
        return True
    binp = find_openresty_bin()
    if not binp:
        print("警告: 找不到 openresty/nginx 可执行文件，跳过自动测试和 reload，请手动执行。")
        return True
    test = subprocess.run([binp, "-t"], capture_output=True, text=True)
    print(test.stdout, test.stderr)
    if test.returncode != 0:
        return False
    reload_ok = subprocess.run(["systemctl", "reload", "openresty"])
    if reload_ok.returncode != 0:
        subprocess.run([binp, "-s", "reload"])
    return True


def detect_nginx_user():
    for path in NGINX_MAIN_CONF_CANDIDATES:
        if os.path.exists(path):
            text = open(path, encoding="utf-8", errors="ignore").read()
            m = re.search(r"^\s*user\s+(\S+)", text, re.MULTILINE)
            if m:
                return m.group(1)
    return None


def ensure_webroot(webroot, dry_run):
    challenge_dir = os.path.join(webroot, ".well-known", "acme-challenge")
    if os.path.isdir(challenge_dir):
        return
    print(f"创建 webroot 目录: {challenge_dir}")
    if dry_run:
        return
    os.makedirs(challenge_dir, exist_ok=True)
    user = detect_nginx_user()
    if user:
        try:
            shutil.chown(webroot, user=user)
            for root, dirs, files in os.walk(webroot):
                for d in dirs:
                    shutil.chown(os.path.join(root, d), user=user)
        except LookupError:
            print(f"警告: 找不到系统用户 {user}，跳过 chown，请手动确认 OpenResty 能读取 {webroot}")
    else:
        print(f"警告: 未能从 nginx.conf 检测到运行用户，请手动确认 OpenResty 能读取 {webroot}")


def strip_comments(text):
    return re.sub(r"#[^\n]*", "", text)


def find_conf_file(domain, conf_dirs):
    name_re = re.compile(r"server_name[^;]*\b" + re.escape(domain) + r"\b[^;]*;")
    matches = []
    for d in conf_dirs:
        if not os.path.isdir(d):
            continue
        for root, _, files in os.walk(d):
            for f in files:
                if not f.endswith(".conf"):
                    continue
                path = os.path.join(root, f)
                try:
                    text = open(path, encoding="utf-8").read()
                except Exception:
                    continue
                if name_re.search(text):
                    matches.append(path)
    return matches


def find_top_level_server_blocks(text):
    depth = 0
    block_start = None
    blocks = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "{":
            if depth == 0:
                head = text[:i].rstrip()
                if re.search(r"\bserver\s*$", head):
                    block_start = head.rfind("server")
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and block_start is not None:
                blocks.append((block_start, i + 1))
                block_start = None
        i += 1
    return blocks


def locate_domain_block(text, domain):
    stripped = strip_comments(text)
    blocks = find_top_level_server_blocks(stripped)
    name_re = re.compile(r"server_name[^;]*\b" + re.escape(domain) + r"\b[^;]*;")
    for start, end in blocks:
        if name_re.search(stripped[start:end]):
            return start, end
    return None


def write_with_confirmation(conf_path, original_text, new_text, dry_run, auto_yes, label):
    diff = "".join(difflib.unified_diff(
        original_text.splitlines(keepends=True),
        new_text.splitlines(keepends=True),
        fromfile=conf_path, tofile=conf_path + " (new)",
    ))
    if not diff:
        print(f"[{label}] 无需改动。")
        return True
    print(f"--- {label} ---")
    print(diff)
    if dry_run:
        print("[dry-run] 未写入文件。")
        return False
    if not auto_yes:
        ans = input(f"确认写入以上修改（{label}）并 reload OpenResty? [y/N] ")
        if ans.strip().lower() != "y":
            print("已取消。")
            return False
    backup = conf_path + "." + datetime.datetime.now().strftime("%Y%m%d%H%M%S") + ".bak"
    shutil.copy2(conf_path, backup)
    print(f"已备份到 {backup}")
    with open(conf_path, "w", encoding="utf-8") as f:
        f.write(new_text)
    if not test_and_reload(dry_run):
        print("配置测试失败，回滚...")
        shutil.copy2(backup, conf_path)
        sys.exit(1)
    return True


def insert_acme_location(block_text, webroot):
    if "/.well-known/acme-challenge/" in block_text:
        return block_text
    acme_location = (
        "\n    location ^~ /.well-known/acme-challenge/ {\n"
        f"        root {webroot};\n"
        "        default_type \"text/plain\";\n"
        "    }\n"
    )
    brace_idx = block_text.index("{")
    return block_text[: brace_idx + 1] + acme_location + block_text[brace_idx + 1:]


def request_certificate(domain, webroot, email, dry_run):
    cert_dir = os.path.join(LE_LIVE_ROOT, domain)
    if os.path.isdir(cert_dir):
        print(f"证书已存在: {cert_dir}，跳过签发。")
        return cert_dir
    cmd = ["certbot", "certonly", "--non-interactive", "--agree-tos",
           "--webroot", "-w", webroot, "-d", domain]
    cmd += ["-m", email] if email else ["--register-unsafely-without-email"]
    print("执行:", " ".join(cmd))
    if dry_run:
        print("[dry-run] 跳过实际签发。")
        return cert_dir
    result = subprocess.run(cmd)
    if result.returncode != 0 or not os.path.isdir(cert_dir):
        print("证书签发失败，请检查上面 certbot 的输出（常见原因：DNS 未解析到本机、80 端口未对公网开放）。")
        sys.exit(1)
    return cert_dir


def build_https_block(block_text, cert_dir):
    fullchain = os.path.join(cert_dir, "fullchain.pem")
    privkey = os.path.join(cert_dir, "privkey.pem")

    def fix_listen(m):
        line = re.sub(r"\bdefault_server\b", "", m.group(0))
        m2 = re.search(r"listen\s+(\[[^\]]+\]|[\d.]+)?:?80\b", line)
        if not m2:
            return line
        addr = m2.group(1) or ""
        repl = f"listen {addr}:443 ssl http2;" if addr else "listen 443 ssl http2;"
        return re.sub(r"listen\s+(\[[^\]]+\]|[\d.]+)?:?80\b[^;]*;", repl, line)

    new_block = re.sub(r"listen\s+[^;]*;", fix_listen, block_text)
    # 443 块不需要 acme-challenge location，去掉（挑战始终走明文 80）
    new_block = re.sub(
        r"\n?\s*location \^~ /\.well-known/acme-challenge/\s*\{[^}]*\}\n?",
        "\n", new_block,
    )
    ssl_lines = (
        f"    ssl_certificate     {fullchain};\n"
        f"    ssl_certificate_key {privkey};\n"
        "    ssl_protocols TLSv1.2 TLSv1.3;\n"
        "    ssl_ciphers HIGH:!aNULL:!MD5;\n"
    )
    brace_idx = new_block.index("{")
    return new_block[: brace_idx + 1] + "\n" + ssl_lines + new_block[brace_idx + 1:]


def build_redirect_block(block_text, webroot):
    listen_lines = re.findall(r"^\s*listen\s+[^;]*;", block_text, re.MULTILINE)
    server_name_lines = re.findall(r"^\s*server_name\s+[^;]*;", block_text, re.MULTILINE)
    body = "\n".join(f"    {l.strip()}" for l in listen_lines + server_name_lines)
    acme_location = (
        "    location ^~ /.well-known/acme-challenge/ {\n"
        f"        root {webroot};\n"
        "        default_type \"text/plain\";\n"
        "    }\n"
    )
    return f"server {{\n{body}\n\n{acme_location}\n    return 301 https://$host$request_uri;\n}}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("domain")
    ap.add_argument("--email")
    ap.add_argument("--webroot", default="/var/www/_letsencrypt")
    ap.add_argument("--conf-dir", action="append", default=[])
    ap.add_argument("--conf-file")
    ap.add_argument("--force", action="store_true", help="即使检测到已有 443 也继续处理")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--yes", action="store_true")
    args = ap.parse_args()

    if args.conf_file:
        conf_files = [args.conf_file]
    else:
        conf_files = find_conf_file(args.domain, args.conf_dir or DEFAULT_CONF_DIRS)
    if not conf_files:
        print(f"错误: 没找到包含 server_name {args.domain} 的 conf 文件，请先手工加好 80 端口的反代配置，或用 --conf-file 指定。")
        sys.exit(1)
    if len(conf_files) > 1:
        print("找到多个匹配文件，请用 --conf-file 指定：")
        for f in conf_files:
            print(" ", f)
        sys.exit(1)
    conf_path = conf_files[0]

    # 第一阶段：确保 webroot 存在 + 80 块里有 acme-challenge location
    ensure_webroot(args.webroot, args.dry_run)

    original_text = open(conf_path, encoding="utf-8").read()
    span = locate_domain_block(original_text, args.domain)
    if not span:
        print(f"错误: 在 {conf_path} 里没找到 {args.domain} 对应的 server{{}} 块。")
        sys.exit(1)
    start, end = span
    block_text = original_text[start:end]

    if re.search(r"listen\s+[^;]*443", block_text) and not args.force:
        print(f"{conf_path} 中该 server 块已经监听 443，判断为已配置过 HTTPS，跳过（用 --force 强制继续）。")
        sys.exit(0)

    patched_block = insert_acme_location(block_text, args.webroot)
    new_text = original_text[:start] + patched_block + original_text[end:]
    write_with_confirmation(conf_path, original_text, new_text, args.dry_run, args.yes,
                             "阶段1: 插入 acme-challenge location")

    # 第二阶段：签发证书（若已存在会自动跳过）
    cert_dir = request_certificate(args.domain, args.webroot, args.email, args.dry_run)

    if args.dry_run:
        print("[dry-run] 跳过 80/443 拆分（需要真实证书路径）。")
        return

    # 第三阶段：拆分成 80 跳转 + 443 ssl
    current_text = open(conf_path, encoding="utf-8").read()
    span = locate_domain_block(current_text, args.domain)
    start, end = span
    block_text = current_text[start:end]

    https_block = build_https_block(block_text, cert_dir)
    redirect_block = build_redirect_block(block_text, args.webroot)
    final_text = current_text[:start] + redirect_block + "\n\n" + https_block + current_text[end:]

    write_with_confirmation(conf_path, current_text, final_text, args.dry_run, args.yes,
                             "阶段2: 拆分为 80 跳转 + 443 ssl")
    print("完成。证书续期方式已是 webroot，systemctl status certbot.timer 会自动续期，无需额外 hook。")


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("请用 root/sudo 运行。")
        sys.exit(1)
    main()
