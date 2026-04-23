# ============================================================
# Dockerfile  —  OPTIMISED (v3 multi-stage)
#
# Students: complete the TODOs based on Practice 6 notes.
# ============================================================

# ---- builder stage ----
FROM python:3.12-slim AS builder

WORKDIR /app

COPY app/requirements.txt .

# TODO (Part 2): replace the plain pip install below with a
# --mount=type=secret variant that reads /run/secrets/app_secret.
# For now, install normally; buildx --secret support is wired in
# by the build command in check.sh.
RUN --mount=type=secret,id=app_secret,target=/run/secrets/app_secret \
    pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- runtime stage ----
FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /install /usr/local

COPY app/ .

EXPOSE 5000

CMD ["python", "app.py"]
