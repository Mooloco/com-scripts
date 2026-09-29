#!/usr/bin/env bash

set -Eeuo pipefail

readonly COMPOSE_INSTALL_PATH="/usr/local/bin/docker-compose"
readonly COMPOSE_SYMLINK_PATH="/usr/bin/docker-compose"

log() {
	printf '[INFO] %s\n' "$*"
}

fail() {
	printf '[ERROR] %s\n' "$*" >&2
	exit 1
}

require_root() {
	if [[ ${EUID} -ne 0 ]]; then
		fail "请使用 root 用户或通过 sudo 运行此脚本。"
	fi
}

check_dependencies() {
	local command_name

	for command_name in curl uname chmod ln systemctl; do
		command -v "${command_name}" >/dev/null 2>&1 || \
			fail "未找到依赖命令: ${command_name}"
	done
}

install_docker() {
	log "安装 Docker。"
	curl --fail --silent --show-error --location https://get.docker.com | sh
}

install_docker_compose() {
	local compose_url

	compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"

	log "下载 Docker Compose。"
	curl --fail --silent --show-error --location \
		"${compose_url}" \
		--output "${COMPOSE_INSTALL_PATH}"

	chmod +x "${COMPOSE_INSTALL_PATH}"
	ln -sfn "${COMPOSE_INSTALL_PATH}" "${COMPOSE_SYMLINK_PATH}"
}

configure_docker_service() {
	log "启动并设置 Docker 服务开机自启。"
	systemctl enable --now docker
}

verify_installation() {
	log "验证 Docker 版本。"
	docker --version

	log "验证 Docker Compose 版本。"
	docker-compose version
}

main() {
	require_root
	check_dependencies
	install_docker
	install_docker_compose
	configure_docker_service
	verify_installation
	log "Docker 与 Docker Compose 安装完成。"
}

main "$@"


