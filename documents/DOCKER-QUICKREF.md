# Docker Quick Reference

Quick reference for common Docker and Docker Compose commands for this project.

## Docker Compose Commands

### Starting Services

```bash
# Start all services (API + MongoDB)
docker-compose up -d

# Start with frontend
docker-compose --profile frontend up -d

# Start in foreground (see logs)
docker-compose up

# Start specific service
docker-compose up -d api
```

### Stopping Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (deletes data!)
docker-compose down -v

# Stop specific service
docker-compose stop api
```

### Viewing Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api

# Last 100 lines
docker-compose logs --tail=100 api

# Since timestamp
docker-compose logs --since 2024-01-01T10:00:00 api
```

### Running Commands

```bash
# Run collector once
docker-compose run --rm collector

# Run shell in API container
docker-compose exec api sh

# Run Python script
docker-compose run --rm api python scripts/setup_db.py

# Run tests
docker-compose exec api pytest
```

### Rebuilding

```bash
# Rebuild after code changes
docker-compose up -d --build

# Rebuild specific service
docker-compose build api

# Force rebuild (no cache)
docker-compose build --no-cache api
```

### Status & Info

```bash
# List running containers
docker-compose ps

# View resource usage
docker stats

# View container details
docker-compose exec api env
```

## Docker Commands

### Building Images

```bash
# Build development image
docker build -t news-sentiment-api:dev --target development .

# Build production image
docker build -t news-sentiment-api:prod --target production .

# Build with no cache
docker build --no-cache -t news-sentiment-api:latest .
```

### Running Containers

```bash
# Run API container
docker run -d \
  --name news-api \
  -p 8000:8000 \
  --env-file .env \
  news-sentiment-api:latest

# Run with custom command
docker run --rm news-sentiment-api:latest python scripts/run_collector.py

# Run interactively
docker run -it --rm news-sentiment-api:latest sh
```

### Managing Containers

```bash
# List running containers
docker ps

# List all containers
docker ps -a

# Stop container
docker stop news-api

# Remove container
docker rm news-api

# View logs
docker logs -f news-api

# Execute command in running container
docker exec -it news-api sh
```

### Images

```bash
# List images
docker images

# Remove image
docker rmi news-sentiment-api:latest

# Tag image
docker tag news-sentiment-api:latest your-registry/news-sentiment-api:v1.0

# Push to registry
docker push your-registry/news-sentiment-api:v1.0

# Pull from registry
docker pull your-registry/news-sentiment-api:v1.0
```

### Cleanup

```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Remove everything unused
docker system prune -a --volumes

# View disk usage
docker system df
```

## MongoDB Commands

### Access MongoDB Shell

```bash
# Via docker-compose
docker-compose exec mongodb mongosh news_sentiment

# Via docker
docker exec -it news-sentiment-mongodb mongosh news_sentiment
```

### Backup & Restore

```bash
# Backup
docker-compose exec mongodb mongodump --out /data/backup

# Restore
docker-compose exec mongodb mongorestore /data/backup

# Export collection
docker-compose exec mongodb mongoexport \
  --db=news_sentiment \
  --collection=daily_comparisons \
  --out=/data/export.json

# Import collection
docker-compose exec mongodb mongoimport \
  --db=news_sentiment \
  --collection=daily_comparisons \
  --file=/data/import.json
```

## Common Workflows

### Fresh Start

```bash
# Stop everything and remove volumes
docker-compose down -v

# Remove images
docker rmi news-sentiment-comparison-api

# Start fresh
docker-compose up -d --build
```

### Development Cycle

```bash
# 1. Start services
docker-compose up -d

# 2. Make code changes (hot reload automatic)

# 3. View logs
docker-compose logs -f api

# 4. Run tests
docker-compose exec api pytest

# 5. Restart if needed
docker-compose restart api
```

### Production Build

```bash
# Build production image
docker build --target production -t news-sentiment-api:v1.0 .

# Test locally
docker run -d \
  --name test-api \
  -p 8000:8000 \
  --env-file .env.production \
  news-sentiment-api:v1.0

# Check logs
docker logs -f test-api

# Tag for registry
docker tag news-sentiment-api:v1.0 your-registry/news-sentiment-api:v1.0

# Push
docker push your-registry/news-sentiment-api:v1.0

# Clean up test
docker stop test-api && docker rm test-api
```

### Debugging

```bash
# Shell into container
docker-compose exec api sh

# Check environment variables
docker-compose exec api env | grep NEWS_API_KEY

# Test MongoDB connection
docker-compose exec api sh
# Inside container:
curl -v telnet://mongodb:27017

# View real-time resource usage
docker stats

# Inspect container
docker inspect news-sentiment-api
```

### Collection Tasks

```bash
# Run collector once
docker-compose run --rm collector

# Run collector for specific date
docker-compose run --rm collector python scripts/run_collector.py --date 2024-01-15

# Dry run (no database save)
docker-compose run --rm collector python scripts/run_collector.py --dry-run

# Trigger via API
curl -X POST http://localhost:8000/api/v1/collect \
  -H "X-Cron-Secret: dev-secret-key"
```

## Environment Variables

### View Current Values

```bash
# In container
docker-compose exec api env

# Specific variable
docker-compose exec api sh -c 'echo $NEWS_API_KEY'
```

### Override Variables

```bash
# Single variable
NEWS_API_KEY=new-key docker-compose up -d

# Different env file
docker-compose --env-file .env.production up -d

# Via command line
docker-compose run --rm -e NEWS_API_KEY=test-key collector
```

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 8000
lsof -i :8000

# Kill process
kill -9 <PID>

# Or use different port
docker-compose run -p 8001:8000 api
```

### Container Won't Start

```bash
# Check logs
docker-compose logs api

# Check if image exists
docker images | grep news-sentiment

# Rebuild
docker-compose build --no-cache api
docker-compose up -d api
```

### Database Connection Failed

```bash
# Check if MongoDB is running
docker-compose ps mongodb

# Check MongoDB logs
docker-compose logs mongodb

# Restart MongoDB
docker-compose restart mongodb

# Check network
docker network ls
docker network inspect news-sentiment-comparison_news-sentiment-network
```

### Out of Disk Space

```bash
# Check disk usage
docker system df

# Clean up
docker system prune -a --volumes

# Remove specific volumes
docker volume ls
docker volume rm news-sentiment-comparison_mongodb_data
```

## Useful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Docker Compose shortcuts
alias dc='docker-compose'
alias dcu='docker-compose up -d'
alias dcd='docker-compose down'
alias dcl='docker-compose logs -f'
alias dcr='docker-compose restart'
alias dce='docker-compose exec'

# Docker shortcuts
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dstop='docker stop $(docker ps -q)'
alias drm='docker rm $(docker ps -aq)'
alias dclean='docker system prune -a --volumes'

# Project-specific
alias news-api='docker-compose exec api'
alias news-logs='docker-compose logs -f api'
alias news-collect='docker-compose run --rm collector'
alias news-test='docker-compose exec api pytest'
```

## Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Complete Docker Guide](DOCKER.md)
- [Kubernetes Deployment](../k8s/README.md)
