#!/usr/bin/env bash
#
# 部署 file-server 到 Linux 服务器
# 用法: ./deploy.sh [-s skip-build] [-h]
#
# 首次使用前请修改下方 ===== 配置区 ===== 中的服务器信息

set -euo pipefail

# ===== 配置区 =====
SERVER_USER="root"                  # SSH 用户名
SERVER_HOST="192.168.1.100"         # 服务器地址
SERVER_PORT="22"                    # SSH 端口
REMOTE_DIR="/opt/file-server"       # 服务器上的部署目录
JAVA_BIN="java"                     # 服务器上的 java 命令路径
JVM_OPTS="-Xms256m -Xmx512m"        # JVM 参数
# ==================

APP_NAME="file-server"
APP_VERSION="1.0.0"
JAR_NAME="${APP_NAME}-${APP_VERSION}.jar"
LOCAL_JAR="target/${JAR_NAME}"
REMOTE_JAR="${REMOTE_DIR}/${APP_NAME}.jar"
LOG_FILE="${REMOTE_DIR}/logs/app.log"
NOHUP_LOG="${REMOTE_DIR}/logs/nohup.log"  # 仅记录应用启动前的 JVM 输出，应用日志由 logback 写入 app.log
PID_FILE="${REMOTE_DIR}/app.pid"

SSH="ssh -p ${SERVER_PORT} ${SERVER_USER}@${SERVER_HOST}"
SCP="scp -P ${SERVER_PORT}"

SKIP_BUILD=false
while getopts "sh" opt; do
  case $opt in
    s) SKIP_BUILD=true ;;
    h) echo "用法: $0 [-s 跳过构建] [-h 帮助]"; exit 0 ;;
    *) echo "用法: $0 [-s 跳过构建] [-h 帮助]"; exit 1 ;;
  esac
done

log() { echo -e "\033[32m[deploy]\033[0m $*"; }
err() { echo -e "\033[31m[deploy]\033[0m $*" >&2; }

# 1. 本地构建
if [ "$SKIP_BUILD" = false ]; then
  log "开始 Maven 打包..."
  if [ -x ./mvnw ]; then
    ./mvnw clean package -DskipTests -q
  else
    mvn clean package -DskipTests -q
  fi
else
  log "跳过构建，使用已有 jar 包"
fi

if [ ! -f "$LOCAL_JAR" ]; then
  err "找不到构建产物: ${LOCAL_JAR}"
  exit 1
fi
log "构建产物: ${LOCAL_JAR} ($(du -h "$LOCAL_JAR" | cut -f1))"

# 2. 上传 jar
log "上传 jar 到 ${SERVER_USER}@${SERVER_HOST}:${REMOTE_DIR} ..."
$SSH "mkdir -p ${REMOTE_DIR}/logs ${REMOTE_DIR}/uploads"
$SCP "$LOCAL_JAR" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_JAR}.new"

# 3. 远程重启
log "远程重启服务..."
$SSH bash -s <<EOF
set -e
cd ${REMOTE_DIR}

# 停掉旧进程
if [ -f ${PID_FILE} ] && kill -0 \$(cat ${PID_FILE}) 2>/dev/null; then
  echo "[remote] 停止旧进程 (pid=\$(cat ${PID_FILE}))"
  kill \$(cat ${PID_FILE})
  for i in \$(seq 1 15); do
    kill -0 \$(cat ${PID_FILE}) 2>/dev/null || break
    sleep 1
  done
  # 超时强杀
  kill -9 \$(cat ${PID_FILE}) 2>/dev/null || true
fi

# 替换 jar（先备份旧版）
[ -f ${REMOTE_JAR} ] && cp ${REMOTE_JAR} ${REMOTE_JAR}.bak
mv ${REMOTE_JAR}.new ${REMOTE_JAR}

# 启动新进程
nohup ${JAVA_BIN} ${JVM_OPTS} -jar ${REMOTE_JAR} \
  --spring.config.location=file:${REMOTE_DIR}/application.yml,classpath:/application.yml \
  >> ${NOHUP_LOG} 2>&1 &
echo \$! > ${PID_FILE}
echo "[remote] 已启动，pid=\$(cat ${PID_FILE})"
EOF

# 4. 健康检查
log "等待服务启动并做健康检查..."
sleep 5
for i in $(seq 1 12); do
  if $SSH "kill -0 \$(cat ${PID_FILE}) 2>/dev/null" 2>/dev/null; then
    STATUS=$($SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/file-server/ || true" 2>/dev/null || echo "000")
    if [ "$STATUS" != "000" ]; then
      log "部署成功！服务已运行，HTTP 状态码: ${STATUS}"
      log "访问地址: http://${SERVER_HOST}:8080/file-server/"
      exit 0
    fi
  else
    err "进程已退出，请查看日志: $SSH 'tail -50 ${LOG_FILE}'"
    exit 1
  fi
  sleep 5
done

err "健康检查超时，请手动查看日志: $SSH 'tail -50 ${LOG_FILE}'"
exit 1
