# Techflow Project — Technical Documentation

**Export to Word:** from the repo root run `python scripts/markdown_to_docx.py` to generate `DOCUMENTATION.docx` (requires `python-docx`: `pip install python-docx`).

This document describes the **Techflow** CI/CD project: a Flask application packaged with Docker, tested and deployed via GitHub Actions to AWS EC2.

---

## Table of contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Project structure](#project-structure)
4. [Application](#application)
5. [Local development](#local-development)
6. [Docker](#docker)
7. [CI/CD pipeline](#cicd-pipeline)
8. [Configuration (secrets & variables)](#configuration-secrets--variables)
9. [EC2 deployment](#ec2-deployment)
10. [Operational scripts](#operational-scripts)
11. [Testing](#testing)
12. [Security (Bandit)](#security-bandit)
13. [Troubleshooting](#troubleshooting)

---

## Overview

| Item | Description |
|------|-------------|
| **Purpose** | Demonstrate an automated pipeline: test → build/push image → deploy to EC2, with health checks and optional rollback. |
| **Runtime** | Python 3.11, Flask 3.x |
| **Container** | Debian Bookworm–based image, non-root user |
| **CI/CD** | GitHub Actions (`test`, `build`, `deploy`) |
| **Hosting** | Docker on Ubuntu EC2 (port 80 → container 5000) |

---

## Architecture

```
Developer (push / PR)
        │
        ▼
┌───────────────────┐
│  GitHub Actions   │
│  • test (pytest)  │
│  • build + push   │──────► Docker Hub (image: latest + SHA)
│  • deploy (SSH)   │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  AWS EC2 (Ubuntu) │
│  Docker: pull &   │
│  run container    │──────► http://EC2_IP/  (Flask :5000)
└───────────────────┘
```

- **Pull requests** to `main` run **tests only** (same `test` job; `build`/`deploy` still depend on `test` but typically you’d gate deploy on `push` only—see [CI/CD pipeline](#cicd-pipeline)).
- **Push to `main`** runs the full pipeline: test → build → deploy.

---

## Project structure

```
Techflow-Project/
├── app.py                 # Flask app (challenge: do not modify)
├── test_app.py            # Pytest suite (challenge: do not modify)
├── requirements.txt       # Python dependencies
├── requirements-dev.txt   # Dev/CI: tests + Bandit (optional local)
├── pyproject.toml         # Bandit config [tool.bandit]
├── Dockerfile             # Container image definition
├── .gitignore
├── DOCUMENTATION.md       # This file
├── README.md              # Challenge brief & learning goals
├── .github/
│   └── workflows/
│       └── pipeline.yml   # GitHub Actions workflow
└── scripts/
    ├── health_check.sh    # Post-deploy HTTP health probe (EC2)
    ├── rollback.sh        # Restore previous_stable image
    └── tag_stable.sh      # Manual tagging helper (stretch / local)
```

---

## Application

**File:** `app.py`

| Route | Method | Response |
|-------|--------|----------|
| `/` | GET | Plain text: hello message + “TechFlow CI/CD Pipeline is live” (HTTP 200) |
| `/health` | GET | JSON: `{"status": "ok"}` (HTTP 200) |

The app listens on `0.0.0.0:5000` when run with `python app.py`. In Docker and on EC2, traffic reaches the app on port **5000** inside the container; EC2 maps **host port 80** to **5000**.

---

## Local development

### Prerequisites

- Python 3.11+ recommended  
- `pip`

### Install and run

```bash
pip install -r requirements.txt
python app.py
```

- App: `http://localhost:5000`  
- Health: `http://localhost:5000/health`

### Run tests

```bash
pip install pytest
pytest test_app.py -v
```

---

## Docker

### Build

```bash
docker build -t techflow-app:local .
```

### Run locally

```bash
docker run --rm -p 5000:5000 techflow-app:local
```

Visit `http://localhost:5000` and `http://localhost:5000/health`.

### Image highlights (`Dockerfile`)

- Base: `python:3.11.11-slim-bookworm` (pinned patch version).
- OS packages upgraded for security patches.
- `pip`, `setuptools`, and `wheel` upgraded before installing app deps.
- Application runs as non-root user `appuser` (UID 10001).
- Port **5000** exposed; default command runs `python app.py`.

---

## CI/CD pipeline

**File:** `.github/workflows/pipeline.yml`

### Triggers

| Event | Branches | Typical behavior |
|-------|----------|------------------|
| `push` | `main` | Full pipeline: test → build → deploy |
| `pull_request` | `main` | Runs jobs that satisfy dependencies; **test** always runs; **build/deploy** also run unless you add `if:` conditions |

> **Note:** To run **only tests** on PRs and **full deploy** on push to `main`, add `if:` conditions to `build` and `deploy` jobs (e.g. `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`).

### Jobs

1. **`test`**  
   - Checkout, setup Python 3.11, install deps, run `pytest test_app.py -v`.

2. **`build`** (needs `test`)  
   - Login to Docker Hub.  
   - `docker build` and tag as `<DOCKERHUB_USERNAME>/<IMAGE_NAME>:<sha>` and `:latest`.  
   - Push both tags.  
   - Image name comes from repo variable `IMAGE_NAME` (see below).

3. **`deploy`** (needs `build`)  
   - Checkout (for `scripts/` upload).  
   - **SSH** to EC2: ensure Docker is installed, optionally commit current container as `previous_stable`, pull `latest`, stop/remove old container, run new container named after `IMAGE_NAME`, port `80:5000`.  
   - **SCP** `scripts/*` → `/home/ubuntu/scripts`.  
   - **SSH** again: `chmod +x` scripts, run `health_check.sh`.  
   - On **failure**, SSH runs `rollback.sh`.  
   - Email notifications on success/failure (Gmail SMTP).

### Workflow environment

- `IMAGE_NAME`: from **GitHub Actions variable** `vars.IMAGE_NAME` (repository **Settings → Secrets and variables → Actions → Variables**).
- `AUTHOR`: display string in emails.

---

## Configuration (secrets & variables)

Configure in **GitHub → Repository → Settings → Secrets and variables → Actions**.

### Secrets (examples — names must match your workflow)

| Name | Usage |
|------|--------|
| `DOCKERHUB_USERNAME` | Docker Hub login & image namespace |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `EC2_HOST` | EC2 public IP or DNS |
| `EC2_USERNAME` | SSH user (e.g. `ubuntu`) |
| `EC2_SSH_KEY` | Private key contents (PEM) |
| `EMAIL_USERNAME` | SMTP username (e.g. Gmail) |
| `EMAIL_APP_PASSWORD` | App password / SMTP password |
| `NOTIFY_EMAIL` | Primary notification address |
| `CC_NOTIFY_EMAIL` | CC on deployment emails (if used in workflow) |

### Variables

| Name | Usage |
|------|--------|
| `IMAGE_NAME` | Docker image/repo name segment (e.g. `techflow-app`); container name on EC2 matches this in the pipeline |

Never commit real credentials; always use secrets/variables.

---

## EC2 deployment

### What the pipeline expects

- SSH access for `EC2_USERNAME` with `EC2_SSH_KEY`.
- Security group allows **22** (SSH) and **80** (HTTP) from where you browse / health checks run.
- Docker: the workflow can install Docker CE if missing; `sudo` is used for Docker commands.
- After deploy, scripts live under `/home/ubuntu/scripts/` and health checks hit `http://localhost/health` (port 80 on the host).

### Container naming

The deploy script uses `${{ env.IMAGE_NAME }}` for the container name—keep it aligned with any manual scripts (e.g. `rollback.sh` uses a fixed name `techflow-app` unless you update those scripts to use the same name or env).

---

## Operational scripts

All under `scripts/`. Paths on EC2: `/home/ubuntu/scripts/`.

### `health_check.sh`

- GET `http://localhost/health` up to **5** times, **5** seconds apart.
- Exits **0** if HTTP **200**, else **1**.

### `rollback.sh`

- Stops/removes container `techflow-app`.
- Pulls image `nokafor2/techflow-app:previous_stable` (hardcoded—align with your Docker Hub user and `previous_stable` tagging).
- Runs container on port **80:5000**.
- Verifies `http://localhost/health` returns **200**.

### `tag_stable.sh`

- Inspects container `techflow-app`, tags current image as `nokafor2/techflow-app:previous_stable`, pushes to Docker Hub.  
- Hardcoded registry path—adjust to match your `DOCKERHUB_USERNAME` and image name.

> **Consistency:** Prefer one source of truth for image name and container name (env vars or a small config) across `pipeline.yml`, `rollback.sh`, and `tag_stable.sh`.

---

## Testing

- **Framework:** pytest + Flask test client (`test_app.py`).
- **Coverage:** `/` returns 200 and contains expected substrings; `/health` returns JSON with `status: ok`.

---

## Security (Bandit)

[Bandit](https://bandit.readthedocs.io/) scans Python for common security issues. This repo configures it in **`pyproject.toml`** (`[tool.bandit]`) and runs it in the **GitHub Actions `test` job** before pytest.

**Run locally** (use a venv if you prefer):

```bash
pip install -r requirements-dev.txt
python -m bandit -c pyproject.toml -r . -ll -f screen
```

- **`requirements-dev.txt`** — app deps + Bandit (not used by the production Docker image).
- **CI command:** `bandit -c pyproject.toml -r . -ll -f screen` (fails the job on medium+ severity findings; `B101` assert in tests is skipped; **`scripts/` is excluded** so dev helpers don’t block deploy).
- If the job fails with **exit code 1** after Bandit, open the **Run Bandit** log: Bandit reports findings and exits 1 when **medium+** issues exist (not a crash—fix or skip with care in `pyproject.toml`).

---

## Troubleshooting

| Symptom | Things to check |
|--------|------------------|
| `docker: command not found` on EC2 | Pipeline installs Docker; ensure SSH user can run `sudo docker` and no conflicting old `docker.io`-only setup breaks the script. |
| Deploy can’t pull image | Docker Hub login on runner is for push; EC2 pull of **public** images needs no login; **private** images need `docker login` on EC2 or a pull secret. |
| Health check fails | App not listening on 5000 inside container; port mapping `80:5000`; firewall/security group; `/health` route. |
| Rollback wrong image | `previous_stable` tag and hardcoded names in `rollback.sh` / `tag_stable.sh` vs actual `IMAGE_NAME` and Docker Hub user. |
| PR runs build/deploy | Add `if:` on `build`/`deploy` so only `test` runs on `pull_request`. |

---

## Related reading

- Challenge brief and learning objectives: [`README.md`](README.md)  
- GitHub Actions workflow: [`.github/workflows/pipeline.yml`](.github/workflows/pipeline.yml)

---

*Last updated to match the repository layout and pipeline behavior at documentation time.*
