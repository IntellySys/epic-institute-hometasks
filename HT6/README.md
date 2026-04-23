# HT6 — Dockerfile Optimization & Docker Compose

> **Prerequisites:** EC2 instance with Docker + Docker Compose installed (from HT5 / Practice 5 & 6).

## Goal

Build and run a Flask + Nginx stack on EC2 that demonstrates:

- Layer caching and multi-stage Dockerfile optimization
- Buildx secret mounts (secrets that never land in the image)
- Docker Compose with healthchecks and automatic container restart

---

## Automated Verification

Your instructor will run the check script against your EC2's public IP:

```bash
./check.sh <YOUR_EC2_PUBLIC_IP>
```

Make sure **port 80** is open in your EC2 security group.

For the optional Swarm bonus (Part 4), keep the service running and pass `--swarm`:

```bash
./check.sh <YOUR_EC2_PUBLIC_IP> --swarm
```

---

## Checklist

### Provided to students

| File | Purpose |
|---|---|
| `Dockerfile` | Optimized multi-stage build template (already complete — study and use it) |
| `Dockerfile.v1` | Naive build — intentionally unoptimized, build this first |
| `app/app.py` | Flask app with `/`, `/health`, and `/secret-check` endpoints |
| `app/requirements.txt` | Python dependencies |
| `docker-compose.yml` | Two-service stack: Flask app + Nginx with healthcheck configured |
| `nginx/nginx.conf` | Nginx reverse proxy config |
| `.env.example` | Environment variable template |
| `check.sh` | Automated verification script run by the instructor |

### What students must do

| Task | How it is verified |
|---|---|
| Build `flask-app:v1` from `Dockerfile.v1` and note its size | Screenshot (cannot check remotely) |
| Demonstrate that changing `app.py` triggers a full `pip install` on v1 | Screenshot |
| Build `flask-app:v3` from the optimized `Dockerfile` | Screenshot showing size vs v1 |
| Rebuild `flask-app:v3` after a code change — `pip install` must be `CACHED` | Screenshot |
| Create `.dockerignore` | Implicit — affects build context size |
| Build `flask-app:secure` using `docker buildx build --secret` | Auto-checked via `/secret-check` endpoint |
| Copy `.env.example` to `.env` and run `docker compose up --build -d` | Auto-checked via port 80 |
| Confirm app container reaches `healthy` state (`docker compose ps`) | Screenshot + auto-checked via `/health` |
| Kill app container and confirm automatic restart | Screenshot |
| Submit EC2 public IP | Auto-checked by instructor |

### Bonus (Part 4)

| Task | How it is verified |
|---|---|
| Initialize Swarm and deploy `flask-app:v1` as a 3-replica service on port 5000 | Auto-checked with `--swarm` flag |
| Perform rolling update to `flask-app:v2` | Screenshot |
| Roll back to `flask-app:v1` | Screenshot |

---

## Part 1 — Dockerfile Optimization

### 1.1 Naive build

Build the naive Dockerfile and record the image size:

```bash
docker build -f Dockerfile.v1 -t flask-app:v1 .
docker images flask-app:v1
```

Now change any line in `app/app.py` and rebuild. You will see `pip install` runs again even though `requirements.txt` did not change. This is the layer ordering problem.

**Checkpoint 1a.** Screenshot of `docker images flask-app:v1` showing the image size (~1 GB).

### 1.2 Optimized multi-stage build

The provided `Dockerfile` uses `python:3.12-slim` and a two-stage build. Build it:

```bash
docker build -t flask-app:v3 .
```

Change a line in `app/app.py` and rebuild — `pip install` must show `CACHED`:

```bash
# edit app/app.py, then:
docker build -t flask-app:v3 .
```

Create `.dockerignore` to keep build context clean:

```
__pycache__
*.pyc
*.pyo
.git
.env
.venv
```

**Checkpoint 1b.** Screenshot of `docker images | grep flask-app` showing v1 vs v3 size difference. Screenshot of the second v3 build with `CACHED` next to the install step.

---

## Part 2 — Buildx Secret Mount

### 2.1 Create a dummy secret

```bash
echo "super-secret-build-token" > /tmp/build_secret.txt
```

### 2.2 Build with buildx

```bash
docker buildx build \
  --secret id=app_secret,src=/tmp/build_secret.txt \
  -t flask-app:secure \
  --load .
```

### 2.3 Verify the secret is not in the final image

```bash
# Must print: cat: /run/secrets/app_secret: No such file or directory
docker run --rm flask-app:secure cat /run/secrets/app_secret
```

The `/secret-check` HTTP endpoint verifies this automatically once the Compose stack is running.

**Checkpoint 2.** Screenshot of the successful `buildx build` and the `docker run` output showing the secret is absent.

---

## Part 3 — Docker Compose with Healthchecks

### 3.1 Start the stack

```bash
cp .env.example .env
docker compose up --build -d
```

### 3.2 Verify healthy status

```bash
docker compose ps
# app service must show (healthy), not just running
```

Open `http://<YOUR_EC2_IP>/` in a browser — you should see the Flask response through Nginx.

### 3.3 Verify self-healing

Kill the app container and confirm it restarts automatically:

```bash
docker kill $(docker compose ps -q app)
sleep 10
docker compose ps   # app must be back in running/healthy state
```

**Checkpoint 3.** Screenshot of `docker compose ps` with app in `healthy` state.

---

## Part 4 — Docker Swarm Rolling Update (Bonus)

### 4.1 Build two image versions

```bash
docker build -t flask-app:v1 .

# Edit APP_VERSION in .env to 2.0, then rebuild:
docker build -t flask-app:v2 .
```

### 4.2 Deploy as a Swarm service

```bash
docker swarm init

docker service create \
  --name my-app-svc \
  --replicas 3 \
  --publish published=5000,target=5000 \
  --update-parallelism 1 \
  --update-delay 5s \
  flask-app:v1

docker service ps my-app-svc
```

### 4.3 Rolling update

```bash
docker service update \
  --image flask-app:v2 \
  --update-parallelism 1 \
  --update-delay 5s \
  my-app-svc

docker service ps my-app-svc
```

### 4.4 Rollback

```bash
docker service rollback my-app-svc
docker service ps my-app-svc   # image tag must revert to flask-app:v1
```

### 4.5 Clean up

```bash
docker service rm my-app-svc
docker swarm leave --force
```

**Checkpoint 4.** Screenshot of `docker service ps` during the rolling update. Screenshot after rollback showing the previous image tag restored.

---

## Submission

Submit only your EC2 public IP. The check script verifies:

- `GET /` on port 80 returns a Flask response through Nginx
- `GET /health` returns `{"status": "ok"}`
- `GET /secret-check` returns `{"leaked": false}` — confirms the build secret was not baked into the image
- Nginx is confirmed as the reverse proxy
