# dev_env

本地开发环境中间件集合：MySQL / PostgreSQL / Redis / RabbitMQ / Elasticsearch / Nacos，全部通过 Docker Compose 管理。每个中间件独立一个目录、一份 `docker-compose.yml`、一份 `.env`（本地配置，不入库）和一份 `.env.example`（入库模板）。

## 目录结构

```text
dev_env/
├── README.md                    # 本文件
├── dev_env.sh                   # 服务启停 / 状态 / 客户端 管理脚本
├── .gitignore                   # 已忽略 **/.env
├── elasticsearch/
│   ├── docker-compose.yml
│   ├── .env / .env.example      # 注意：该服务 compose 未参数化，见下文说明
│   └── (无 conf，数据在命名卷)
├── mysql/
│   ├── docker-compose.yml
│   ├── .env / .env.example
│   └── conf/my.cnf
├── postgresql/
│   ├── docker-compose.yml
│   ├── .env / .env.example
│   ├── conf/postgresql.conf
│   └── initdb/                  # 首次初始化数据卷时执行的扩展脚本
├── redis/
│   ├── docker-compose.yml
│   ├── .env / .env.example
│   └── conf/redis.conf
├── rabbitmq/
│   ├── docker-compose.yml
│   ├── .env / .env.example
│   └── conf/rabbitmq.conf
└── nacos/
    ├── docker-compose.yml
    ├── .env / .env.example      # 鉴权密钥必填（:? 语法），缺失会启动失败
    └── (数据在命名卷；配置库 nacos_data 复用在 mysql 栈)
```

## 服务一览

| 服务 | 镜像 | 容器名 | 主机端口 | 默认凭据（可经 .env 覆盖） |
| --- | --- | --- | --- | --- |
| MySQL | `mysql:lts` (8.4 LTS) | dev-mysql | 3306 | root / root123；用户 dev / dev123；库 dev |
| PostgreSQL | `pgvector/pgvector:pg17` | dev-postgres | 5432 | postgres / postgres123；库 dev（含 vector 等扩展） |
| Redis | `redis:7.4.11` | dev-redis | 6379 | 密码 redis123 |
| RabbitMQ | `rabbitmq:4.3.5-management` | dev-rabbitmq | 5672 / 15672 | dev / dev123；vhost dev；控制台 http://localhost:15672 |
| Elasticsearch | `elasticsearch:8.19.3` | dev-elasticsearch | 9200 | 无认证（开发环境已关闭 xpack） |
| Nacos | `nacos/nacos-server:v3.2.2` | dev-nacos | 8848 / 9848 / 8080 | 连接 mysql 栈；控制台 http://localhost:8080 |

所有数据均持久化在 Docker 命名卷（`mysql_data`、`pg_data`、`redis_data`、`rabbitmq_data`、`es_data`、`nacos_data_dir`），不映射到主机目录。

## .env 机制说明

- 每个 compose 文件通过 `${VAR:-默认值}` 从**同目录的 `.env`** 读取配置；`.env` 缺失或未定义某键时使用默认值，因此空配置也能按默认值启动。
- `.env` 已被 `.gitignore`（`**/.env`）忽略，**不会入库**；仓库只提交 `.env.example` 作为模板。
- nacos 的 `NACOS_AUTH_TOKEN` / `NACOS_AUTH_IDENTITY_KEY` / `NACOS_AUTH_IDENTITY_VALUE` 使用 `:?` 语法**必填**，没有默认值，缺失时 compose 会直接报错拒绝启动——nacos/.env 必须存在且包含这三个键。
- **elasticsearch 例外**：其 compose 目前完全硬编码、未使用任何 `${VAR}`，因此 `.env`/`.env.example` 只作占位说明。如需通过 .env 管理端口/内存等，请先按 `.env.example` 中的注释把 compose 参数化。
- 直接改动 `docker-compose.yml` 也可，但建议优先把可变项参数化后放进 `.env`，避免改坏文件。

## 快速开始

1. 初始化本地 `.env`（当前工作区已生成，可跳过；新克隆的仓库执行）：

   ```bash
   for d in mysql postgresql redis rabbitmq elasticsearch nacos; do
       cp "$d/.env.example" "$d/.env"
   done
   ```

   说明：除 nacos 外，`.env.example` 中的值即 compose 默认值，复制即可运行；nacos 的鉴权密钥为随机构造的可用示例值，正式使用前建议按 `nacos/.env.example` 内注释重新生成。

