# HT8 — S3 Static Website + CloudFront

> **Prerequisites:** AWS account with S3 access. No EC2 instance required for this task.

## Goal

Host a static website on S3 and serve it over HTTPS via CloudFront:

- S3 bucket with versioning and a public bucket policy
- Static website hosting enabled on the bucket
- CloudFront distribution in front of S3 for HTTPS and CDN

> **Plus task:** If you want to complete the custom domain task but don't have a domain, contact the trainer on Discord to get one.

---

## Checklist

### What students must do

| Task | Verified by |
|---|---|
| Create S3 bucket and enable versioning | Screenshot |
| Enable static website hosting and upload HTML template | Screenshot of live HTTP URL |
| Add bucket policy for public read access | Screenshot |
| Create CloudFront distribution pointing to the S3 website endpoint | Screenshot of working CloudFront URL (HTTPS) |

### Plus task

| Task | Verified by |
|---|---|
| Add custom domain + SSL certificate via ACM | Screenshot of working custom domain over HTTPS |

---

## Part 1 — Create S3 Bucket and Enable Versioning

### 1.1 Create a bucket

Go to **S3 → Create bucket**:
- **Bucket name:** must be globally unique (e.g., `yourname-ht8-website`)
- **Region:** choose any (e.g., `eu-central-1`)
- Leave **Block all public access** enabled for now — you will change it in Part 3

### 1.2 Enable versioning

Go to your bucket → **Properties → Versioning → Edit → Enable → Save**.

> **Note:** Once versioning is enabled it cannot be fully disabled — only suspended. It also increases storage costs because every version of every object is kept. For a small static site the cost is negligible, but keep this in mind for large buckets.

**Checkpoint 1.** Screenshot of the bucket properties page showing versioning as **Enabled**.

---

## Part 2 — Upload a Static Website

### 2.1 Get a free HTML template

Go to [https://html5up.net](https://html5up.net) and download any free template. Unzip it locally.

### 2.2 Enable static website hosting

Go to your bucket → **Properties → Static website hosting → Edit**:
- Select **Enable**
- **Index document:** `index.html`
- **Error document:** `404.html` (or `index.html` if the template does not have a 404 page)
- Click **Save**

Note the **Bucket website endpoint** URL shown after saving — you will need it in Part 4.

### 2.3 Upload the template

Go to your bucket → **Objects → Upload**. Upload all files from the unzipped template folder.

> **Important:** `index.html` must be at the root of the bucket, not inside a subfolder. Upload all files and folders from the template root directly.

**Checkpoint 2.** Screenshot of the bucket objects list showing `index.html` at the root.

---

## Part 3 — Bucket Policy for Public Read

### 3.1 Unblock public access

Go to your bucket → **Permissions → Block public access → Edit**. Uncheck **Block all public access** and save.

### 3.2 Add a bucket policy

Go to your bucket → **Permissions → Bucket policy → Edit**. Paste the following, replacing `your-bucket-name` with your actual bucket name:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::your-bucket-name/*"
    }
  ]
}
```

Click **Save**.

Now open the **Bucket website endpoint** URL from Part 2 in a browser — your site should load over plain HTTP.

**Checkpoint 3.** Screenshot of the website loading via the S3 HTTP endpoint.

---

## Part 4 — CloudFront Distribution (HTTPS)

S3 static website hosting only supports HTTP. CloudFront adds HTTPS and CDN caching in front of it.

### 4.1 Create a distribution

Go to **CloudFront → Create distribution**:

- **Origin domain:** paste the **S3 website endpoint** from Part 2 (the `http://...s3-website-...amazonaws.com` URL). Do **not** select the bucket from the dropdown — type or paste the website endpoint manually.
- **Protocol:** HTTP only (S3 website endpoint does not support HTTPS)
- Leave all other settings as defaults
- Click **Create distribution**

Wait until **Last modified** changes from *Deploying* to today's date (takes a few minutes).

### 4.2 Test the CloudFront URL

Copy the **Distribution domain name** (ends with `.cloudfront.net`) from the distribution details and open it in a browser. Your site should load over HTTPS.

**Checkpoint 4.** Screenshot of the site loading over HTTPS via the CloudFront URL.

---

## Plus Task — Custom Domain + SSL Certificate

> Skip this section if you do not have a domain. The CloudFront URL from Part 4 is sufficient for submission.

You will need a domain name. You can buy a cheap one (~$1/year) from Namecheap or Hostinger. If you don't have one, contact the trainer on Discord to get a subdomain assigned to you.

### 5.1 Set up DNS

**Option A — Route53 (Epic institute accounts or if you want to pay ~$0.50/month):**
1. Go to **Route53 → Hosted zones → Create hosted zone**
2. Enter your root domain (e.g., `example.com`)
3. Copy the four NS records from the hosted zone
4. Go to your domain registrar (Namecheap, Hostinger, etc.) and replace the default nameservers with the Route53 ones

**Option B — Your domain provider's DNS (private accounts, no extra cost):**
Keep DNS at your registrar. You will add a CNAME record manually in step 5.4.

### 5.2 Request an SSL certificate in ACM

> **Critical:** ACM certificates for CloudFront must be requested in **us-east-1 (N. Virginia)**. If you request it in any other region, CloudFront will not see it.

Switch your AWS console region to **us-east-1**, then go to **Certificate Manager → Request certificate**:
- Select **Request a public certificate**
- Enter your subdomain (e.g., `www.example.com` or `site.example.com`)
- Validation method: **DNS validation** (recommended)
- Click **Request**

### 5.3 Validate the certificate

After requesting, ACM generates a CNAME record for DNS validation. On the certificate detail page:
- **Route53 users:** click **Create records in Route53** — ACM adds the CNAME automatically
- **Other DNS providers:** copy the CNAME name and value and add it manually in your domain provider's DNS settings

Wait until the certificate status changes to **Issued** (a few minutes after DNS propagates).

### 5.4 Add the custom domain to CloudFront

Go back to your CloudFront distribution → **General → Edit**:
- **Alternate domain names (CNAMEs):** add your subdomain (e.g., `www.example.com`)
- **Custom SSL certificate:** select the certificate you just issued
- Click **Save**

Now add a CNAME record in your DNS pointing your subdomain to the CloudFront domain name:

| Type | Name | Value |
|---|---|---|
| CNAME | `www` | `xxxxxxxxxx.cloudfront.net` |

Wait for CloudFront to redeploy (status changes from *Deploying* to a date). Then open your custom domain in a browser.

**Plus Checkpoint.** Screenshot of your website loading over HTTPS at your custom domain.

---

## Submission

Submit either:
- The **CloudFront URL** (ends with `.cloudfront.net`) — required for everyone
- Your **custom domain URL** — if you completed the bonus part

---

## Key Concepts

### Why not serve HTTPS directly from S3?

S3 static website hosting only supports HTTP. HTTPS requires CloudFront (or another CDN) in front of it. In production, always use CloudFront with **Origin Access Control (OAC)** and keep the bucket private — the approach in this task (public bucket + website endpoint) is simpler for learning but less secure.

### Versioning + Lifecycle

Enable both together to avoid runaway storage costs: versioning keeps every version forever, lifecycle rules let you automatically delete old versions after N days.

### CloudFront caching

CloudFront caches your files at edge locations worldwide. After you update files in S3, you may need to **invalidate the cache** in CloudFront (`/*`) for users to see the new version immediately.

### Presigned URLs

If you ever need to share a private S3 object temporarily, use presigned URLs instead of making the bucket public. They expire automatically and require no bucket policy changes.
