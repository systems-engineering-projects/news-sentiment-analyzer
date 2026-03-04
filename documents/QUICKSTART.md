# Quick Start Guide

Get up and running in 5 minutes!

## 1. Setup Python Backend

```bash
cd news-sentiment-comparison

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## 2. Configure Environment

```bash
# Copy example env file
cp .env.example .env

# Edit .env and add your API keys:
# - NEWS_API_KEY (get from https://newsapi.org)
# - GROQ_API_KEY (get from https://console.groq.com) OR OPENAI_API_KEY
# - MONGODB_URI (default: mongodb://localhost:27017/news_sentiment)
```

## 3. Start MongoDB

**Option A: Docker (Recommended)**
```bash
docker run -d -p 27017:27017 --name mongodb mongo
```

**Option B: MongoDB Atlas (Cloud)**
- Sign up at https://www.mongodb.com/cloud/atlas
- Create free cluster
- Get connection string and update `MONGODB_URI` in `.env`

## 4. Setup Database

```bash
python scripts/setup_db.py
```

## 5. Run Your First Collection

```bash
python scripts/run_collector.py
```
#the run_collector above will
#answer: it will fetch headlines, score them, and save to MongoDB.


## 6. Start the API Server

```bash
uvicorn news_sentiment.api.main:app --reload
```

#the uvicorn command above will start the API server.
#the API server will be available at http://localhost:8000
#the API server will have the following endpoints:
#- GET /api/v1/today
#- GET /api/v1/date/{date}
#- GET /api/v1/history?days=7
#- GET /api/v1/most-uplifting?side=conservative&date={date}
#- GET /api/v1/stats?days=30
#- GET /api/v1/health

API available at: http://localhost:8000
- API Docs: http://localhost:8000/docs


## 7. Setup React Frontend

```bash
cd frontend

# Install dependencies
npm install

# Start dev server
npm run dev
```

Frontend available at: http://localhost:3000

## Test It Out

1. **Run collection**: `python scripts/run_collector.py`
2. **Check API**: Visit http://localhost:8000/api/v1/today
3. **View dashboard**: Visit http://localhost:3000

## Making Code Changes & Restarting

### Local development

| What changed | API (uvicorn) | Frontend (npm run dev) | Collector / cron |
|--------------|---------------|------------------------|------------------|
| **Python code** (e.g. `news_sentiment/`, `scripts/`) | Auto-reloads (`--reload`) | — | Re-run `python scripts/run_collector.py` or wait for next cron |
| **Frontend code** (e.g. `frontend/src/`) | — | Hot reload (HMR) | — |
| **`requirements.txt`** | Restart API: `Ctrl+C` then `uvicorn news_sentiment.api.main:app --reload` | — | Re-run collector after restarting |
| **`frontend/package.json`** or new deps | — | Restart: `Ctrl+C` then `npm run dev` | — |
| **`.env`** or env vars | Restart API | Restart frontend if `VITE_*` vars change | Re-run collector |

**Restarting locally:**

```bash
# API (from project root, with venv activated)
uvicorn news_sentiment.api.main:app --reload

# Frontend
cd frontend && npm run dev

# One-off collector run
python scripts/run_collector.py
```

### Caching

The API caches daily comparison reads (for `/today`, `/date/{date}`, and `/most-uplifting`) in memory by date. **What is cached:** Results of `get_daily_comparison(date)` keyed by `YYYY-MM-DD`. **TTL:** "Today" (UTC) uses a short TTL (default 5 minutes) so that after the collector runs, the API serves fresh data within a few minutes. Past dates use a longer TTL (default 24 hours). **Invalidation:** When the API process writes a daily comparison (e.g. via an admin endpoint), the cache for that date is invalidated so the next read sees fresh data. **Cross-process:** The collector runs in a separate process (cron or script), so when it saves data, the API's in-memory cache is *not* invalidated; staleness for that date is cleared only when the cache entry's TTL expires. Rely on the short TTL for "today" so fresh "today" data appears soon after the collector runs.

**Architecture before cache (every request hits the database):**

```
Client  ──►  FastAPI Routes  ──►  MongoDB  (every request)
```

**Architecture after cache (cache hit avoids DB; miss fills cache):**

```
Client  ──►  FastAPI Routes  ──►  Cache (hit)  ──►  return
                    │
                    └──►  Cache (miss)  ──►  MongoDB  ──►  set cache  ──►  return
