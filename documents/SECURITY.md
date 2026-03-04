# Security

This document describes security practices for the News Sentiment Comparison project.

## Secrets and credentials

- **Never commit** `.env`, `.env.local`, or any file containing API keys, passwords, or tokens.
- Store secrets in environment variables or a secrets manager (e.g. Render env vars, HashiCorp Vault).
- Use `.env.example` as a template only; never put real values there.
- Rotate keys if you suspect exposure (NewsAPI, Groq/OpenAI, MongoDB, `CRON_SECRET_KEY`).

## Pre-commit and CI checks

Run the secret-scanning script before committing:

```bash
./scripts/check_secrets.sh
```

Add it to your workflow (e.g. pre-commit hook or CI step) to reduce the risk of committing secrets.

## Production vs development

- **API docs** (`/docs`, `/redoc`, `/openapi.json`) are disabled by default when `ENV=production` or `RENDER=true`. They can be enabled in production by setting `ENABLE_DOCS=true` (useful for public APIs where you want to allow others to use your API).
- **Debug logging** in the frontend runs only when `import.meta.env.DEV` is true (e.g. `npm run dev`); production builds do not log debug output.

## Secure configuration

- **CORS**: Allowed origins come from `CORS_ORIGINS`; methods and headers are restricted (no `*`).
- **Security headers**: The API adds `X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`, and `Referrer-Policy` to responses.
- **Collection endpoint**: `POST /api/v1/collect` requires the `X-Cron-Secret` header matching `CRON_SECRET_KEY`. Unauthorized attempts are logged with client IP.

## Security testing with OWASP ZAP

The project includes basic OWASP ZAP security testing to identify common vulnerabilities.

### Prerequisites

1. **Install ZAP** (choose one method):

   **Option A: Docker (Recommended - Easiest)**
   ```bash
   docker run -d -p 8080:8080 --name zap zaproxy/zap-stable zap.sh -daemon -host 0.0.0.0 -port 8080 -config api.disablekey=true -config 'api.addrs.addr.name=.*' -config 'api.addrs.addr.regex=true'
   ```
   
   This command:
   - Starts ZAP in daemon mode
   - Disables API key requirement (for local testing)
   - Allows API access from any IP address

   **Option B: ZAP GUI with API Enabled**
   - Download ZAP from https://www.zaproxy.org/download/
   - Open ZAP GUI
   - Go to **Tools → Options → API**
   - Check **"Enable API"** and set port to `8080`
   - Or start from command line: `/Applications/OWASP\ ZAP.app/Contents/Java/zap.sh -daemon -host 0.0.0.0 -port 8080`

   See `scripts/zap_setup_guide.md` for detailed setup instructions.

2. **Install Python dependencies:**
   ```bash
   pip install -r requirements-dev.txt
   ```

### Running ZAP Scans

**Basic scan (local API):**
```bash
# Make sure your API is running on localhost:8000
uvicorn news_sentiment.api.main:app --reload

# In another terminal, run ZAP scan
python scripts/zap_scan.py --target http://localhost:8000
```

**Scan production API:**
```bash
python scripts/zap_scan.py --target https://sentiment-lens.onrender.com
```

**Custom options:**
```bash
# Skip spider scan (only active scan)
python scripts/zap_scan.py --target http://localhost:8000 --skip-spider

# Skip active scan (only spider crawl)
python scripts/zap_scan.py --target http://localhost:8000 --skip-active

# Generate HTML report instead of JSON
python scripts/zap_scan.py --target http://localhost:8000 --report-format HTML

# Custom ZAP URL
python scripts/zap_scan.py --target http://localhost:8000 --zap-url http://localhost:8090
```

### Understanding Results

- **High/Medium risk alerts**: Should be addressed before production deployment
- **Low/Informational alerts**: Review and address as appropriate
- Reports are saved to `zap-reports/` directory by default

### Integration with CI/CD

The project includes a GitLab CI pipeline (`.gitlab-ci.yml`) that runs ZAP scans per environment (dev, staging, production). The pipeline:

- Runs ZAP as a service container
- Scans the API URL per branch: `DEV_API_BASE_URL` (develop), `STAGING_API_BASE_URL` (staging), `PROD_API_BASE_URL` or `API_BASE_URL` (main/master)
- Uses `--fail-on high,medium` to fail the job if High or Medium risk findings are detected
- Saves ZAP reports as artifacts (30-day retention)
- Production ZAP runs only after manual approval (risk management)

**How CI interacts with production:** CI does not deploy; it validates. On push to `main`/`master`, the pipeline runs lint, test, smoke against the production API URL, and (after manual approval) ZAP against production. Production is the live API (e.g. Render) that `PROD_API_BASE_URL`/`API_BASE_URL` points to. Render deploys from the connected Git repo; CI gives confidence before and after that deploy.

**GitLab CI Setup:**
1. Set `DEV_API_BASE_URL`, `STAGING_API_BASE_URL`, and `PROD_API_BASE_URL` (or `API_BASE_URL`) in CI/CD Variables. If dev/staging services do not exist yet, set them to the production URL so pipelines run.
2. Optionally set `ZAP_SKIP=true` to skip ZAP jobs (e.g. on MRs).
3. Pipeline runs per branch (see README branch behavior table).

**Manual CI/CD Integration:**

For other CI/CD platforms (GitHub Actions, Jenkins, etc.):

```yaml
# Example GitHub Actions workflow
- name: Start ZAP
  run: |
    docker run -d -p 8080:8080 --name zap zaproxy/zap-stable zap.sh -daemon

- name: Run ZAP scan
  run: |
    pip install -r requirements-dev.txt
    python scripts/zap_scan.py --target ${{ env.API_BASE_URL }} --fail-on high,medium

- name: Upload ZAP report
  uses: actions/upload-artifact@v3
  with:
    name: zap-report
    path: zap-reports/
```

**Key Features:**
- `--fail-on high,medium` causes the script to exit with code 1 if High or Medium risk findings are detected
- Reports are saved to `zap-reports/` directory (configurable via `--output-dir`)
- Use `--report-format HTML` for human-readable reports, or `JSON` for programmatic parsing

## Dependency hygiene

- Python dependencies are pinned in `requirements.txt`. Periodically run `pip-audit` or `safety check` and update vulnerable packages.
- Frontend: run `npm audit` and address reported issues.

## Reporting vulnerabilities

If you discover a vulnerability, please report it responsibly (e.g. private disclosure to the maintainers) rather than opening a public issue. Include steps to reproduce and impact.

## Incident response

1. Rotate any potentially exposed secrets immediately.
2. Check logs for suspicious activity (e.g. unauthorized `/collect` attempts, unusual traffic).
3. Update dependencies if a vulnerability is in a library.
4. Document the incident and mitigations for future reference.
