# Hometask 3

## Goal

Launch an EC2 instance and configure it only through **User data**.

This task is checked remotely, so screenshots are not required.

## Requirements

1. Create an EC2 instance using the practice session materials.
2. All server configuration must be done through **User data** in the EC2 launch form.
3. Your User data script must:
   - install `nginx`
   - create a user named `devops`
   - enable and start `nginx`
   - create `/usr/local/bin/ht3-check.sh`
   - create `/var/www/html/index.html`
   - create `/var/www/html/check.json`
4. Your User data must run `/usr/local/bin/ht3-check.sh` at least once during provisioning.
5. Your User data must configure a cron job that refreshes `/var/www/html/check.json` every minute.

## What must be visible remotely

When I open `http://<public-ip>/`, I must see a custom page.

The page must contain:
- your name or email
- the marker string `EC2-HT3-OK`
- the instance hostname
- the path `/check.json`

When I open `http://<public-ip>/check.json`, I must receive valid JSON with the following structure:

```json
{
  "task": "HT3",
  "marker": "EC2-HT3-OK",
  "student": "student@example.com",
  "hostname": "ip-172-31-0-10",
  "updated_at_utc": "2026-03-23T18:10:00Z",
  "checks": {
    "nginx_active": true,
    "nginx_enabled": true,
    "devops_user_exists": true,
    "index_html_exists": true
  }
}
```

## Submission

Submit only:
- the public IP of your EC2 instance

## How it will be checked

The submission will be checked automatically.

The checker will verify:
- `http://<public-ip>/` returns HTTP 200
- the main page contains `EC2-HT3-OK`
- the main page contains your student identifier
- `http://<public-ip>/check.json` returns valid JSON
- JSON contains the required fields
- all required checks in JSON are `true`

## Notes

- Do not configure the server manually after launch.
- If the instance is restarted, your current public IP may change.
- If `nginx` is not running, the remote check will fail.
- A sample reference implementation is provided in `sample_user_data.sh`.