```

**Environment variables (optional):**

| Variable | Default | Description |
|----------|---------|--------------|
| `CACHE_ENABLED` | (enabled) | Set to `false` or `0` to disable caching. |
| `CACHE_TTL_TODAY_SECONDS` | `300` | TTL in seconds for "today" (5 min). |
| `CACHE_TTL_PAST_SECONDS` | `86400` | TTL in seconds for past dates (24 h). |

### Render (production)

| What changed | API | Frontend | Cron (collector) |
|--------------|-----|----------|------------------|
| **Application code** (push to Git) | Auto redeploy on push | Auto redeploy on push | Uses new code on next scheduled run |
| **Env vars** (Dashboard → Environment) | Redeploy required | Redeploy required | Next run uses new vars |
| **`render.yaml`** (new services, etc.) | Update via Blueprint sync | — | — |

**Update and restart on Render:**

1. **Code changes:** Push to your connected branch (e.g. `main`). Render builds and deploys the API and frontend automatically.
2. **Env var changes:** In [Render Dashboard](https://dashboard.render.com) → your service → **Environment** → Save. Then **Manual Deploy** → **Deploy latest commit** (or trigger a redeploy).
3. **Manual redeploy:** Dashboard → service → **Manual Deploy** → **Deploy latest commit**.
4. **Cron:** No “restart.” It runs on a schedule; each run uses the current code and env from the last deploy. To run immediately, use **Cron Job** → **Trigger Run** (or equivalent).

**Blueprint (multi-service):** If you use the `render.yaml` Blueprint, push code changes as above; both API and frontend redeploy. Adjust env vars per service in the dashboard, then redeploy each service as needed.

### Smoke testing production

After you deploy (or redeploy) the API, run a quick smoke test to verify the production API is up and returning expected data:

```bash
# Default base URL (blueprint: news-sentiment-api.onrender.com)
python scripts/smoke_test_production.py

# Your Render service uses a different URL (e.g. sentiment-lens)
python scripts/smoke_test_production.py --base-url https://your-api.onrender.com

# Verbose: print response details
python scripts/smoke_test_production.py --base-url https://your-api.onrender.com -v
```

**When to use it:**

- **After a deploy** — Once Render reports "Your service is live", run the smoke test to confirm health, sources, today, and history endpoints respond as expected.
- **After env var changes** — If you updated API keys or `MONGODB_URI` in the Render dashboard and redeployed, run it to catch config issues.
- **Debugging prod vs local** — When something works locally but not in production, run the script against your production URL to see which endpoint fails.
- **Ongoing checks** — Optionally run from CI or a separate cron to detect outages.

The script exits 0 on success and 1 if any check fails. Use `--base-url` when your API service has a different hostname than the blueprint default (e.g. you named the service `sentiment-lens` → `https://sentiment-lens.onrender.com`). For Playwright E2E (frontend + API), see **Playwright E2E** below.

### Playwright E2E (frontend + API)

For browser-based checks of the frontend and API, use Playwright from `frontend/`:

```bash
cd frontend
npm install
npx playwright install   # first time only
```

- **Local:** Run API and frontend (`uvicorn …` and `npm run dev`), then:
  - `npm run test:e2e` — frontend smoke + API tests
  - `npm run test:api` — API tests only
- **Production:** After deploying:
  - `npm run test:api:prod` — API tests against production (e.g. Render).
  - `npm run test:e2e:prod` — E2E using production base URL. To test the live **frontend** (e.g. Netlify), run:

    ```bash
    PLAYWRIGHT_BASE_URL=https://sentimentlens.netlify.app npm run test:e2e
    ```

Use these **after deploys** alongside the Python smoke script: smoke script for API-only checks, Playwright for frontend + API.

## Troubleshooting

### MongoDB Connection Failed
- Check if MongoDB is running: `docker ps | grep mongo`
- Verify `MONGODB_URI` in `.env`

### API Key Errors
- NewsAPI: Sign up at https://newsapi.org (free tier: 100 req/day)
- Groq: Sign up at https://console.groq.com (free tier available)
- OpenAI: Sign up at https://platform.openai.com

### Checking Render Logs (Production Issues)

If you're experiencing issues in production (e.g., all scores are 0, collection failures), **always check Render logs first**:

