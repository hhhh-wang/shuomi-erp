# SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment
# 后端镜像：构建上下文为项目根目录
#   docker build -f docker/backend.Dockerfile -t shuomi-erp-backend .

# ---------- 构建 ----------
FROM --platform=$BUILDPLATFORM eclipse-temurin:17-jdk AS build
WORKDIR /src
# Gradle 依赖缓存在 BuildKit 缓存中，重复构建不会重新下载
COPY . .
RUN --mount=type=cache,target=/root/.gradle \
    chmod +x gradlew && ./gradlew --no-daemon :lemon-admin:bootJar

# ---------- 运行 ----------
FROM eclipse-temurin:17-jre
# 国内网络默认使用中科大 Ubuntu 镜像；海外构建可传 --build-arg APT_MIRROR=archive.ubuntu.com
ARG APT_MIRROR=mirrors.ustc.edu.cn
ENV DEBIAN_FRONTEND=noninteractive
# 中文字体：单据打印（JasperReports）排版时用来测量文字宽度；curl 用于健康检查
RUN sed -i "s@archive.ubuntu.com@${APT_MIRROR}@g; s@security.ubuntu.com@${APT_MIRROR}@g" /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends fontconfig fonts-noto-cjk curl \
    && rm -rf /var/lib/apt/lists/*
ENV TZ=Asia/Shanghai \
    SPRING_PROFILES_ACTIVE=prod \
    UPLOAD_PATH=/data/uploads \
    LEMON_UPLOAD_ATTACHMENTPATH=/data/attachments \
    JAVA_OPTS="-Xms512m -Xmx1g"
WORKDIR /app
COPY LICENSE /app/licenses/LICENSE
COPY --from=build /src/lemon-admin/build/libs/lemon-erp.jar /app/lemon-erp.jar
VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=120s --retries=5 \
    CMD curl -fs http://localhost:8080/api/auth/config > /dev/null || exit 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/lemon-erp.jar"]
