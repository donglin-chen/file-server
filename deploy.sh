#!/usr/bin/env bash
#
# file-server 部署/管理脚本（在 Linux 服务器上运行）
#
# 用法:
#   ./deploy.sh deploy              # 拉代码 -> 打包 -> 重启（完整部署）
#   ./deploy.sh start|stop|restart  # 仅管理服务进程
#   ./deploy.sh status              # 查看运行状态
#   ./deploy.sh logs                # 实时查看应用日志
#
# 首次使用前请修改下方 ===== 配置区 =====

set -euo pipefail

# ===== 配置区 =====
APP_NAME="file-server"
REPO_DIR="/data/code/file-server"          # 代码仓库目录（git clone 到此目录）
GIT_BRANCH="main"                         # 部署分支
DEPLOY_DIR="/data/code/file-server"             # 服务运行目录（jar 拷贝到这里）
JAVA_BIN="java"                           # java 命令路径
MVN_BIN="mvn"                             # maven 命令路径
JVM_OPTS="-Xms256m -Xmx256m"              # JVM 参数
APP_VERSION="1.0.0"                       # 与 pom.xml 的 version 保持一致
# ==================

JAR_NAME="${APP_NAME}-${APP_VERSION}.jar"
JAR_FILE="${DEPLOY_DIR}/${APP_NAME}.jar"
PID_FILE="${DEPLOY_DIR}/app.pid"
LOG_DIR="${DEPLOY_DIR}/logs"
APP_LOG="${LOG_DIR}/app.log"          # 应用日志（logback 写入）
NOHUP_LOG="${LOG_DIR}/nohup.log"      # JVM 启动阶段输出

log() { echo -e "\033[32m[${APP_NAME}]\033[0m $*"; }
err() { echo -e "\033[31m[${APP_NAME}]\033[0m $*" >&2; }

pid() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    cat "$PID_FILE"
  fi
}

# ---------- 构建 ----------

build() {
  log "拉取代码: ${REPO_DIR} (${GIT_BRANCH})"
  cd "$REPO_DIR"
  git fetch origin
  git checkout "$GIT_BRANCH"
  git reset --hard "origin/${GIT_BRANCH}"

  log "Maven 打包..."
  "$MVN_BIN" clean package -DskipTests -q

  local built_jar="${REPO_DIR}/target/${JAR_NAME}"
  if [ ! -f "$built_jar" ]; then
    err "构建产物不存在: ${built_jar}（请检查 APP_VERSION 是否与 pom.xml 一致）"
    exit 1
  fi

  mkdir -p "$DEPLOY_DIR"
  # 备份旧版本
  [ -f "$JAR_FILE" ] && cp "$JAR_FILE" "${JAR_FILE}.bak"
  cp "$built_jar" "$JAR_FILE"
  log "jar 已更新: ${JAR_FILE} ($(du -h "$JAR_FILE" | cut -f1))"
}

# ---------- 服务管理 ----------

start() {
  if [ -n "$(pid)" ]; then
    log "服务已在运行，pid=$(pid)"
    return 0
  fi
  if [ ! -f "$JAR_FILE" ]; then
    err "找不到 ${JAR_FILE}"
    exit 1
  fi
  mkdir -p "$LOG_DIR"
  cd "$DEPLOY_DIR"

  # 存在外置配置则优先加载
  EXTRA_ARGS=()
  [ -f "${DEPLOY_DIR}/application.yml" ] && \
    EXTRA_ARGS+=(--spring.config.additional-location="file:${DEPLOY_DIR}/application.yml")

  log "启动服务..."
  nohup "$JAVA_BIN" $JVM_OPTS -jar "$JAR_FILE" "${EXTRA_ARGS[@]}" \
    >> "$NOHUP_LOG" 2>&1 &
  echo $! > "$PID_FILE"

  # 健康检查：最多等待 60 秒
  for i in $(seq 1 12); do
    sleep 5
    if [ -z "$(pid)" ]; then
      err "启动失败，进程已退出，请查看日志:"
      err "  tail -50 ${APP_LOG}"
      err "  tail -50 ${NOHUP_LOG}"
      exit 1
    fi
    PORT=$(grep -E '^\s*port:' "${DEPLOY_DIR}/application.yml" 2>/dev/null | awk '{print $2}' || true)
    PORT=${PORT:-8080}
    if curl -s -o /dev/null "http://localhost:${PORT}/file-server/" 2>/dev/null; then
      log "启动成功，pid=$(pid)，地址: http://localhost:${PORT}/file-server/"
      return 0
    fi
  done
  log "进程已启动 (pid=$(pid))，但健康检查未通过，请关注日志: tail -f ${APP_LOG}"
}

stop() {
  local p
  p="$(pid)"
  if [ -z "$p" ]; then
    log "服务未运行"
    rm -f "$PID_FILE"
    return 0
  fi
  log "停止服务，pid=${p} ..."
  kill "$p"
  for i in $(seq 1 15); do
    kill -0 "$p" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$p" 2>/dev/null; then
    log "优雅停止超时，强制终止"
    kill -9 "$p" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  log "已停止"
}

status() {
  if [ -n "$(pid)" ]; then
    log "运行中，pid=$(pid)"
    ps -o pid,etime,rss,cmd -p "$(pid)" | tail -n +2
  else
    log "未运行"
    exit 1
  fi
}

case "${1:-}" in
  deploy)  build; stop; start ;;
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  status ;;
  logs)    tail -f "$APP_LOG" ;;
  *)
    echo "用法: $0 {deploy|start|stop|restart|status|logs}"
    exit 1
    ;;
esac
