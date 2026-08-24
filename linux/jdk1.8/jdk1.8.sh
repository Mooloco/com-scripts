#!/bin/bash
# CentOS 7 一键安装 JDK 1.8 并配置环境变量
#Mooloco 

echo ">>> 更新软件源"
yum clean all
yum makecache

echo ">>> 安装 JDK 1.8"
yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel

echo ">>> 配置环境变量"
cat >/etc/profile.d/java.sh <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
export PATH=$JAVA_HOME/bin:$PATH
EOF

chmod +x /etc/profile.d/java.sh
source /etc/profile.d/java.sh

echo ">>> 验证安装结果"
java -version
javac -version

echo ">>> JDK 安装完成！"