2. 启动（脚本会按依赖顺序处理，nacos 依赖 mysql 栈网络与库账号，见下文）：

   ```bash
   ./dev_env.sh start          # 启动全部：mysql → postgresql → redis → elasticsearch → rabbitmq → nacos
   ./dev_env.sh status         # 查看各容器状态与健康检查
   ```

   等价地也可在任意目录直接执行：

   ```bash
   docker compose -f mysql/docker-compose.yml up -d     # 需先起 mysql（nacos 依赖其网络与数据）
   docker compose -f nacos/docker-compose.yml up -d
   ```

3. 验证：

   ```bash
   ./dev_env.sh cli mysql       # 进入 mysql 客户端（自动读取 mysql/.env 的 root 密码）
   ./dev_env.sh cli postgresql  # 进入 psql
   ./dev_env.sh cli redis       # 进入 redis-cli（自动读取 redis/.env 密码）
   ```

## Nacos 使用外部 MySQL（一次性初始化）

本仓库的 nacos 不另起数据库，而是连接 mysql 栈的 `dev-mysql` 容器，使用独立库 `nacos_data` 与账号 `nacos_admin`（密码取 `nacos/.env` 的 `MYSQL_PASSWORD`，默认 `Nacos_123`）。

> 注意：`nacos/.env` 中的 `MYSQL_PASSWORD` 是 **nacos_admin 账号**的密码，与 `mysql/.env` 中 `MYSQL_PASSWORD`（dev 用户）是两套凭据，不要混用。

1. 先在 MySQL 中创建库与账号（密码若已修改请同步替换）：

   ```bash
   docker exec -i dev-mysql mysql -uroot -proot123 <<'SQL'
   CREATE DATABASE IF NOT EXISTS nacos_data DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER IF NOT EXISTS 'nacos_admin'@'%' IDENTIFIED BY 'Nacos_123';
   GRANT ALL PRIVILEGES ON nacos_data.* TO 'nacos_admin'@'%';
   FLUSH PRIVILEGES;
   SQL
   ```

2. 导入与 nacos-server:v3.2.2 匹配的官方建表 SQL（官方集群部署文档同样指向该文件）：

   ```bash
   curl -fsSL -o /tmp/mysql-schema.sql \
     https://raw.githubusercontent.com/alibaba/nacos/master/distribution/conf/mysql-schema.sql
   docker exec -i dev-mysql mysql -uroot -proot123 nacos_data < /tmp/mysql-schema.sql
   ```

