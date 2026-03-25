# ============================================================
# Stage 1: Build
# ============================================================
FROM swift:6.0-jammy AS build

WORKDIR /build

# Copy Package manifests first (better layer caching)
COPY Package.swift Package.resolved ./

# Resolve dependencies
RUN swift package resolve

# Copy source code
COPY Sources/ Sources/
COPY Tests/ Tests/
COPY Resources/ Resources/

# Build release binary
RUN swift build -c release --static-swift-stdlib \
    -Xlinker -lstdc++ \
    && mv $(swift build -c release --show-bin-path)/App /build/app

# ============================================================
# Stage 2: Production image
# ============================================================
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libcurl4 \
    libxml2 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from build stage
COPY --from=build /build/app .
COPY --from=build /build/Resources ./Resources
COPY --from=build /build/Public ./Public

# Create non-root user
RUN useradd --create-home --shell /bin/bash vapor
USER vapor

EXPOSE 8080

ENV ENVIRONMENT=production
ENV LOG_LEVEL=info

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["./app"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "8080"]
