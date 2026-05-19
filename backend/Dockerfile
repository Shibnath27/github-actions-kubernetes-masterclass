# ============================================================
# STAGE 1: Builder (Optimized for caching)
# ============================================================
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install git (needed for go modules)
RUN apk add --no-cache git

# Copy go mod first (better cache)
COPY go.mod ./
RUN go mod tidy

# Download dependencies (cached layer)
RUN go mod tidy

# Copy source code
COPY . .

# Build optimized binary
RUN CGO_ENABLED=0 GOOS=linux go build -o skillpulse .

# ============================================================
# STAGE 2: Minimal Runtime (Distroless)
# ============================================================
FROM gcr.io/distroless/static:nonroot

WORKDIR /app

# Copy binary only
COPY --from=builder /app/skillpulse .

# Use non-root user (built-in)
USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["./skillpulse"]