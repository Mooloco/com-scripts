# docker-image-porter

Docker 镜像离线迁移工具，用于在有外网的机器上下载、打包 Docker 镜像，再拷贝到 OpenWrt 等离线/内网环境导入。

## 功能

- **下载并打包镜像**：输入镜像名（可带 tag，例如 `nginx:1.25`），拉取后用 `docker save` 打包为 `.tar.gz`，包含镜像完整信息（layer、tag、创建时间等）。
- **解压导入镜像**：指定 `.tar.gz` 文件路径，原样 `docker load` 导入。
- **从 compose 文件批量打包**：`-f` 指定 `docker-compose.yml`/`.yaml`，自动解析出其中所有 `image:` 字段，无需手动输入，逐个拉取后打包成一个 `.tar.gz` 文件；导入时用普通菜单的选项2即可一次性导入其中所有镜像。

## 用法

```sh
chmod +x docker-image-porter.sh

# 交互菜单：手动选择「下载打包」或「解压导入」
./docker-image-porter.sh

# 直接解析 compose 文件，拉取并打包其中所有镜像
./docker-image-porter.sh -f docker-compose.yml
```

### 交互菜单

```
1. 下载并打包镜像   → 输入镜像名（如 nginx:latest）→ 生成 <repo>_<tag>.tar.gz
2. 解压导入镜像     → 输入 .tar.gz 路径 → docker load 导入
```

### compose 批量打包

```sh
./docker-image-porter.sh -f docker-compose.yml
```

会解析 `docker-compose.yml` 中所有 `image:` 字段（自动去重、去引号、去行内注释），依次 `docker pull`，最终打包为：

```
<compose文件名>_images.tar.gz
```

生成的包里含所有服务用到的镜像，导入时无需区分来源，走菜单选项2导入即可。

## 说明与限制

- compose 文件解析基于文本匹配 `image:` 字段，不支持 YAML 锚点/变量替换（如 `${TAG}`）等高级语法。
- 仅支持 `.yml` / `.yaml` 后缀的 compose 文件。
- 私有仓库地址（含端口号，如 `registry.example.com:5000/app:1.0`）在 compose 解析中已正确支持；但普通「下载并打包镜像」菜单的单镜像导出功能暂不支持此类地址（tag 解析会出错）。
- 需要本机已安装并可运行 `docker`。
