# file-server 接口文档

简单的文件上传/下载服务，文件按 `命名空间/环境` 两级目录隔离存储。

- **基础地址**: `https://www.xiaojiang.tech/file-server`
- **数据格式**: 上传接口为 `multipart/form-data`，其余均为 `application/json`
- **文件大小限制**: 单个文件最大 100MB

## 通用约定

### 路径参数规则

| 参数 | 说明 | 规则 |
|------|------|------|
| `namespace` | 命名空间，用于业务隔离 | 仅允许字母、数字、下划线、中划线，长度 1-64 |
| `env` | 环境标识（如 dev / test / prod） | 同上 |

### 存储文件名

上传成功后，文件实际存储名为 `UUID_原始文件名`（例如 `3f2b8c1a-xxxx_avatar.png`），下载/删除时需使用该存储名。

### 错误响应

统一返回 JSON：

```json
{ "error": "错误描述" }
```

| HTTP 状态码 | 说明 |
|------------|------|
| 400 | 参数缺失/不合法、文件为空、文件不存在 |
| 413 | 文件大小超过 100MB 限制 |
| 500 | 服务器内部错误 |

---

## 1. 上传文件（单文件）

```
POST /files/upload
```

**请求参数**（multipart/form-data）：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| namespace | string | 是 | 命名空间 |
| env | string | 是 | 环境 |
| file | file | 是 | 文件内容 |

**curl 示例**：

```bash
curl -X POST https://www.xiaojiang.tech/file-server/files/upload \
  -F "namespace=myapp" \
  -F "env=dev" \
  -F "file=@/path/to/avatar.png"
```

**响应** `200 OK`：

```json
{
  "namespace": "myapp",
  "env": "dev",
  "filename": "3f2b8c1a-1a2b-4c3d-9e4f-5a6b7c8d9e0f_avatar.png",
  "url": "/myapp/dev/3f2b8c1a-1a2b-4c3d-9e4f-5a6b7c8d9e0f_avatar.png"
}
```

> `url` 为文件相对路径，下载时拼接存储目录的访问域名即可（见「3. 下载文件」）。

---

## 2. 批量上传文件

```
POST /files/upload/batch
```

上传多个文件到同一命名空间 + 环境。

**请求参数**（multipart/form-data）：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| namespace | string | 是 | 命名空间 |
| env | string | 是 | 环境 |
| files | file[] | 是 | 多个文件 |

**curl 示例**：

```bash
curl -X POST https://www.xiaojiang.tech/file-server/files/upload/batch \
  -F "namespace=myapp" \
  -F "env=dev" \
  -F "files=@a.png" \
  -F "files=@b.pdf"
```

**响应** `200 OK`：

```json
[
  {
    "namespace": "myapp",
    "env": "dev",
    "filename": "uuid1_a.png",
    "url": "/myapp/dev/uuid1_a.png"
  },
  {
    "namespace": "myapp",
    "env": "dev",
    "filename": "uuid2_b.pdf",
    "url": "/myapp/dev/uuid2_b.pdf"
  }
]
```

---

## 3. 下载文件

文件下载不经过应用，由 nginx 直接代理磁盘存储目录（配置项 `file.upload-dir`）：

```
GET {文件相对路径}
```

上传接口返回的 `url` 即为该路径，拼接存储服务域名即可访问：

```bash
# 上传返回 "url": "/myapp/dev/uuid1_a.png"
curl -O -J https://www.xiaojiang.tech/myapp/dev/uuid1_a.png
```

> nginx 参考配置（`alias` 指向 `file.upload-dir` 目录）：
>
> ```nginx
> location / {
>     alias /data/uploads/;
> }
> ```

文件不存在时由 nginx 返回 `404`。

应用内也保留了下载接口作为备用（需要登录态/鉴权时可使用）：

```
GET /file-server/files/{namespace}/{env}/{filename}
```

- `Content-Type`: 根据文件扩展名自动识别，无法识别时为 `application/octet-stream`
- `Content-Disposition`: `attachment; filename*=UTF-8''<原始文件名>`（支持中文文件名）

文件不存在时返回 `400`：

```json
{ "error": "文件不存在: myapp/dev/xxx.png" }
```

---

## 4. 列出文件

```
GET /files/{namespace}/{env}
```

列出指定命名空间 + 环境下的所有文件（存储文件名，按名称排序）。

**curl 示例**：

```bash
curl https://www.xiaojiang.tech/file-server/files/myapp/dev
```

**响应** `200 OK`：

```json
["uuid1_a.png", "uuid2_b.pdf"]
```

目录不存在时返回空数组 `[]`。

---

## 5. 列出环境

```
GET /files/{namespace}
```

列出指定命名空间下的所有环境。

**curl 示例**：

```bash
curl https://www.xiaojiang.tech/file-server/files/myapp
```

**响应** `200 OK`：

```json
["dev", "prod", "test"]
```

---

## 6. 列出所有命名空间

```
GET /files/namespaces
```

**curl 示例**：

```bash
curl https://www.xiaojiang.tech/file-server/files/namespaces
```

**响应** `200 OK`：

```json
["myapp", "other-app"]
```

---

## 7. 删除文件

```
DELETE /files/{namespace}/{env}/{filename}
```

**curl 示例**：

```bash
curl -X DELETE https://www.xiaojiang.tech/file-server/files/myapp/dev/uuid1_a.png
```

**响应** `200 OK`：

```json
{
  "namespace": "myapp",
  "env": "dev",
  "filename": "uuid1_a.png",
  "deleted": true
}
```

`deleted` 为 `false` 表示文件不存在（接口仍返回 200）。

---

## 磁盘存储结构

文件在服务器上按以下结构存放（根目录由配置项 `file.upload-dir` 指定）：

```
{upload-dir}/
└── {namespace}/
    └── {env}/
        ├── {uuid}_{文件名1}
        └── {uuid}_{文件名2}
```
