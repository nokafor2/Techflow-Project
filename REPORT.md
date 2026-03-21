# Techflow Project — Integration & Execution Report

**Subject:** Summary of how the CI/CD workflow, container image, application code, tests, dependencies, and shell scripts work together.

---

## 1. Executive summary

This project delivers a **small Flask web application** deployed as a **Docker image** to **Docker Hub**, then **run on AWS EC2** via **GitHub Actions**. Automated **pytest** checks validate the app before any image is built or deployed. **Bash scripts** on the server perform **health checks** and **rollback** after deployment. The glue between pieces is: **`requirements.txt`** → runtime and test deps; **`Dockerfile`** → same deps inside an image; **`pipeline.yml`** → orchestrates test, build, push, deploy, script upload, health check, rollback, and email.

---

## 2. Component roles

| Component | Role |
|-----------|------|
| **`app.py`** | Defines the Flask app: `/` (hello text) and `/health` (JSON `status: ok`). Listens on `0.0.0.0:5000` when started directly. |
| **`test_app.py`** | Uses pytest + Flask’s test client to assert HTTP 200 and body content for `/`, and JSON for `/health`. Gates quality before build/deploy. |
| **`requirements.txt`** | Pins **Flask**, **pytest**, and **requests** versions used locally and in CI. The Dockerfile installs these inside the image (pytest is not required at runtime in production but is listed for a single dev/CI file). |
| **`Dockerfile`** | Builds a reproducible image: Python 3.11 slim Bookworm, OS security updates, upgrades pip tooling, `pip install -r requirements.txt`, copies app, runs as non-root user, **exposes 5000**, **CMD `python app.py`**. |
| **`.github/workflows/pipeline.yml`** | GitHub Actions: **test** → **build/push** → **deploy**; SSH to EC2 for Docker pull/run; SCP of `scripts/`; remote health check; rollback on failure; optional email notifications. |
| **`scripts/`** | `health_check.sh` — retries `GET /health` on localhost; `rollback.sh` — restores `previous_stable` image; `tag_stable.sh` — optional manual tagging helper. |

---

## 3. Integration flow (end-to-end)

1. **Trigger:** Push or pull request targeting **`main`** starts the workflow.
2. **Test job:** Checkout → install from **`requirements.txt`** → **`pytest test_app.py -v`**. This validates **`app.py`** behavior against **`test_app.py`** without starting a real server.
3. **Build job** (after tests pass): Checkout → Docker Hub login → **`docker build`** using the **`Dockerfile`** → tag image as **`<user>/<IMAGE_NAME>:<commit-sha>`** and **`:latest`** → **`docker push`** both tags. `IMAGE_NAME` comes from GitHub **Actions variables** (`vars.IMAGE_NAME`).
4. **Deploy job** (after build): Checkout (for `scripts/`) → **SSH** to EC2 → ensure Docker is installed → optionally commit running container as **`previous_stable`** and push → **`docker pull`** `:latest` → stop/remove old container → **`docker run`** new container (**port 80 → 5000**) → **SCP** `scripts/*` to `/home/ubuntu/scripts` → SSH chmod and run **`health_check.sh`** → on failure, run **`rollback.sh`** → email success/failure.

**Conceptual chain:**  
`requirements.txt` + `app.py` → tested by `test_app.py` → packaged by `Dockerfile` → published by `pipeline.yml` → executed on EC2 as a container → verified by `health_check.sh`.

---

## 4. How each file connects

- **`requirements.txt` ↔ `app.py`:** Flask is the web framework; tests use pytest and the Flask client.
- **`requirements.txt` ↔ `Dockerfile`:** `RUN pip install -r requirements.txt` installs the same dependencies inside the image so the container runs the same stack as CI (minus OS-only steps).
- **`pytest` ↔ `test_app.py`:** The pipeline runs `pytest test_app.py`; failures block `build` and `deploy` because `build` has `needs: test`.
- **`Dockerfile` ↔ `pipeline.yml`:** `docker build ... .` uses the Dockerfile in the repo root; the pushed image is what EC2 pulls and runs.
- **`app.py` ↔ EC2:** Container maps host **80** to container **5000**, matching Flask’s port and the health URL (`http://localhost/health` from the host).
- **`scripts/` ↔ `pipeline.yml`:** Scripts are copied after deploy; **`health_check.sh`** aligns with **`/health`** in **`app.py`**. **`rollback.sh`** assumes a previous image tag and container name consistent with your Docker Hub user and naming (see script contents).

---

## 5. Main commands and where they run

### Local / developer machine

| Command | Purpose |
|---------|---------|
| `pip install -r requirements.txt` | Install Python deps for local dev and testing. |
| `python app.py` | Start Flask on `http://localhost:5000`. |
| `pytest test_app.py -v` | Run the same checks the CI **test** job runs. |

### Docker (local)

| Command | Purpose |
|---------|---------|
| `docker build -t <name> .` | Build image from **Dockerfile** (same as CI). |
| `docker run -p 5000:5000 <name>` | Run container; app available on port 5000. |

### GitHub Actions (runner — `ubuntu-latest`)

| Command / action | Purpose |
|------------------|---------|
| `pip install -r requirements.txt` + `pip install pytest` | Prepare **test** job. |
| `pytest test_app.py -v` | Automated tests. |
| `docker build -t <user>/<IMAGE>:<sha> .` | Build release image. |
| `docker tag` / `docker push` | Publish **sha** and **latest** to Docker Hub. |

### EC2 (via SSH in deploy)

| Command | Purpose |
|---------|---------|
| `sudo docker pull <image>:latest` | Get newly built image. |
| `sudo docker stop` / `rm` | Replace old container. |
| `sudo docker run -d --name <IMAGE_NAME> -p 80:5000 ...` | Start app; **80** is public HTTP, **5000** is Flask inside the container. |
| `bash /home/ubuntu/scripts/health_check.sh` | Post-deploy verification. |
| `bash /home/ubuntu/scripts/rollback.sh` | On pipeline failure, attempt restore. |

### Inside the container (default process)

| Command | Purpose |
|---------|---------|
| `python app.py` | **Dockerfile CMD** — starts Flask binding to **0.0.0.0:5000** (see `app.py` `if __name__ == "__main__"` block). |

---

## 6. Conclusion

The project integrates **static dependencies** (`requirements.txt`), **application logic** (`app.py`), **automated verification** (`test_app.py`), **immutable delivery** (`Dockerfile` + Docker Hub), and **operations** (`scripts/` + EC2) under a single **GitHub Actions** workflow. The **main execution path** for production is: **GitHub Actions builds and pushes the image → EC2 pulls and runs the container with `python app.py` → scripts confirm and optionally roll back health.**

---

*This report reflects the repository layout and workflow at the time of writing.*