3. 启动 nacos 并访问控制台 `http://localhost:8080`：3.x 开启鉴权后，首次访问需初始化管理员（用户名为 `nacos`）的密码，详见 [Nacos 控制台手册](https://nacos.io/docs/v3.0/manual/admin/console/)。

> 提示：nacos 的 healthcheck 通过 TCP 探测 8848；若 `start` 时 mysql 未运行，`dev_env.sh` 会先自动拉起 mysql。若手工执行 compose 报 `network dev-mysql_default not found`，请先启动 mysql 栈。

## 各服务 .env 变量参考

### mysql/.env

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MYSQL_ROOT_PASSWORD` | `root123` | root 密码（首次初始化数据卷时生效） |
| `MYSQL_USER` | `dev` | 额外创建的开发用户 |
| `MYSQL_PASSWORD` | `dev123` | 开发用户密码 |
| `MYSQL_DATABASE` | `dev` | 开发库 |

### postgresql/.env

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `POSTGRES_USER` | `postgres` | 超级用户 |
| `POSTGRES_PASSWORD` | `postgres123` | 超级用户密码 |
| `POSTGRES_DB` | `dev` | 默认库（initdb 扩展脚本作用于该库） |

### redis/.env

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `REDIS_PASSWORD` | `redis123` | 访问密码（由 compose 以 `--requirepass` 注入） |

### rabbitmq/.env

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `RABBITMQ_DEFAULT_USER` | `dev` | 默认用户（仅首次初始化时创建） |
| `RABBITMQ_DEFAULT_PASS` | `dev123` | 默认用户密码 |
| `RABBITMQ_DEFAULT_VHOST` | `dev` | 默认虚拟主机 |

### nacos/.env

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MYSQL_PASSWORD` | `Nacos_123` | nacos 连接 mysql 时 nacos_admin 账号的密码（有默认值，非必填） |
| `NACOS_AUTH_ENABLE` | `true` | 是否开启鉴权 |
| `NACOS_AUTH_TOKEN` | 无（必填） | 鉴权密钥；`openssl rand -base64 48` 生成（解码后 ≥32 字节） |
| `NACOS_AUTH_IDENTITY_KEY` | 无（必填） | 服务间鉴权身份 key |
| `NACOS_AUTH_IDENTITY_VALUE` | 无（必填） | 服务间鉴权身份 value；`openssl rand -hex 24` 生成 |

## 修改凭据 / 配置的注意事项

- **数据卷已初始化后，修改 `.env` 中的密码不会改库内已有账号**（MySQL/PostgreSQL/RabbitMQ 等仅首次初始化时读取）。需要改库内账号时，请用客户端 SQL 修改，或删卷重建：

  ```bash
  docker compose -f mysql/docker-compose.yml down -v   # 会删除 mysql_data 卷，谨慎操作
  ```

- nacos 重新生成密钥后，需重启容器使其生效；请同时记住新值（客户端/控制台鉴权一致）。
- 修改 `.env` 后执行 `docker compose -f <dir>/docker-compose.yml up -d` 即可让容器按新环境变量重建。
- 端口、资源等未参数化的项（如各服务端口、Elasticsearch 的 `ES_JAVA_OPTS`/`cluster.name`、MySQL 的 `3306` 映射等）需要直接编辑对应的 `docker-compose.yml`；建议参考 `elasticsearch/.env.example` 注释的方式自行参数化。

## 日常管理

```bash
./dev_env.sh start [服务...]     # 启动（默认全部，自动处理 nacos 依赖）
./dev_env.sh stop  [服务...]     # 停止（默认全部，按依赖逆序）
./dev_env.sh status              # 查看状态与健康检查
./dev_env.sh cli mysql|postgresql|redis [参数...]   # 进入客户端，密码自动从 .env 读取
```

直接使用 docker compose：

```bash
docker compose -f redis/docker-compose.yml logs -f          # 查看日志
docker compose -f redis/docker-compose.yml ps               # 查看单栈状态
docker compose -f redis/docker-compose.yml exec redis sh    # 进入容器
```

## 常见问题

- **nacos 启动失败：network `dev-mysql_default` not found** — nacos 复用 mysql 栈的外部网络，请先 `./dev_env.sh start mysql` 或 `docker compose -f mysql/docker-compose.yml up -d`。
- **nacos 启动报 `NACOS_AUTH_* 未设置`** — `nacos/.env` 缺失或缺少必填键（compose 用了 `:?` 语法，缺省即报错），请从 `nacos/.env.example` 复制补齐。
- **nacos 连不上数据库 / 登录后报权限错误** — 确认已按上文在 MySQL 中创建 `nacos_data` 库与 `nacos_admin` 账号，且 `nacos/.env` 的 `MYSQL_PASSWORD` 与建号密码一致。
- **改了密码后健康检查失败** — 数据卷内的账号密码未变，而 `.env` 已改。要么用 SQL 同步库内账号，要么 `down -v` 删卷重建。
- **端口被占用** — 各服务端口在 compose 中硬编码，直接修改对应 `docker-compose.yml` 的 `ports` 映射。
- **Redis 的密码** — 由 compose 的 `--requirepass "${REDIS_PASSWORD:-redis123}"` 注入，`redis/conf/redis.conf` 中不写密码。
- **MySQL 慢查询日志** — 已开启（阈值 1s），日志在容器内 `/var/lib/mysql/slow.log`，可用 `docker exec dev-mysql tail -f /var/lib/mysql/slow.log` 查看。
- **Elasticsearch 健康检查依赖容器内 curl** — 官方镜像自带 curl；如换用精简镜像需同步调整 healthcheck。

## 安全提示

- 本仓库是**本地开发环境**：所有服务映射 `0.0.0.0` 且使用文档中的默认口令，Elasticsearch 也关闭了安全认证（见 compose 注释），请勿直接用于生产或暴露公网。
- `.env` 已 gitignore，但 `.env.example` 会入库——其中的 nacos 密钥只是示例值，新环境请务必重新生成。
- 如需更安全的凭据，可生成随机值后填入 `.env`：

  ```bash
  openssl rand -base64 16   # MySQL / Redis / RabbitMQ 等常规密码参考
  openssl rand -base64 48   # nacos NACOS_AUTH_TOKEN
  openssl rand -hex 24      # nacos NACOS_AUTH_IDENTITY_VALUE
  ```
