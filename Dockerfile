# Multi-stage build for production
# Stage 1: Build frontend
FROM node:18-alpine as frontend-build

WORKDIR /app/frontend

# Install dependencies
COPY frontend/package*.json ./
RUN npm ci --only=production

# Copy source and build
COPY frontend/ ./
RUN npm run build

# Stage 2: Build backend
FROM node:18-alpine as backend-build

WORKDIR /app/backend

# Install dependencies
COPY backend/package*.json ./
RUN npm ci --only=production

# Copy source
COPY backend/ ./

# Stage 3: Production runtime
FROM node:18-alpine

# Install necessary packages
RUN apk add --no-cache \
    curl \
    postgresql-client \
    tzdata

# Create app directory
WORKDIR /app

# Copy built frontend
COPY --from=frontend-build /app/frontend/dist ./frontend/dist

# Copy backend
COPY --from=backend-build /app/backend ./backend

# Create necessary directories
RUN mkdir -p uploads logs

# Install PM2 for process management
RUN npm install -g pm2

# Copy entrypoint script
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

# Copy healthcheck
COPY healthcheck.js .

# Set timezone
ENV TZ=Asia/Tashkent

# Expose port
EXPOSE 5000 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node healthcheck.js

# Start application
ENTRYPOINT ["./docker-entrypoint.sh"]
