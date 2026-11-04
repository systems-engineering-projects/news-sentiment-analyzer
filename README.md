# News Sentiment Comparison Tool

Fetches headlines from NewsAPI and RSS, scores how uplifting each one feels with an LLM (Groq or OpenAI), stores a daily rollup in MongoDB, and serves it from a FastAPI API and a React dashboard.

- **Live app:** https://sentimentlens.netlify.app
- **API docs:** https://sentiment-lens.onrender.com/docs
- **Repo:** https://gitlab.com/rclarke009-group/news-sentiment-comparison

The Kubernetes cluster (Prometheus, Grafana, HPA) runs on Docker Desktop only. It is not on the internet. Contact the developer for a live demo.

## Features

- Daily collection from NewsAPI and RSS, with rate-limit delays and a dry-run mode
- LLM sentiment scoring behind a provider swap (Groq / OpenAI)
- FastAPI (`/api/v1`) with health checks and a secret-protected collect endpoint
- In-memory cache for daily reads (today: 5 min; past dates: 24 h)
- React dashboard, Docker Compose, GitLab CI, and Render (`render.yaml`)
- Local Kubernetes practice: CronJob, Prometheus `/metrics`, Grafana, HPA

## Architecture

```
Scheduler (daily) → Collector → NewsAPI / RSS
                            → LLM scores
                            → MongoDB
                            → FastAPI → React
```

## Design decisions

| Choice | Why |
| --- | --- |
| MongoDB | A day's headlines, scores, and rollups are one document. Schema can change without migrations. |
| Daily rollup | One snapshot per side per day. Stats are computed once at collection time and replayed by date. |
| Headlines, not articles | Full text is slower, costlier, and often paywalled. The metric is the tone of what people see first. |
| FastAPI | Async, Pydantic contracts, and OpenAPI docs at `/docs`. |
| Render for the live site | Blueprint deploys the API and cron. GitLab CI validates the live URL; it does not deploy. |
| Kubernetes locally | Same app, for CronJobs, metrics, and HPA. Production traffic stays on Render. |

## CI

[![Pipeline](https://gitlab.com/rclarke009-group/news-sentiment-comparison/badges/main/pipeline.svg)](https://gitlab.com/rclarke009-group/news-sentiment-comparison/-/pipelines)

| Branch | Stages |
| --- | --- |
| Feature / MR | lint (black, ruff, mypy), test |
| develop | + smoke and ZAP against dev |
| staging | + smoke and ZAP against staging |
| main | + smoke against production; prod ZAP is manual |

`API_BASE_URL` / `PROD_API_BASE_URL` must be the real Render host. The pipeline does not read it from Render.

## Prerequisites

Python 3.9+, MongoDB (local or Atlas), Node 18+ for the frontend. Docker is optional. Keys: NewsAPI (100 requests/day on the free tier) and Groq or OpenAI.

## Quick start

**Docker**

```bash
cp .env.example .env   # NEWS_API_KEY, GROQ_API_KEY or OPENAI_API_KEY, MONGODB_URI
docker-compose up -d
docker-compose run --rm collector
```

API: http://localhost:8000 · Docs: http://localhost:8000/docs

**Local Python**

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
docker run -d -p 27017:27017 --name mongodb mongo   # or an Atlas URI
python scripts/run_collector.py                     # --date YYYY-MM-DD, or --dry-run
uvicorn news_sentiment.api.main:app --reload
```

Trigger a deployed run with `POST /api/v1/collect` and header `X-Cron-Secret`. Full steps, caching, and restarts: [documents/QUICKSTART.md](documents/QUICKSTART.md).

## API

Interactive docs: https://sentiment-lens.onrender.com/docs

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/today` | Today's comparison |
| GET | `/api/v1/date/{date}` | One day (`YYYY-MM-DD`) |
| GET | `/api/v1/history?days=7` | Recent days |
| GET | `/api/v1/most-uplifting?side=conservative\|liberal` | Top story for a side |
| GET | `/api/v1/stats?days=30` | Aggregates |
| GET | `/api/v1/health` | Health |
| POST | `/api/v1/collect` | Manual collection (`X-Cron-Secret`) |

A response has `summary` (average uplift and headline count per side), `most_uplifting` (source, headline, score), and `metadata` (model provider, confidence).

Sources live in `news_sentiment/config.py` (NewsAPI ids plus RSS, including Newsmax). A small keyword heuristic nudges scores for clearly uplifting headlines alongside the LLM score.

## Development

```bash
pip install -r requirements-dev.txt
pytest
```

Local API and Vite reload on save. Restart after `requirements.txt`, `.env`, or `package.json` changes. On Render, push the connected branch; the web service start command must be `uvicorn news_sentiment.api.main:app --host 0.0.0.0 --port $PORT`.

## Deploy

| Piece | Where | Notes |
| --- | --- | --- |
| API + daily cron | Render | Cron command is `python scripts/run_collector.py`, not the web start command. Env: `NEWS_API_KEY`, `GROQ_API_KEY` or `OPENAI_API_KEY`, `MONGODB_URI` (not `DATABASE_URL`), `CORS_ORIGINS`. |
| Database | MongoDB Atlas | Free M0 is enough. |
| Frontend | Netlify | Base `frontend`, build `npm run build`, publish `dist`. `VITE_API_URL` must end in `/api/v1` (digit 1). |
| Containers | Docker Compose | [documents/DOCKER.md](documents/DOCKER.md) |
| Cluster practice | Local Kubernetes | [k8s/README.md](k8s/README.md), [documents/Kubernetes-Setup.md](documents/Kubernetes-Setup.md), [documents/STRESS-TEST.md](documents/STRESS-TEST.md). AWS notes: [documents/AWS-DEPLOY.md](documents/AWS-DEPLOY.md). |

Gotchas that have already bitten this project:

- **Render exits immediately** if the web service runs the collector. Uvicorn belongs on the web service; the collector belongs on the cron job.
- **Browser CORS errors** mean the Netlify origin is missing from `CORS_ORIGINS`.
- **404 on `/api/vi/...`** is a path typo. The segment is `v1`.
- **Smoke tests 404 in CI** when `API_BASE_URL` is not the live Render host.

## Lessons learned

- Dates had to be UTC everywhere. Mixing local time broke daily snapshots.
- A truncated env var on the first cloud deploy failed silently until the collector ran.
- On Render's free tier the API slept, so the cron job could not reach it.

## License

MIT
