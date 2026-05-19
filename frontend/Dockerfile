# ============================================================
# STAGE: Secure Nginx Runtime
# ============================================================
FROM alpine:latest AS builder
WORKDIR /app
COPY . .

FROM nginx:mainline-alpine-slim

# Remove default config
#RUN rm -rf /etc/nginx/conf.d/*

# Copy static assets
COPY --from=builder /app/index.html /usr/share/nginx/html/
COPY --from=builder /app/css /usr/share/nginx/html/css
COPY --from=builder /app/js /usr/share/nginx/html/js

# Copy custom nginx configuration
COPY --from=builder /app/nginx.conf /etc/nginx/conf.d/default.conf

# Set correct permissions
#RUN chown -R nginx:nginx /usr/share/nginx/html

# Switch to non-root user
#USER nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]