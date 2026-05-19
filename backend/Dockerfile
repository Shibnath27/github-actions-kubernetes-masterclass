# ============================================================
# STAGE 1: Builder (Optimized for caching)
# ============================================================
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Install git (needed for go modules)
RUN apk add --no-cache git

# Copy go mod first (better cache)
COPY go.mod ./

# generate go.sum + fix deps
RUN go mod tidy

# Download dependencies (cached layer)
#RUN go mod download

# Copy source code
COPY . .

# Build optimized binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -mod=readonly -ldflags="-s -w" -o skillpulse .


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