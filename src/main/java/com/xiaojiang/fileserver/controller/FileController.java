package com.xiaojiang.fileserver.controller;

import com.xiaojiang.fileserver.service.FileStorageService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/files")
public class FileController {

    private final FileStorageService storageService;

    public FileController(FileStorageService storageService) {
        this.storageService = storageService;
    }

    /** 上传文件（单文件），需指定命名空间和 env */
    @PostMapping("/upload")
    public ResponseEntity<Map<String, String>> upload(@RequestParam("namespace") String namespace,
                                                      @RequestParam("env") String env,
                                                      @RequestParam("file") MultipartFile file) {
        String storedFilename = storageService.store(namespace, env, file);
        return ResponseEntity.ok(Map.of(
                "namespace", namespace,
                "env", env,
                "filename", storedFilename,
                "url", buildDownloadUrl(namespace, env, storedFilename)));
    }

    /** 上传多个文件到同一命名空间 + env */
    @PostMapping("/upload/batch")
    public ResponseEntity<List<Map<String, String>>> uploadBatch(
            @RequestParam("namespace") String namespace,
            @RequestParam("env") String env,
            @RequestParam("files") List<MultipartFile> files) {
        List<Map<String, String>> results = files.stream().map(file -> {
            String storedFilename = storageService.store(namespace, env, file);
            return Map.of(
                    "namespace", namespace,
                    "env", env,
                    "filename", storedFilename,
                    "url", buildDownloadUrl(namespace, env, storedFilename));
        }).toList();
        return ResponseEntity.ok(results);
    }

    /** 下载文件 */
    @GetMapping("/{namespace}/{env}/{filename:.+}")
    public ResponseEntity<Resource> download(@PathVariable String namespace,
                                             @PathVariable String env,
                                             @PathVariable String filename,
                                             HttpServletRequest request) throws IOException {
        Resource resource = storageService.loadAsResource(namespace, env, filename);

        String contentType = request.getServletContext()
                .getMimeType(resource.getFile().getAbsolutePath());
        if (contentType == null) {
            contentType = MediaType.APPLICATION_OCTET_STREAM_VALUE;
        }
        String encodedFilename = URLEncoder.encode(resource.getFilename(), StandardCharsets.UTF_8)
                .replace("+", "%20");
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(contentType))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename*=UTF-8''" + encodedFilename)
                .body(resource);
    }

    /** 列出指定命名空间 + env 下的所有文件 */
    @GetMapping("/{namespace}/{env}")
    public ResponseEntity<List<String>> list(@PathVariable String namespace,
                                             @PathVariable String env) {
        return ResponseEntity.ok(storageService.listAll(namespace, env));
    }

    /** 列出指定命名空间下的所有 env */
    @GetMapping("/{namespace}")
    public ResponseEntity<List<String>> listEnvs(@PathVariable String namespace) {
        return ResponseEntity.ok(storageService.listEnvs(namespace));
    }

    /** 列出所有命名空间 */
    @GetMapping("/namespaces")
    public ResponseEntity<List<String>> listNamespaces() {
        return ResponseEntity.ok(storageService.listNamespaces());
    }

    /** 删除文件 */
    @DeleteMapping("/{namespace}/{env}/{filename:.+}")
    public ResponseEntity<Map<String, Object>> delete(@PathVariable String namespace,
                                                      @PathVariable String env,
                                                      @PathVariable String filename) {
        boolean deleted = storageService.delete(namespace, env, filename);
        return ResponseEntity.ok(Map.of(
                "namespace", namespace,
                "env", env,
                "filename", filename,
                "deleted", deleted));
    }

    /** 返回文件相对路径（下载由 nginx 直接代理存储目录，拼接域名即可访问） */
    private String buildDownloadUrl(String namespace, String env, String filename) {
        return "/" + namespace + "/" + env + "/" + filename;
    }
}
