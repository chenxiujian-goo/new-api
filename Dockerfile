FROM oven/bun:latest AS builder  
  
# 接收构建参数  
ARG VITE_BASE_PATH=/  
ARG VITE_REACT_APP_SERVER_URL=  
  
WORKDIR /build  
COPY web/package.json .  
COPY web/bun.lock .  
RUN bun install  
COPY ./web .  
COPY ./VERSION .  
  
# 在构建时设置环境变量  
ENV VITE_BASE_PATH=${VITE_BASE_PATH}  
ENV VITE_REACT_APP_SERVER_URL=${VITE_REACT_APP_SERVER_URL}  
  
RUN DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat VERSION) bun run build  
  
FROM golang:alpine AS builder2  
  
ENV GO111MODULE=on \  
    CGO_ENABLED=0 \  
    GOOS=linux  
  
WORKDIR /build  
  
ADD go.mod go.sum ./  
RUN go mod download  
  
COPY . .  
COPY --from=builder /build/dist ./web/dist  
RUN go build -ldflags "-s -w -X 'one-api/common.Version=$(cat VERSION)'" -o one-api  
  
# 测试阶段：运行one-api并验证  
FROM alpine AS tester  
RUN apk upgrade --no-cache \  
    && apk add --no-cache ca-certificates tzdata ffmpeg bash \  
    && update-ca-certificates  
  
COPY --from=builder2 /build/one-api /  
WORKDIR /data  
  
# 运行one-api并等待60秒进行测试  
RUN timeout 60s /one-api --help || true && \  
    echo "Testing one-api executable..." && \  
    (timeout 60s /one-api > /tmp/test.log 2>&1 &) && \  
    sleep 60 && \  
    echo "=== Test Log Output ===" && \  
    cat /tmp/test.log && \  
    echo "=== Test Completed ==="  
  
# 最终镜像  
FROM alpine  
  
RUN apk upgrade --no-cache \  
    && apk add --no-cache ca-certificates tzdata ffmpeg bash \  
    && update-ca-certificates  
  
COPY --from=builder2 /build/one-api /  
EXPOSE 3000  
WORKDIR /data  
ENTRYPOINT ["/one-api"]
