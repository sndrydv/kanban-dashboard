
# Stage 1: Build React application
FROM node:22-alpine AS builder

WORKDIR /app

# Copy dependency manifests
COPY package*.json ./

# Install exact dependencies
RUN npm ci

# Copy source code
COPY . .

# Build production application
RUN npm run build


# Stage 2: Production runtime
FROM nginx:alpine AS runtime

# Create non-root user
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup && \
    mkdir -p /var/cache/nginx /var/run /tmp/nginx && \
    chown -R appuser:appgroup \
      /var/cache/nginx /var/run /tmp/nginx /usr/share/nginx/html

# Copy custom Nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy only production build artifacts
COPY --from=builder --chown=appuser:appgroup \
    /app/dist /usr/share/nginx/html

# Run Nginx on an unprivileged port
EXPOSE 8080

USER appuser

HEALTHCHECK --interval=30s --timeout=3s \
    --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
