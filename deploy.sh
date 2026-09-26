#!/usr/bin/env bash
#
# file-server 服务管理脚本（在 Linux 服务器上运行）
# 用法: ./deploy.sh {start|stop|restart|status}
#
# 与 file-server.jar 放在同一目录下使用：
#   /opt/file-server/
#   ├── deploy.sh
#   ├── file-server.jar
#   ├── application.yml      # 可选，存在则优先于 jar 内配置
#   ├── logs/
#   └── uploads/

set -euo pipefail

# ===== 配置区 =====
APP_NAME="file-server"
JVM_OPTS="-Xms256m -Xmx512m"        # JVM 参数
JAVA_BIN="java"                     # java 命令路径
# ==================

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
JAR_FILE="${APP_DIR}/${APP_NAME}.jar"
PID_FILE="${APP_DIR}/app.pid"
LOG_DIR="${APP_DIR}/logs"
APP_LOG="${LOG_DIR}/app.log"          # 应用日志（logback 写入）
NOHUP_LOG="${LOG_DIR}/nohup.log"      # JVM 启动阶段输出

cd "$APP_DIR"

log() { echo -e "\033[32m[${APP_NAME}]\033[0m $*"; }
err() { echo -e "\033[31m[${APP_NAME}]\033[0m $*" >&2; }

pid() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    cat "$PID_FILE"
  fi
}

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

  # 存在外置配置则优先加载
  EXTRA_ARGS=()
  [ -f "${APP_DIR}/application.yml" ] && \
    EXTRA_ARGS+=(--spring.config.additional-location="file:${APP_DIR}/application.yml")

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
    PORT=$(grep -E '^\s*port:' "${APP_DIR}/application.yml" 2>/dev/null | awk '{print $2}' || true)
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
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  status ;;
  *)
    echo "用法: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
