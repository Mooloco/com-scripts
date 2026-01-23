@REM delete the known_hosts for windows cmd/powershell

@echo off

set SSH_KNOWN_HOSTS=%USERPROFILE%\.ssh\known_hosts

if exist "%SSH_KNOWN_HOSTS%" (
    del "%SSH_KNOWN_HOSTS%"
    echo known_hosts 已删除：%SSH_KNOWN_HOSTS%
) else (
    echo 未找到 known_hosts：%SSH_KNOWN_HOSTS%
)
