# Redress Item Photos API - Cloudflare Worker

Cloudflare Worker for handling photo storage and retrieval for the Redress Closet app using Cloudflare R2.

## Setup

### 1. Install Wrangler CLI

```bash
npm install -g wrangler
```

### 2. Login to Cloudflare

```bash
wrangler login
```

### 3. Configure Environment Variables

Set secrets in Cloudflare Dashboard or via CLI:

```bash
# Set Supabase project ID
wrangler secret put SUPABASE_PROJECT_ID

# Set Supabase anon key
wrangler secret put SUPABASE_ANON_KEY

# Set worker URL (optional)
wrangler secret put WORKER_URL
```

Or set them in Cloudflare Dashboard:
1. Go to Workers & Pages → `redress-item-photos-api`
2. Settings → Variables
3. Add environment variables

### 4. Bind R2 Bucket

In Cloudflare Dashboard:
1. Go to Workers & Pages → `redress-item-photos-api`
2. Settings → Variables
3. Add R2 bucket binding:
   - Variable name: `R2_BUCKET`
   - Bucket: `redress-item-photos`

### 5. Deploy

```bash
wrangler deploy
```

## API Endpoints

### Upload Photo (PUT)
```
PUT /{userId}/{itemId}/{photoId}.jpg
Authorization: Bearer {supabase_jwt_token}
Content-Type: image/jpeg
```

### Get Photo (GET)
```
GET /{userId}/{itemId}/{photoId}.jpg
```

### Delete Photo (DELETE)
```
DELETE /{userId}/{itemId}/{photoId}.jpg
Authorization: Bearer {supabase_jwt_token}
```

## Security

- JWT validation via Supabase API
- Path ownership verification (users can only access their own files)
- File size limit: 5MB
- Content type validation
- CORS enabled

## Testing

```bash
# Upload
curl -X PUT https://redress-item-photos-api.your-subdomain.workers.dev/user-id/item-id/photo-id.jpg \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: image/jpeg" \
  --data-binary @photo.jpg

# Get
curl https://redress-item-photos-api.your-subdomain.workers.dev/user-id/item-id/photo-id.jpg

# Delete
curl -X DELETE https://redress-item-photos-api.your-subdomain.workers.dev/user-id/item-id/photo-id.jpg \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

