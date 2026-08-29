#!/usr/bin/env bash
# dev_env 服务管理脚本
# 用法:
#   ./dev_env.sh start  [服务...]    启动（默认全部，按依赖顺序）
#   ./dev_env.sh stop   [服务...]    停止（默认全部，按依赖逆序）
#   ./dev_env.sh status [服务...]    查看状态（默认全部）
#   ./dev_env.sh cli <mysql|postgresql|redis> [客户端参数...]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 固定顺序：nacos 依赖 mysql 栈的网络，必须先起 mysql、最后停 mysql
ALL_SERVICES=(mysql postgresql redis elasticsearch rabbitmq nacos)

usage() {
    cat <<EOF
用法: $0 <start|stop|status|cli> [服务...]    # 不指定服务则作用于全部
可用服务: ${ALL_SERVICES[*]}
示例:
  $0 start                 # 启动全部
  $0 stop nacos redis      # 停止指定服务
  $0 status                # 查看全部状态
  $0 cli mysql             # 进入 MySQL 客户端（默认 root，密码读 mysql/.env）
  $0 cli mysql -uroot -p   # 额外参数原样透传给 mysql 客户端
  $0 cli postgresql        # 进入 psql（postgres 用户）
  $0 cli redis             # 进入 redis-cli（密码读 redis/.env）
EOF
}

container_of() {
    case "$1" in
        postgresql) echo dev-postgres ;;
        *)          echo "dev-$1" ;;
    esac
}

# 校验参数中的服务名，结果写入 selected 数组
selected=()
parse_services() {
    if [ $# -eq 0 ]; then
        selected=("${ALL_SERVICES[@]}")
        return
    fi
    for arg in "$@"; do
        local valid=false
        for s in "${ALL_SERVICES[@]}"; do
            [ "$arg" = "$s" ] && valid=true && break
        done
        if ! $valid; then
            echo "错误: 未知服务 '$arg'" >&2
            echo "可用服务: ${ALL_SERVICES[*]}" >&2
            exit 1
        fi
        selected+=("$arg")
    done
}

is_selected() {
    local sel
    for sel in "${selected[@]}"; do
        [ "$1" = "$sel" ] && return 0
    done
    return 1
}

cmd_start() {
    cd "$ROOT_DIR"
    local started=0 s
    for s in "${ALL_SERVICES[@]}"; do
        is_selected "$s" || continue
        # nacos 依赖 mysql 栈：未运行时提示并自动先启动 mysql
        if [ "$s" = "nacos" ] && ! docker ps --format '{{.Names}}' | grep -qx dev-mysql; then
            echo "提示: nacos 依赖 mysql，当前 mysql 未运行，将自动一并启动"
            docker compose -f mysql/docker-compose.yml up -d
            started=$((started + 1))
        fi
        echo "==> 启动 $s"
        docker compose -f "$s/docker-compose.yml" up -d
        started=$((started + 1))
    done
    echo "完成：本次启动 $started 个服务"
}

cmd_stop() {
    cd "$ROOT_DIR"
    local stopped=0 s i
    for ((i=${#ALL_SERVICES[@]}-1; i>=0; i--)); do
        s="${ALL_SERVICES[$i]}"
        is_selected "$s" || continue
        if [ -z "$(docker compose -f "$s/docker-compose.yml" ps -q --status running)" ]; then
            echo "==> $s 未在运行，跳过"
            continue
        fi
        if [ "$s" = "mysql" ] && [ -n "$(docker compose -f nacos/docker-compose.yml ps -q --status running)" ]; then
            echo "提示: nacos 仍在运行，停止 mysql 将导致 nacos 不可用"
        fi
        echo "==> 停止 $s"
        docker compose -f "$s/docker-compose.yml" stop
        stopped=$((stopped + 1))
    done
    echo "完成：本次停止 $stopped 个服务"
}

cmd_status() {
    local s c state health
    printf '%-14s %-18s %-10s %-10s\n' "SERVICE" "CONTAINER" "STATE" "HEALTH"
    for s in "${ALL_SERVICES[@]}"; do
        is_selected "$s" || continue
        c=$(container_of "$s")
        health="-"
        state=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null) || state="absent"
        if [ "$state" = "running" ]; then
            health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$c")
        fi
        printf '%-14s %-18s %-10s %-10s\n' "$s" "$c" "$state" "$health"
    done
}

# 读取某服务 .env 中指定键的值
env_of() {
    grep -E "^$2=" "$ROOT_DIR/$1/.env" 2>/dev/null | head -1 | cut -d= -f2-
}

cmd_cli() {
    if [ $# -eq 0 ]; then
        echo "错误: cli 需要指定服务（mysql|postgresql|redis）" >&2
        exit 1
    fi
    local s="$1" it="-i" pass
    shift
    [ -t 0 ] && it="-it"
    case "$s" in
        mysql)
            docker ps --format '{{.Names}}' | grep -qx dev-mysql || { echo "错误: mysql 未运行，请先 ./dev_env.sh start mysql" >&2; exit 1; }
            if [ $# -eq 0 ] && pass=$(env_of mysql MYSQL_ROOT_PASSWORD) && [ -n "$pass" ]; then
                exec docker exec $it dev-mysql mysql -uroot -p"$pass"
            fi
            exec docker exec $it dev-mysql mysql "$@"
            ;;
        postgresql)
            docker ps --format '{{.Names}}' | grep -qx dev-postgres || { echo "错误: postgresql 未运行，请先 ./dev_env.sh start postgresql" >&2; exit 1; }
            exec docker exec $it dev-postgres psql -U postgres "$@"
            ;;
        redis)
            docker ps --format '{{.Names}}' | grep -qx dev-redis || { echo "错误: redis 未运行，请先 ./dev_env.sh start redis" >&2; exit 1; }
            if pass=$(env_of redis REDIS_PASSWORD) && [ -n "$pass" ]; then
                exec docker exec $it dev-redis redis-cli -a "$pass" --no-auth-warning "$@"
            fi
            exec docker exec $it dev-redis redis-cli "$@"
            ;;
        rabbitmq|nacos|elasticsearch)
            echo "该服务提供 Web 控制台，无需 cli 入口："
            echo "  rabbitmq       http://localhost:15672"
            echo "  nacos          http://localhost:8080"
            echo "  elasticsearch  http://localhost:9200"
            exit 1
            ;;
        *)
            echo "错误: cli 不支持服务 '$s'（可用: mysql postgresql redis）" >&2
            exit 1
            ;;
    esac
}

main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    case "$1" in
        -h|--help) usage; exit 0 ;;
        start|stop|status|cli) ;;
        *) echo "错误: 未知命令 '$1'" >&2; usage >&2; exit 1 ;;
    esac
    local cmd="$1"
    shift
    if [ "$cmd" = "cli" ]; then
        cmd_cli "$@"
        return
    fi
    parse_services "$@"
    case "$cmd" in
        start)  cmd_start ;;
        stop)   cmd_stop ;;
        status) cmd_status ;;
    esac
}

main "$@"
