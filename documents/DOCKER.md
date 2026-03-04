# Docker Deployment Guide

This guide covers running the News Sentiment Comparison API using Docker and Docker Compose for local development and production deployments.

## Table of Contents

- [Quick Start](#quick-start)
- [Docker Compose Services](#docker-compose-services)
- [Development Workflow](#development-workflow)
- [Production Deployment](#production-deployment)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Prerequisites

- Docker 20.10+ and Docker Compose 2.0+
- `.env` file with API keys (copy from `.env.example`)

### Start All Services

```bash
# Start API and MongoDB
docker-compose up -d

# View logs
docker-compose logs -f

# Check status
docker-compose ps
```

The API will be available at `http://localhost:8000`

### Run Manual Collection

```bash
# Run collector once
docker-compose run --rm collector

# Or use the API endpoint
curl -X POST http://localhost:8000/api/v1/collect \
  -H "X-Cron-Secret: dev-secret-key"
```

### Stop Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (deletes database data)
docker-compose down -v
```

## Docker Compose Services

### Core Services (Always Running)

#### `mongodb`
- **Image**: `mongo:7.0`
- **Port**: `27017`
- **Purpose**: Database for storing headlines and comparisons
- **Data**: Persisted in named volume `mongodb_data`

#### `api`
- **Build**: Multi-stage Dockerfile (development target)
- **Port**: `8000`
- **Purpose**: FastAPI backend with hot reload
- **Features**:
  - Automatic code reload on changes
  - Health checks
  - Non-root user for security

### Optional Services (Profiles)

#### `collector` (Profile: `collector`)
- **Purpose**: Run news collection manually or on schedule
- **Usage**:
  ```bash
  # Run once
  docker-compose run --rm collector
  
  # Or start as service
  docker-compose --profile collector up -d collector
  ```

#### `frontend` (Profile: `frontend`)
- **Image**: `node:20-alpine`
- **Port**: `5173`
- **Purpose**: React frontend with Vite dev server
- **Usage**:
  ```bash
  docker-compose --profile frontend up -d
  ```

## Development Workflow

### 1. Initial Setup

```bash
# Clone repository
git clone <your-repo-url>
cd news-sentiment-comparison

# Copy environment file
cp .env.example .env

# Edit .env with your API keys
vim .env
```

### 2. Start Development Environment

```bash
# Start API + MongoDB
docker-compose up -d

# Start with frontend
docker-compose --profile frontend up -d

# View logs
docker-compose logs -f api
```

### 3. Make Code Changes

The development container automatically reloads when you change code:

```bash
# Edit Python files
vim news_sentiment/api/routes.py

# Changes are immediately reflected (hot reload)
```

### 4. Run Tests

```bash
# Run tests inside container
docker-compose exec api pytest

# Run with coverage
docker-compose exec api pytest --cov=news_sentiment

# Run linting
docker-compose exec api black --check news_sentiment/
docker-compose exec api ruff check news_sentiment/
```

### 5. Access Services

- **API**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs
- **Frontend**: http://localhost:5173 (if started)
- **MongoDB**: `mongodb://localhost:27017`

### 6. Debugging

```bash
# Shell into API container
docker-compose exec api sh

# Shell into MongoDB
docker-compose exec mongodb mongosh

# View real-time logs
docker-compose logs -f api

# Restart a service
docker-compose restart api
```

## Production Deployment

### Build Production Image

```bash
# Build production image (no dev dependencies)
docker build --target production -t news-sentiment-api:latest .

# Test production image
docker run -d \
  --name test-api \
  -p 8000:8000 \
  --env-file .env \
  news-sentiment-api:latest

# Check logs
docker logs -f test-api

# Clean up
docker stop test-api && docker rm test-api
```

### Push to Registry

```bash
# Tag for your registry
docker tag news-sentiment-api:latest your-registry/news-sentiment-api:latest

# Push to registry
docker push your-registry/news-sentiment-api:latest
```

### Production docker-compose.yml

Create a separate `docker-compose.prod.yml`:

```yaml
services:
  api:
    image: your-registry/news-sentiment-api:latest
    restart: always
    ports:
      - "8000:8000"
    environment:
      ENV: production
      MONGODB_URI: ${MONGODB_URI}
      # ... other env vars
    depends_on:
      - mongodb
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  mongodb:
    image: mongo:7.0
    restart: always
    volumes:
      - /data/mongodb:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
```

Deploy:

```bash
docker-compose -f docker-compose.prod.yml up -d
```

## Common Tasks

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api

# Last 100 lines
docker-compose logs --tail=100 api

# Since specific time
docker-compose logs --since 2024-01-01T10:00:00 api
```

### Database Operations

```bash
# Access MongoDB shell
docker-compose exec mongodb mongosh news_sentiment

# Backup database
docker-compose exec mongodb mongodump --out /data/backup

# Restore database
docker-compose exec mongodb mongorestore /data/backup

# Export data
docker-compose exec mongodb mongoexport \
  --db=news_sentiment \
  --collection=daily_comparisons \
  --out=/data/export.json
```

### Resource Management

```bash
# View resource usage
docker stats

# Clean up unused resources
docker system prune -a

# Remove volumes (deletes data!)
docker volume prune

# View disk usage
docker system df
```

### Rebuild After Changes

```bash
# Rebuild API image
docker-compose build api

# Rebuild and restart
docker-compose up -d --build api

# Force rebuild (no cache)
docker-compose build --no-cache api
```

### Run One-Off Commands

```bash
# Run collector once
docker-compose run --rm collector

# Run custom script
docker-compose run --rm api python scripts/setup_db.py

# Run shell
docker-compose run --rm api sh

# Run with different command
docker-compose run --rm api python -c "print('Hello')"
```

### Environment Variables

```bash
# Override env vars
NEWS_API_KEY=new-key docker-compose up -d

# Use different env file
docker-compose --env-file .env.production up -d

# Check env vars in container
docker-compose exec api env | grep NEWS_API_KEY
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker-compose logs api

# Check if port is in use
lsof -i :8000

# Remove and recreate
docker-compose down
docker-compose up -d
```

### Database Connection Issues

```bash
# Check if MongoDB is running
docker-compose ps mongodb

# Check MongoDB logs
docker-compose logs mongodb

# Test connection from API container
docker-compose exec api sh
# Inside container:
curl -v telnet://mongodb:27017
```

### Hot Reload Not Working

```bash
# Check if volumes are mounted
docker-compose exec api ls -la /app/news_sentiment

# Restart with rebuild
docker-compose down
docker-compose up -d --build
```

### Out of Memory

```bash
# Check resource usage
docker stats

# Increase Docker memory limit (Docker Desktop)
# Settings → Resources → Memory → Increase

# Or disable local sentiment model
echo "USE_LOCAL_SENTIMENT=false" >> .env
docker-compose restart api
```

### Permission Issues

```bash
# Fix ownership (if volumes have wrong permissions)
docker-compose exec api chown -R appuser:appuser /app

# Or run as root temporarily
docker-compose exec -u root api sh
```

### Clean Slate

```bash
# Stop everything
docker-compose down -v

# Remove images
docker rmi news-sentiment-comparison-api

# Remove all containers and volumes
docker system prune -a --volumes

# Start fresh
docker-compose up -d --build
```

## Docker Best Practices

### Multi-Stage Builds

The Dockerfile uses multi-stage builds to:
- Reduce final image size
- Separate build and runtime dependencies
- Improve security by minimizing attack surface

### Security

- ✅ Runs as non-root user (`appuser`)
- ✅ Uses official base images
- ✅ Minimal system dependencies
- ✅ No secrets in image layers
- ✅ Health checks configured

### Performance

- ✅ Layer caching optimized
- ✅ Dependencies installed before code copy
- ✅ `.dockerignore` excludes unnecessary files
- ✅ Named volumes for persistent data

### Development Experience

- ✅ Hot reload enabled in dev mode
- ✅ Source code mounted as volume
- ✅ Separate dev and prod stages
- ✅ Docker Compose profiles for optional services

## Next Steps

- [Kubernetes Deployment](../k8s/README.md) - Deploy to Kubernetes
- [CI/CD Pipeline](../.gitlab-ci.yml) - Automated testing and deployment
- [Production Checklist](../README.md#deployment) - Deploy to cloud platforms

## Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
