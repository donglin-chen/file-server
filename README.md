# file-server

基于 Spring Boot 3 的简单文件上传/下载服务，支持按命名空间（namespace）+ env（环境）两级隔离存储。

## 运行

```bash
mvn spring-boot:run
```

服务默认监听 `8080` 端口，上下文路径为 `/file-server`。上传的文件按命名空间和 env 分目录保存在 `uploads/<namespace>/<env>/` 下（根目录可在 `application.yml` 中通过 `file.upload-dir` 修改）。

## 接口

`namespace` 与 `env` 均为必填：上传时通过表单字段传入；下载/删除/列表时在路径中指定。
两者均仅允许字母、数字、下划线、中划线（长度 1-64）。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/files` | 上传单个文件（表单字段 `namespace`、`env`、`file`） |
| POST | `/files/batch` | 批量上传（表单字段 `namespace`、`env`、`files`） |
| GET | `/files/namespaces` | 列出所有命名空间 |
| GET | `/files/{namespace}` | 列出该命名空间下的所有 env |
| GET | `/files/{namespace}/{env}` | 列出该命名空间 + env 下的所有文件 |
| GET | `/files/{namespace}/{env}/{filename}` | 下载文件 |
| DELETE | `/files/{namespace}/{env}/{filename}` | 删除文件 |

## 示例

```bash
BASE=http://localhost:8080/file-server/files

# 上传（必须带 namespace 和 env）
curl -F "namespace=user-avatar" -F "env=dev" -F "file=@a.txt" $BASE
# => {"namespace":"user-avatar","env":"dev","filename":"944be..._a.txt","url":"http://localhost:8080/file-server/files/user-avatar/dev/944be..._a.txt"}

# 批量上传
curl -F "namespace=order-doc" -F "env=prod" -F "files=@a.txt" -F "files=@b.txt" $BASE/batch

# 下载
curl -O $BASE/user-avatar/dev/944be..._a.txt

# 列表：命名空间 / env / 文件
curl $BASE/namespaces
curl $BASE/user-avatar
curl $BASE/user-avatar/dev

# 删除
curl -X DELETE $BASE/user-avatar/dev/944be..._a.txt
```

## 说明

- 文件按命名空间 + env 两级目录隔离存储：`uploads/<namespace>/<env>/<uuid>_<原始文件名>`。
- 上传的文件会加上 UUID 前缀存储，避免重名覆盖；返回的 `url` 可直接用于下载。
- 单文件与单请求大小限制为 100MB（`spring.servlet.multipart.max-file-size` / `max-request-size`）。
- 命名空间、env 与文件名均做路径穿越防护（命名空间/env 有字符白名单，文件名拒绝 `..` 且解析后不得越出目录）。
- 下载时使用 RFC 5987 编码，支持中文文件名。
