# Hometask 5

## Goal

Run a custom HTTPS-enabled `nginx` web server inside a Docker container on EC2 and prove the result through automatic checks instead of screenshots.

This task extends Hometask 4. You will use a basic Ubuntu EC2 image, install everything yourself, configure HTTPS and HTTP-to-HTTPS redirect, and run `nginx` in a container built from a basic Ubuntu image.

## Requirements

1. Use a basic Ubuntu EC2 image.
2. Do not use a preconfigured `nginx` AMI.
3. Do not use a ready-made `nginx` container image as the final solution.
4. Install Docker and all required packages yourself.
5. Build your container from a basic Ubuntu image.
6. Inside the container, install and configure `nginx` yourself.
7. Configure `nginx` to:
   - serve your custom page over HTTPS
   - redirect HTTP requests to HTTPS
8. Generate and use a TLS certificate.
   - A self-signed certificate is acceptable for this homework.
9. Publish:
   - `/` over HTTP with redirect to HTTPS
   - `/` over HTTPS with your custom page
   - `/check.json` over HTTPS
10. Your EC2 User data must:
   - install Docker
   - prepare all required files
   - build the container image
   - start the container automatically
   - create `/usr/local/bin/ht5-check.sh`
   - run the checker script at least once during provisioning
   - refresh the checker output every minute

## Important Container Note

In a container, the main process must stay in the foreground. If the main process exits, the container stops.

For `nginx`, this means you should run it with:

```bash
nginx -g 'daemon off;'
```

Do not rely on the default background daemon mode inside the container.

## How the Checks Are Split

The checker script runs on the **EC2 host**, not inside the container.

Because of that, the checks are divided into two groups:

### Host-level checks

These checks verify what is configured on the EC2 machine itself:
- Docker is installed
- the container is running
- HTTP responds with redirect to HTTPS
- HTTPS responds successfully
- the image was built and can be inspected through Docker

Typical commands for host-level checks include:
- `command -v docker`
- `docker ps`
- `docker image inspect`
- `curl http://127.0.0.1/`
- `curl -k https://127.0.0.1/`

### Container-level checks

These checks verify what is happening inside the running container:
- `nginx` is running inside the container
- the container serves the expected content

Typical commands for container-level checks include:
- `docker exec <container-name> pgrep nginx`

This is **not** Docker-in-Docker. The checker uses Docker commands on the EC2 host to inspect the running container.

## What must be visible remotely

When I open `http://<public-ip>/`, I must receive a redirect to HTTPS.

When I open `https://<public-ip>/`, I must see a custom page.

The HTTPS page must contain:
- your name or email
- the marker string `EC2-HT5-OK`
- a note that HTTPS is enabled
- the path `/check.json`

When I open `https://<public-ip>/check.json`, I must receive valid JSON with the following structure:

```json
{
  "task": "HT5",
  "marker": "EC2-HT5-OK",
  "student": "student@example.com",
  "updated_at_utc": "2026-03-23T18:10:00Z",
  "docker": {
    "installed": true,
    "container_running": true,
    "image_built_from_ubuntu": true
  },
  "web": {
    "https_enabled": true,
    "http_redirect_to_https": true
  },
  "checks": {
    "nginx_running_in_container": true,
    "custom_index_present": true,
    "check_json_present": true
  }
}
```

## Submission

Submit only:
- the public IP of your EC2 instance

## How it will be checked

The submission will be checked automatically.

The checker will verify:
- `http://<public-ip>/` responds with a redirect to HTTPS
- `https://<public-ip>/` returns HTTP 200
- the HTTPS page contains `EC2-HT5-OK`
- the HTTPS page contains your student identifier
- `https://<public-ip>/check.json` returns valid JSON
- JSON contains the required fields
- Docker is installed
- the container is running
- the image was built from Ubuntu
- HTTPS is enabled
- HTTP redirect to HTTPS is enabled
- all required checks in JSON are `true`

## Notes

- Do not submit screenshots.
- Do not use the `nginx:latest` image as your final solution.
- Use a basic Ubuntu base image and make the required changes yourself.
- A self-signed certificate is acceptable. Because of that, browser warnings are expected and automated checks can use insecure HTTPS mode.
- The sample User data script is a reference implementation.
