package com.xiaojiang.fileserver.service;

import com.xiaojiang.fileserver.config.FileStorageProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.net.MalformedURLException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;
import java.util.stream.Stream;

@Service
public class FileStorageService {

    private static final Logger log = LoggerFactory.getLogger(FileStorageService.class);

    /** 命名空间与 env 只允许字母、数字、下划线、中划线，防止路径穿越 */
    private static final Pattern SAFE_NAME_PATTERN = Pattern.compile("[a-zA-Z0-9_-]{1,64}");

    private final Path rootLocation;

    public FileStorageService(FileStorageProperties properties) {
        this.rootLocation = Paths.get(properties.getUploadDir())
                .toAbsolutePath()
                .normalize();
        try {
            Files.createDirectories(rootLocation);
            log.info("文件存储目录: {}", rootLocation);
        } catch (IOException e) {
            throw new IllegalStateException("无法创建文件存储目录: " + rootLocation, e);
        }
    }

    /**
     * 保存上传的文件到指定命名空间 + env，返回存储后的文件名（带 UUID 前缀防止重名冲突）。
     */
    public String store(String namespace, String env, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("上传的文件不能为空");
        }
        String originalFilename = StringUtils.cleanPath(
                file.getOriginalFilename() == null ? "unnamed" : file.getOriginalFilename());
        // 防止路径穿越攻击
        if (originalFilename.contains("..")) {
            throw new IllegalArgumentException("文件名不合法: " + originalFilename);
        }
        String storedFilename = UUID.randomUUID() + "_" + originalFilename;
        Path storageDir = resolveStorageDir(namespace, env);
        try {
            Files.createDirectories(storageDir);
            Path destination = storageDir.resolve(storedFilename);
            try (InputStream in = file.getInputStream()) {
                Files.copy(in, destination, StandardCopyOption.REPLACE_EXISTING);
            }
            log.info("文件上传成功: [{}/{}/{}] -> {}", namespace, env, originalFilename, storedFilename);
            return storedFilename;
        } catch (IOException e) {
            throw new IllegalStateException("保存文件失败: " + originalFilename, e);
        }
    }

    /**
     * 加载文件为可下载的资源。
     */
    public Resource loadAsResource(String namespace, String env, String filename) {
        try {
            Path file = resolveFile(namespace, env, filename);
            Resource resource = new UrlResource(file.toUri());
            if (resource.exists() && resource.isReadable()) {
                return resource;
            }
            throw new IllegalArgumentException("文件不存在: " + namespace + "/" + env + "/" + filename);
        } catch (MalformedURLException e) {
            throw new IllegalArgumentException("文件不存在: " + namespace + "/" + env + "/" + filename, e);
        }
    }

    /**
     * 删除文件，返回是否删除成功。
     */
    public boolean delete(String namespace, String env, String filename) {
        try {
            return Files.deleteIfExists(resolveFile(namespace, env, filename));
        } catch (IOException e) {
            throw new IllegalStateException("删除文件失败: " + filename, e);
        }
    }

    /**
     * 列出指定命名空间 + env 下的所有文件名。
     */
    public List<String> listAll(String namespace, String env) {
        return listChildren(resolveStorageDir(namespace, env), false);
    }

    /**
     * 列出指定命名空间下的所有 env。
     */
    public List<String> listEnvs(String namespace) {
        return listChildren(resolveNamespaceDir(namespace), true);
    }

    /**
     * 列出所有命名空间。
     */
    public List<String> listNamespaces() {
        return listChildren(rootLocation, true);
    }

    /** 列出目录下的子项；directoriesOnly 为 true 时只列目录，否则只列文件。 */
    private List<String> listChildren(Path dir, boolean directoriesOnly) {
        if (!Files.isDirectory(dir)) {
            return List.of();
        }
        try (Stream<Path> stream = Files.list(dir)) {
            return stream.filter(directoriesOnly ? Files::isDirectory : Files::isRegularFile)
                    .map(path -> path.getFileName().toString())
                    .sorted()
                    .toList();
        } catch (IOException e) {
            throw new IllegalStateException("读取目录失败: " + dir, e);
        }
    }

    /** 解析文件名到命名空间 + env 目录内，并防止路径穿越。 */
    private Path resolveFile(String namespace, String env, String filename) {
        Path storageDir = resolveStorageDir(namespace, env);
        Path file = storageDir.resolve(filename).normalize();
        if (!file.startsWith(storageDir)) {
            throw new IllegalArgumentException("文件名不合法: " + filename);
        }
        return file;
    }

    /** 校验并解析命名空间 + env 对应的存储目录。 */
    private Path resolveStorageDir(String namespace, String env) {
        return resolveNamespaceDir(namespace).resolve(validate(env, "env")).normalize();
    }

    /** 校验并解析命名空间对应的存储目录。 */
    private Path resolveNamespaceDir(String namespace) {
        Path resolved = rootLocation.resolve(validate(namespace, "命名空间")).normalize();
        if (!resolved.startsWith(rootLocation)) {
            throw new IllegalArgumentException("命名空间不合法: " + namespace);
        }
        return resolved;
    }

    private String validate(String name, String label) {
        if (name == null || !SAFE_NAME_PATTERN.matcher(name).matches()) {
            throw new IllegalArgumentException(
                    label + "不合法（仅允许字母、数字、下划线、中划线，长度1-64）: " + name);
        }
        return name;
    }
}