1. **Access Render Logs:**
   - Go to [Render Dashboard](https://dashboard.render.com) → Your service → **Logs** tab

2. **What to Look For:**
   - **API Key Errors**: `401`, `AuthenticationError`, or `Incorrect API key provided` → Update the key in Render Environment
   - **Scoring Errors**: `Error scoring headline` or `LLM API error` → Check API key validity
   - **Collection Results**: `Collection completed for` shows `avg_uplift` (should be non-zero)
   - **Save Verification**: `Saving headlines with scores - sample: final_score=...` confirms scores before saving

3. **Common Fixes:**
   - Invalid API key → Update `OPENAI_API_KEY` in Render with the **full key** (no truncation)
   - All scores zero → Check logs for scoring errors, then fix API key and redeploy

### Frontend Can't Connect to API
- Make sure API is running on port 8000
- Check `vite.config.ts` proxy configuration
- Check CORS settings in `api/main.py`

## 8. Set Up Daily Automation (Cron Job)

To automatically collect news headlines daily, set up a cron job:

### Step 1: Create Wrapper Script

The wrapper script `scripts/cron_collect.sh` should already exist. If not, create it:

```bash
chmod +x scripts/cron_collect.sh
```

### Step 2: Test the Script

```bash
./scripts/cron_collect.sh
```

### Step 3: Add Cron Job

```bash
crontab -e
```

Add this line (runs daily at 10:00 AM - adjust time as needed):

```cron
0 10 * * * /Users/rebeccaclarke/Documents/Financial/Gigs/devops_software_engineering/conceptprojects/news-sentiment-comparison/scripts/cron_collect.sh >> /tmp/news-collector.log 2>&1
```

**Cron time format:** `minute hour * * *`
- `0 10 * * *` = 10:00 AM daily
- `0 6 * * *` = 6:00 AM daily
- `0 0 * * *` = Midnight daily

### Step 4: Verify

```bash
# List your cron jobs
crontab -l

# Check the log after it runs
cat /tmp/news-collector.log
```

**Note:** Cron jobs only run when your computer is on and awake. For production, deploy to a cloud host (see Deployment section below).

## 9. Deploy to Production

### Option A: Deploy to Render (Blueprint — recommended)

The repo includes a `render.yaml` Blueprint that deploys the **API**, **frontend**, and **daily cron** in one go.

1. **MongoDB Atlas (required first):**
   - Sign up at https://www.mongodb.com/cloud/atlas
   - Create a free M0 cluster, database user, and allow `0.0.0.0/0` in Network Access
   - Copy your connection string: `mongodb+srv://user:pass@cluster.mongodb.net/news_sentiment`

2. **Connect the Blueprint:**
   - Go to [Render Blueprints](https://dashboard.render.com/blueprints)
   - Click **New → Blueprint**
   - Connect the `news-sentiment-comparison` GitHub repo and select the branch

3. **Add secrets when prompted:**
   - `NEWS_API_KEY` — from https://newsapi.org
   - `GROQ_API_KEY` **or** `OPENAI_API_KEY` — Groq: https://console.groq.com; OpenAI: https://platform.openai.com
   - `MONGODB_URI` — your Atlas connection string

4. **Deploy.** Render creates:
   - **news-sentiment-api** — FastAPI at `https://news-sentiment-api.onrender.com`
   - **news-sentiment-frontend** — React app at `https://news-sentiment-frontend.onrender.com`
   - **news-sentiment-collector** — Cron job (daily 10:00 AM UTC)
   
   **Note:** If you're on Render's free tier, the cron job service won't work (jobs require Starter plan). See "Using cron-job.org (Free Tier Alternative)" below.

5. **Run the DB setup once:**  
   Locally, set `MONGODB_URI` to your Atlas URL and run:
   ```bash
   python scripts/setup_db.py
   ```
   Then trigger a manual run of the collector in Render, or wait for the first scheduled run.

6. **Force collector to use Groq/OpenAI (avoid OOM):**  
   If the cron hits "Out of memory (used over 512Mi)" or loads DistilBERT, ensure it uses the API instead of the local model:
   - **Render Dashboard** → **Cron Jobs** → **news-sentiment-collector** (or **news-sentiment-collector-evening**).
   - **Environment** → Add or edit: **Key** `USE_LOCAL_SENTIMENT`, **Value** `false` (no quotes).
   - **Save**, then **Manual Deploy** → **Deploy latest commit** (or **Trigger Run** to re-run the cron).
   The Blueprint sets this in `render.yaml`; set it in the Dashboard if it’s missing or overridden.

### Using cron-job.org (Free Tier Alternative)

If you're using Render's free tier (which doesn't support cron jobs), use cron-job.org to trigger collection:

#### Step 1: Generate a Secret Key

Generate a secure random secret key:

```bash
# macOS/Linux
openssl rand -hex 32

# Or Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

#### Step 2: Add Secret to Render

1. Go to Render dashboard → Your API service → Environment
2. Add environment variable:
   - **Key**: `CRON_SECRET_KEY`
   - **Value**: Your generated secret key
3. Save and redeploy

#### Step 3: Create cron-job.org Account

1. Sign up at https://cron-job.org (free)
2. Verify your email

#### Step 4: Create Cron Job

1. Click **"Create cronjob"**
2. Configure:
   - **Title**: `News Sentiment Collection`
   - **Address (URL)**: `https://your-api-url.onrender.com/api/v1/collect`
     - Replace with your actual Render API URL
   - **Request method**: `POST`
   - **Request headers**: Add header:
     - **Name**: `X-Cron-Secret`
     - **Value**: Your `CRON_SECRET_KEY` value
   - **Schedule**: 
     - Daily at 10 AM UTC: `0 10 * * *`
     - Daily at 2 AM UTC (9 PM EST): `0 2 * * *`
   - **Activate cronjob**: ✓
3. Click **"Create cronjob"**

#### Step 5: Test

Test the endpoint manually:

```bash
curl -X POST https://your-api-url.onrender.com/api/v1/collect \
  -H "X-Cron-Secret: your_secret_key"
```

You should see a JSON response with collection results.

#### Monitor

- **cron-job.org**: Check "Executions" tab for run history
- **Render**: Check API service logs for collection activity

**Custom domains:** In each service’s Render dashboard, add your domain under **Settings → Custom Domains**. Update `CORS_ORIGINS` on the API to include your frontend URL.

### Option B: Frontend on Netlify + Backend elsewhere

1. **Build the frontend:**
   ```bash
   cd frontend
   npm run build
   ```

2. **Deploy to Netlify:**
   - Go to https://app.netlify.com
   - **Option A:** Drag and drop the `frontend/dist` folder (no build settings needed)
   - **Option B:** Connect your Git repository (recommended for auto-deploys)

3. **If using Git-based deploy, configure build settings:**
   
   In Netlify → **Site settings → Build & deploy → Build settings**, set:
   
   | Setting | Value |
   |---------|-------|
   | **Base directory** | `frontend` |
   | **Build command** | `npm run build` |
   | **Publish directory** | `dist` |

   **Note:** Use Base directory `frontend` (not `news-sentiment-comparison/frontend`) when the repo is the project itself. Use **`v1`** (digit 1) in the API URL, not **`vi`**. Do not use `pip` for the frontend build.

4. **Set environment variable:**
   - In Netlify: **Site settings → Environment variables**
   - Add: `VITE_API_URL` = `https://your-api-host.com/api/v1`
   - Use your deployed backend API URL (from Render/Railway/etc.). Use **v1** (digit one), not **vi**.
   - **Redeploy** after adding the variable

### Backend on Cloud Host

Deploy your FastAPI backend to:
- **Render** (recommended): Free tier, easy setup
- **Railway**: Simple deployment
- **Fly.io**: More control

#### Render Deployment Settings

**⚠️ Prerequisite: MongoDB Atlas**
You need a MongoDB Atlas cluster before the app will work on Render. The app requires a database connection at startup. You can set up Atlas in parallel with your Render deployment.

**Quick MongoDB Atlas Setup (5-10 minutes):**
1. Sign up at https://www.mongodb.com/cloud/atlas
2. Create a free M0 cluster (takes ~5 minutes to provision)
3. Create a database user (Database Access → Add New User)
4. Whitelist IP addresses (Network Access → Add IP Address → Allow Access from Anywhere: `0.0.0.0/0`)
5. Get connection string (Database → Connect → Connect your application)
6. Copy the connection string (format: `mongodb+srv://username:password@cluster.mongodb.net/news_sentiment`)

When creating a new Web Service on Render:

**Required Settings:**
- **Environment:** Python 3
- **Build Command:** `pip install -r requirements.txt` (or leave blank if auto-detected)
- **Start Command:** `uvicorn news_sentiment.api.main:app --host 0.0.0.0 --port $PORT`
  - ⚠️ **Critical:** The Web Service must use this uvicorn command. Do **not** use `python scripts/run_collector.py` for the Web Service—that is for the Cron Job only (collector runs once and exits).
  - Render sets `$PORT`; `--host 0.0.0.0` allows external connections.

**Root Directory:**
- **Not needed** if deploying from the `news-sentiment-comparison` directory
- Only specify if deploying from a parent monorepo (set to `news-sentiment-comparison`)

**Environment Variables:**
Set these in Render dashboard → Environment:
- `NEWS_API_KEY` - Your NewsAPI key
- `GROQ_API_KEY` - Your Groq API key (or use `OPENAI_API_KEY` instead)
- `MONGODB_URI` - MongoDB Atlas connection string (⚠️ **Required** - app uses this only; `DATABASE_URL` is not used)
- `CORS_ORIGINS` - Must include your frontend origin (e.g. `https://your-site.netlify.app`) or the browser will block API requests

**Note:** You can create the Render service first and add the `MONGODB_URI` environment variable once you have your Atlas connection string. The app will connect on the next deploy/restart.

**Set up cron on cloud host:**
- Render: Use "Cron Job" service type
- Railway: Use scheduled tasks
- Or use external cron service (cron-job.org) to call an API endpoint

See README.md for detailed deployment instructions. For common deployment issues (base directory, CORS, v1 vs vi, smoke test 404), see **README.md → Troubleshooting → Deployment Gotchas**.

## Next Steps

- Customize news sources in `config.py`
- Add more visualizations to the dashboard
- Deploy to production for 24/7 availability
