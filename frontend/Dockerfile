# ============================================================
# STAGE: Secure Nginx Runtime
# ============================================================
FROM alpine:latest AS builder
WORKDIR /app
COPY . .

FROM nginx:mainline-alpine-slim


# Copy static assets
COPY --from=builder /app/index.html /usr/share/nginx/html/
COPY --from=builder /app/css /usr/share/nginx/html/css
COPY --from=builder /app/js /usr/share/nginx/html/js

# Copy custom nginx configuration
COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf



EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]