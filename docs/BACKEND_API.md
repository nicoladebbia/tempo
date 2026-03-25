# Tempo Backend API Specification

> **Version:** 2.1.0
> **Last updated:** 2026-03-24
> **Stack:** Vapor 4 (Swift) + PostgreSQL 16 + Redis 7
> **Authors:** Nicola Debbia
> **Status:** Production-ready specification

---

## Table of Contents

1. [API Overview](#1-api-overview)
2. [Authentication](#2-authentication)
3. [User Management](#3-user-management)
4. [User Preferences & Settings](#4-user-preferences--settings)
5. [Whoop Integration](#5-whoop-integration)
6. [NutriTrack Proxy](#6-nutritrack-proxy)
7. [Training & Workouts](#7-training--workouts)
8. [Study Sessions](#8-study-sessions)
9. [Daily Snapshots & History](#9-daily-snapshots--history)
10. [Arena / Social Endpoints](#10-arena--social-endpoints)
11. [Non-Negotiables & Accountability](#11-non-negotiables--accountability)
12. [Sync & Batch Operations](#12-sync--batch-operations)
13. [Push Notifications](#13-push-notifications)
14. [Outbound Webhooks](#14-outbound-webhooks)
15. [AI Insights](#15-ai-insights)
16. [Reports & Data Export](#16-reports--data-export)
17. [Search](#17-search)
18. [Admin Endpoints](#18-admin-endpoints)
19. [App Configuration](#19-app-configuration)
20. [Real-Time (WebSocket)](#20-real-time-websocket)
21. [Database Schema](#21-database-schema)
22. [Caching Strategy](#22-caching-strategy)
23. [Error Codes](#23-error-codes)
24. [Security](#24-security)
25. [Rate Limiting](#25-rate-limiting)
26. [Background Jobs](#26-background-jobs)
27. [Observability](#27-observability)
28. [Deployment](#28-deployment)
29. [Migration Strategy](#29-migration-strategy)
30. [API Versioning & Deprecation](#30-api-versioning--deprecation)
31. [Load Testing & Capacity Planning](#31-load-testing--capacity-planning)

---

## 1. API Overview

### 1.1 Base URL

```
Production:  https://api.tempo.app
Staging:     https://api-staging.tempo.app
Development: http://localhost:8080
```

All endpoints are prefixed with a version namespace:

```
https://api.tempo.app/v1/auth/apple
```

### 1.2 Content Type

All requests and responses use JSON:

```
Content-Type: application/json
Accept: application/json
```

File uploads (avatar) use `multipart/form-data` and are the only exception.

**Request size limits:**

| Content-Type | Max Size |
|-------------|----------|
| `application/json` | 1 MB |
| `multipart/form-data` | 5 MB |

Requests exceeding these limits receive `413 Payload Too Large`. The server validates `Content-Type` on every request and rejects mismatches with `415 Unsupported Media Type`.

### 1.3 Standard Response Envelope

Every successful response is wrapped:

```json
{
  "ok": true,
  "data": { ... },
  "meta": {
    "request_id": "req_abc123def456",
    "timestamp": "2026-03-24T10:30:00Z"
  }
}
```

For paginated responses:

```json
{
  "ok": true,
  "data": [ ... ],
  "pagination": {
    "cursor": "eyJpZCI6MTAwfQ==",
    "has_more": true,
    "count": 25
  },
  "meta": {
    "request_id": "req_abc123def456",
    "timestamp": "2026-03-24T10:30:00Z"
  }
}
```

### 1.4 Standard Error Response

```json
{
  "ok": false,
  "error": {
    "code": 1001,
    "message": "Access token has expired.",
    "detail": "The JWT access token provided in the Authorization header is expired. Use POST /v1/auth/refresh to obtain a new one.",
    "field": null
  },
  "meta": {
    "request_id": "req_abc123def456",
    "timestamp": "2026-03-24T10:30:00Z"
  }
}
```

Validation errors include per-field details:

```json
{
  "ok": false,
  "error": {
    "code": 2001,
    "message": "Validation failed.",
    "detail": "One or more fields failed validation.",
    "fields": {
      "username": "Must be 3-30 characters, alphanumeric and underscores only.",
      "display_name": "Must not exceed 50 characters."
    }
  },
  "meta": {
    "request_id": "req_abc123def456",
    "timestamp": "2026-03-24T10:30:00Z"
  }
}
```

Rate limit errors include retry guidance:

```json
{
  "ok": false,
  "error": {
    "code": 5001,
    "message": "Rate limit exceeded.",
    "detail": "You have exceeded the rate limit for this endpoint.",
    "retry_after_seconds": 30
  },
  "meta": {
    "request_id": "req_abc123def456",
    "timestamp": "2026-03-24T10:30:00Z"
  }
}
```

### 1.5 Pagination

All list endpoints use **cursor-based pagination** (not offset-based) to avoid issues with insertions/deletions between pages.

**Query parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `cursor` | string | `null` | Opaque cursor from previous response. Omit for first page. |
| `limit` | integer | `25` | Items per page. Min: 1, Max: 100. |
| `direction` | string | `"desc"` | Sort direction: `"asc"` or `"desc"`. |

The cursor is a base64-encoded JSON object containing the sort key(s). The server decodes it, never the client.

### 1.6 Standard Headers

**Every response includes:**

```
X-Request-Id: req_abc123def456
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 97
X-RateLimit-Reset: 1711276800
Content-Type: application/json; charset=utf-8
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Cache-Control: no-store
```

**Every request should include:**

```
Content-Type: application/json
Accept: application/json
Authorization: Bearer <access_token>       (when authenticated)
X-Client-Version: 1.2.3                    (iOS app build version)
X-Device-Id: 550e8400-e29b-...             (stable device UUID from Keychain)
X-Request-Id: req_client_abc123            (optional, echoed back)
Idempotency-Key: idem_unique-key           (optional, for mutating requests)
```

### 1.7 Idempotency

For POST/PUT/PATCH requests that create or mutate resources, clients may send:

```
Idempotency-Key: idem_unique-client-generated-key
```

The server stores the response for 24 hours keyed by `(user_id, idempotency_key)` in Redis. Duplicate requests within that window return the cached response without re-executing side effects.

### 1.8 Date/Time Format

All timestamps use ISO 8601 in UTC: `2026-03-24T10:30:00Z`. Date-only fields use `YYYY-MM-DD`: `2026-03-24`.

### 1.9 ETag Support

Endpoints returning single resources support conditional requests:

**Response:** `ETag: "a1b2c3d4e5f6"`
**Conditional request:** `If-None-Match: "a1b2c3d4e5f6"` returns `304 Not Modified` if unchanged.

Supported on: `GET /v1/users/me`, `GET /v1/users/:id`, `GET /v1/xp/level`, `GET /v1/achievements/available`, `GET /v1/config`.

---

## 2. Authentication

### 2.1 Sign in with Apple

#### POST /v1/auth/apple

Authenticate via Sign in with Apple. Handles both registration and returning login.

**Authentication:** None | **Rate limit:** 10 req/min per IP | **Cache:** None

**Request headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `Content-Type` | Yes | `application/json` |
| `X-Client-Version` | Yes | iOS app version, e.g. `1.0.0` |
| `X-Device-Id` | Yes | Stable device identifier (UUID stored in Keychain) |

**Request body:**

```json
{
  "identity_token": "eyJraWQiOiI...",
  "authorization_code": "c1234567890abcdef...",
  "first_name": "Nicola",
  "last_name": "Debbia",
  "nonce": "random-nonce-generated-client-side"
}
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `identity_token` | string | Yes | Non-empty, valid JWT | From Apple's `ASAuthorizationAppleIDCredential` |
| `authorization_code` | string | Yes | Non-empty | Single-use authorization code from Apple |
| `first_name` | string | No | Max 50 chars | Only provided on first sign-in |
| `last_name` | string | No | Max 50 chars | Only provided on first sign-in |
| `nonce` | string | Yes | Non-empty | Must match nonce embedded in `identity_token` |

**Server-side flow:**

1. Decode `identity_token` JWT header to extract `kid`.
2. Fetch Apple's public keys from `https://appleid.apple.com/auth/keys` (cached 24h in Redis).
3. Verify JWT signature (RS256).
4. Validate claims: `iss` = `https://appleid.apple.com`, `aud` = bundle ID, `exp` > now, nonce matches.
5. Extract `sub` — the Apple User ID.
6. Lookup by `apple_user_id`: exists = login, new = create user with default username `user_<random8>`.
7. Exchange `authorization_code` with Apple for a refresh token (stored encrypted server-side).
8. Return access + refresh tokens + user profile.

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/auth/apple \
  -H "Content-Type: application/json" \
  -H "X-Client-Version: 1.0.0" \
  -H "X-Device-Id: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{
    "identity_token": "eyJraWQiOiJXNldjT09...",
    "authorization_code": "c18cb0b2c3d4e5f6...",
    "first_name": "Nicola",
    "last_name": "Debbia",
    "nonce": "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  }'
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "access_token": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI2LTAzIn0.eyJzdWIiOiJ1c3JfYWJjMTIzZGVmNDU2IiwiaXNzIjoidGVtcG8tYXBpIiwiYXVkIjoiYXBwLnRlbXBvLmlvcyIsImlhdCI6MTcxMTI3MDIwMCwiZXhwIjoxNzExMjcxMTAwfQ.SIGNATURE",
    "refresh_token": "rt_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4",
    "token_type": "Bearer",
    "expires_in": 900,
    "user": {
      "id": "usr_abc123def456",
      "apple_user_id": "001234.abcdef1234567890",
      "username": "nicola_d",
      "display_name": "Nicola Debbia",
      "avatar_url": null,
      "created_at": "2026-03-24T10:00:00Z",
      "is_new_user": true
    }
  },
  "meta": {
    "request_id": "req_x7k9m2p4q1w3",
    "timestamp": "2026-03-24T10:00:01Z"
  }
}
```

**Error responses:**

| Status | Code | Condition | Example body |
|--------|------|-----------|-------------|
| 400 | 1002 | Invalid identity token | `{"ok":false,"error":{"code":1002,"message":"Invalid identity token","detail":"The identity token is not a valid JWT."}}` |
| 400 | 1003 | Nonce mismatch | `{"ok":false,"error":{"code":1003,"message":"Nonce mismatch","detail":"Client nonce does not match identity token nonce."}}` |
| 400 | 1004 | Authorization code invalid | `{"ok":false,"error":{"code":1004,"message":"Authorization code invalid","detail":"Code has been exchanged or expired."}}` |
| 401 | 1005 | Signature verification failed | `{"ok":false,"error":{"code":1005,"message":"Signature verification failed"}}` |
| 401 | 1006 | Token expired | `{"ok":false,"error":{"code":1006,"message":"Identity token expired"}}` |
| 409 | 1007 | Deleted account in recovery window | `{"ok":false,"error":{"code":1007,"message":"Account in recovery window","detail":"Use POST /v1/auth/recover."}}` |
| 429 | 5001 | Rate limited | `{"ok":false,"error":{"code":5001,"message":"Rate limit exceeded","retry_after_seconds":42}}` |
| 500 | 5000 | Internal error | `{"ok":false,"error":{"code":5000,"message":"Internal server error"}}` |

### 2.2 Token Refresh

#### POST /v1/auth/refresh

Exchange a valid refresh token for a new access + refresh token pair (rotation).

**Authentication:** None | **Rate limit:** 10 req/min per IP | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -H "X-Device-Id: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{"refresh_token": "rt_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4"}'
```

**Request body:**

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `refresh_token` | string | Yes | Non-empty, starts with `rt_` |

**Server-side flow:**

1. Look up refresh token by SHA-256 hash.
2. Validate: not expired, not revoked, `device_id` matches.
3. Revoke old token (single-use rotation).
4. Generate new pair.
5. On replay: revoke ALL tokens for user, log security event.

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "access_token": "eyJhbGciOiJFUzI1NiIs...",
    "refresh_token": "rt_z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k4j3i2h1g0f9e8d7c6",
    "token_type": "Bearer",
    "expires_in": 900
  },
  "meta": {
    "request_id": "req_r4s5t6u7v8w9",
    "timestamp": "2026-03-24T10:15:01Z"
  }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 1008 | Missing or malformed refresh token |
| 401 | 1009 | Refresh token expired |
| 401 | 1010 | Refresh token revoked or not found |
| 401 | 1011 | Replay detected — all sessions invalidated |
| 401 | 1012 | Device ID mismatch |
| 429 | 5001 | Rate limit exceeded |

### 2.3 JWT Specification

**Signing algorithm:** ES256 (ECDSA P-256 + SHA-256).

**Access token payload:**

```json
{
  "sub": "usr_abc123def456",
  "iss": "tempo-api",
  "aud": "app.tempo.ios",
  "iat": 1711270200,
  "exp": 1711271100,
  "jti": "tok_unique_id",
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "scopes": ["user"]
}
```

**Token TTLs:**

| Token | TTL | Storage |
|-------|-----|---------|
| Access token | 15 minutes | Client Keychain only |
| Refresh token | 30 days | Server DB + client Keychain |

**Key rotation:** 90-day cycle. Old keys kept 15 min post-rotation. JWKS endpoint publishes all active keys.

### 2.4 Logout

#### POST /v1/auth/logout

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/auth/logout \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "rt_a1b2c3d4...", "all_devices": false}'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `refresh_token` | string | Yes | Non-empty, starts with `rt_` | The refresh token to revoke |
| `all_devices` | boolean | No | Default `false` | If `true`, revokes all sessions for this user |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": { "revoked_count": 1 },
  "meta": { "request_id": "req_w8x9y0z1a2b3", "timestamp": "2026-03-24T10:30:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 1008 | Missing or malformed refresh token |
| 401 | 1001 | Invalid or expired access token |

### 2.5 Token Rotation on Suspected Compromise

#### POST /v1/auth/rotate

Force-rotate all tokens when compromise is suspected.

**Authentication:** Required | **Rate limit:** 3 req/hour | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/auth/rotate \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"reason": "suspicious_activity"}'
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `reason` | string | Yes | Enum: `suspicious_activity`, `device_lost`, `manual` |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "sessions_revoked": 3,
    "access_token": "eyJhbGciOiJFUzI1NiIs...",
    "refresh_token": "rt_new_secure_token...",
    "token_type": "Bearer",
    "expires_in": 900,
    "message": "All previous sessions invalidated."
  },
  "meta": { "request_id": "req_i0j1k2l3m4n5", "timestamp": "2026-03-24T10:35:00Z" }
}
```

### 2.6 JWKS Endpoint

#### GET /v1/.well-known/jwks.json

**Authentication:** None | **Rate limit:** 100 req/min per IP | **Cache:** `Cache-Control: public, max-age=86400`

```bash
curl https://api.tempo.app/v1/.well-known/jwks.json
```

**Response (200 OK):**

```json
{
  "keys": [
    {
      "kty": "EC", "crv": "P-256", "kid": "key-2026-03", "use": "sig", "alg": "ES256",
      "x": "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU",
      "y": "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"
    }
  ]
}
```

### 2.7 JWT Middleware

Every protected request passes through `JWTAuthMiddleware`:

1. Extract `Authorization: Bearer <token>`.
2. Verify JWT signature against JWKS.
3. Check `exp` > now. Expired = `401` code `1001`.
4. Check `iss` and `aud`.
5. Check `jti` against Redis blocklist.
6. Attach `req.auth.userId` and `req.auth.scopes`.
7. Any failure = immediate `401`.

---

## 3. User Management

### 3.1 Get Current User

#### GET /v1/users/me

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** ETag supported. Redis: 60s TTL on `user:{id}:profile`. Invalidated on PATCH.

**Example request:**

```bash
curl https://api.tempo.app/v1/users/me \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "id": "usr_abc123def456",
    "username": "nicola_d",
    "display_name": "Nicola Debbia",
    "avatar_url": "https://cdn.tempo.app/avatars/usr_abc123def456.webp",
    "bio": "Builder. Student. Optimizer.",
    "timezone": "Europe/Rome",
    "xp_total": 12450,
    "level": 8,
    "streak_days": 14,
    "integrations": {
      "whoop": { "connected": true, "last_sync_at": "2026-03-24T08:00:00Z" },
      "nutritrack": { "connected": true, "last_sync_at": "2026-03-24T09:30:00Z" }
    },
    "created_at": "2026-01-15T12:00:00Z",
    "updated_at": "2026-03-24T10:00:00Z"
  },
  "meta": { "request_id": "req_xyz792", "timestamp": "2026-03-24T10:30:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |

### 3.2 Update Current User

#### PATCH /v1/users/me

**Authentication:** Required | **Rate limit:** 20 req/min | **Cache:** Invalidates `user:{id}:profile` in Redis

**Example request:**

```bash
curl -X PATCH https://api.tempo.app/v1/users/me \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"username": "nicola", "display_name": "Nicola D.", "bio": "Builder."}'
```

**Request body (all fields optional):**

| Field | Type | Validation | Description |
|-------|------|------------|-------------|
| `username` | string | 3-30 chars, `^[a-zA-Z0-9_]+$`, unique | Public username |
| `display_name` | string | 1-50 chars | Display name |
| `bio` | string | Max 160 chars | Short bio |
| `timezone` | string | Valid IANA timezone | For local-time features |

**Response (200 OK):** Same shape as GET /v1/users/me with updated fields.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2001 | Validation failed |
| 401 | 1001 | Invalid or expired access token |
| 409 | 2002 | Username already taken |

### 3.3 Upload Avatar (Presigned URL)

#### POST /v1/users/me/avatar/presign

Get a presigned S3 URL for direct avatar upload from the client. Avoids routing large files through the API server.

**Authentication:** Required | **Rate limit:** 5 req/min | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/users/me/avatar/presign \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"content_type": "image/jpeg", "file_size_bytes": 245000}'
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `content_type` | string | Yes | `image/jpeg`, `image/png`, or `image/webp` |
| `file_size_bytes` | integer | Yes | 1 - 5242880 (5MB) |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "upload_url": "https://tempo-avatars.s3.eu-west-1.amazonaws.com/uploads/usr_abc123def456/avatar_v3.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=...",
    "upload_method": "PUT",
    "upload_headers": {
      "Content-Type": "image/jpeg",
      "x-amz-meta-user-id": "usr_abc123def456"
    },
    "expires_in": 300,
    "confirm_url": "/v1/users/me/avatar/confirm"
  },
  "meta": { "request_id": "req_xyz794", "timestamp": "2026-03-24T10:36:00Z" }
}
```

### 3.4 Confirm Avatar Upload

#### POST /v1/users/me/avatar/confirm

After uploading to S3, confirm the upload. Server validates the image, resizes to 256x256, converts to WebP, and updates the user profile.

**Authentication:** Required | **Rate limit:** 5 req/min | **Cache:** Invalidates user profile cache and CDN avatar cache

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/users/me/avatar/confirm \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json"
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "avatar_url": "https://cdn.tempo.app/avatars/usr_abc123def456_v3.webp"
  },
  "meta": { "request_id": "req_xyz795", "timestamp": "2026-03-24T10:37:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2003 | File too large (>5MB) |
| 400 | 2004 | Invalid file format |
| 400 | 2005 | Image too small (<128x128) |
| 404 | 2011 | No pending upload found |

### 3.5 Upload Avatar (Direct)

#### POST /v1/users/me/avatar

Direct upload via multipart. Fallback for when presigned URL flow is not feasible.

**Authentication:** Required | **Rate limit:** 5 req/min | **Cache:** Invalidates user profile cache

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/users/me/avatar \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -F "avatar=@photo.jpg"
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `avatar` | file | Yes | JPEG/PNG/WebP, max 5MB, min 128x128px |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": { "avatar_url": "https://cdn.tempo.app/avatars/usr_abc123def456_v3.webp" },
  "meta": { "request_id": "req_xyz796", "timestamp": "2026-03-24T10:38:00Z" }
}
```

### 3.6 Get User by ID

#### GET /v1/users/:id

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** ETag. Redis 60s TTL.

**Example request:**

```bash
curl https://api.tempo.app/v1/users/usr_def456ghi789 \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "id": "usr_def456ghi789",
    "username": "marco_r",
    "display_name": "Marco R.",
    "avatar_url": "https://cdn.tempo.app/avatars/usr_def456ghi789.webp",
    "bio": "Fitness nerd.",
    "xp_total": 8200,
    "level": 6,
    "streak_days": 7,
    "is_friend": true,
    "friendship_id": "fr_abc123",
    "created_at": "2026-02-01T08:00:00Z"
  },
  "meta": { "request_id": "req_xyz797", "timestamp": "2026-03-24T10:39:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 404 | 2006 | User not found |

### 3.7 Search Users

#### GET /v1/users/search

> **DEPRECATED:** Use `GET /v1/search/users` instead. This endpoint returns a `301` redirect. Will be removed in v2.

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** None (real-time search)

**Example request:**

```bash
curl "https://api.tempo.app/v1/users/search?q=marco&limit=5" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

| Parameter | Type | Required | Validation | Description |
|-----------|------|----------|------------|-------------|
| `q` | string | Yes | 2-50 chars | Search query |
| `limit` | integer | No | 1-20, default 10 | Max results |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": [
    {
      "id": "usr_def456ghi789",
      "username": "marco_r",
      "display_name": "Marco R.",
      "avatar_url": "https://cdn.tempo.app/avatars/usr_def456ghi789.webp",
      "xp_total": 8200,
      "level": 6,
      "is_friend": false,
      "has_pending_request": true
    }
  ],
  "meta": { "request_id": "req_xyz798", "timestamp": "2026-03-24T10:40:00Z" }
}
```

### 3.8 Delete Account

#### DELETE /v1/users/me

GDPR and App Store compliant account deletion.

**Authentication:** Required | **Rate limit:** 3 req/hour | **Cache:** Purges all user cache keys

**Example request:**

```bash
curl -X DELETE https://api.tempo.app/v1/users/me \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"confirmation": "DELETE"}'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `confirmation` | string | Yes | Must be exactly `"DELETE"` | Prevents accidental deletion |

**Server-side flow:**

1. Validate `confirmation == "DELETE"`. Reject with `2007` otherwise.
2. Soft-delete user (set `deleted_at`, anonymize PII).
3. Revoke all refresh tokens.
4. Disconnect all integrations (revoke Whoop tokens, remove NutriTrack config).
5. Delete device tokens.
6. Remove from active challenges.
7. Keep anonymized XP for leaderboard integrity.
8. After 30 days, background job hard-deletes all data.
9. Re-login within 30 days with same Apple ID triggers recovery (code 1007).

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2007 | Invalid confirmation (must be "DELETE") |
| 401 | 1001 | Invalid or expired access token |
| 429 | 5001 | Rate limit exceeded |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "message": "Account scheduled for deletion. Data permanently removed after 30 days.",
    "recovery_deadline": "2026-04-23T10:40:00Z"
  },
  "meta": { "request_id": "req_xyz799", "timestamp": "2026-03-24T10:40:00Z" }
}
```

### 3.9 Recover Deleted Account

#### POST /v1/auth/recover

**Authentication:** None (Apple auth) | **Rate limit:** 5 req/hour per IP | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/auth/recover \
  -H "Content-Type: application/json" \
  -d '{
    "identity_token": "eyJraWQiOiI...",
    "authorization_code": "c1234567890abcdef...",
    "nonce": "random-nonce"
  }'
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "access_token": "eyJhbGciOiJFUzI1NiIs...",
    "refresh_token": "rt_recovered_token...",
    "token_type": "Bearer",
    "expires_in": 900,
    "user": {
      "id": "usr_abc123def456",
      "username": "nicola_d",
      "display_name": "Nicola Debbia",
      "recovered_at": "2026-03-25T08:00:00Z"
    }
  },
  "meta": { "request_id": "req_xyz800", "timestamp": "2026-03-25T08:00:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 404 | 1013 | No deleted account for this Apple ID |
| 410 | 1014 | Recovery window expired (>30 days) |

---

## 4. User Preferences & Settings

### 4.1 Get Preferences

#### GET /v1/users/me/preferences

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 300s TTL on `user:{id}:prefs`. Invalidated on PUT.

**Example request:**

```bash
curl https://api.tempo.app/v1/users/me/preferences \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "notifications": {
      "recovery_morning": true,
      "accountability_nudges": true,
      "accountability_max_tier": 3,
      "leaderboard_changes": true,
      "challenge_updates": true,
      "achievement_unlocks": true,
      "weekly_summary": true,
      "quiet_hours_start": "23:00",
      "quiet_hours_end": "07:00"
    },
    "privacy": {
      "profile_visibility": "friends_only",
      "show_on_leaderboard": true,
      "show_streak": true,
      "show_level": true
    },
    "accountability": {
      "wake_time": "07:00",
      "sleep_target_time": "23:30",
      "escalation_enabled": true,
      "ps5_earned_not_default": true
    },
    "units": {
      "weight": "kg",
      "distance": "km",
      "temperature": "celsius"
    },
    "theme": "system",
    "haptics_enabled": true
  },
  "meta": { "request_id": "req_pref001", "timestamp": "2026-03-24T11:00:00Z" }
}
```

### 4.2 Update Preferences

#### PUT /v1/users/me/preferences

Full replacement of preferences. Client should GET first, modify, then PUT.

**Authentication:** Required | **Rate limit:** 20 req/min | **Cache:** Invalidates `user:{id}:prefs`

**Example request:**

```bash
curl -X PUT https://api.tempo.app/v1/users/me/preferences \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "notifications": {
      "recovery_morning": true,
      "accountability_nudges": true,
      "accountability_max_tier": 2,
      "leaderboard_changes": false,
      "challenge_updates": true,
      "achievement_unlocks": true,
      "weekly_summary": true,
      "quiet_hours_start": "23:00",
      "quiet_hours_end": "07:30"
    },
    "privacy": {
      "profile_visibility": "friends_only",
      "show_on_leaderboard": true,
      "show_streak": true,
      "show_level": true
    },
    "accountability": {
      "wake_time": "07:00",
      "sleep_target_time": "23:30",
      "escalation_enabled": true,
      "ps5_earned_not_default": true
    },
    "units": { "weight": "kg", "distance": "km", "temperature": "celsius" },
    "theme": "dark",
    "haptics_enabled": true
  }'
```

**Response (200 OK):** Returns the full preferences object (same as GET).

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2001 | Validation failed |
| 401 | 1001 | Invalid token |

### 4.3 Patch Single Preference

#### PATCH /v1/users/me/preferences

Partial update. Merge semantics -- only provided keys are updated.

**Authentication:** Required | **Rate limit:** 20 req/min | **Cache:** Invalidates `user:{id}:prefs`

**Example request:**

```bash
curl -X PATCH https://api.tempo.app/v1/users/me/preferences \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"notifications": {"leaderboard_changes": false}, "theme": "dark"}'
```

**Response (200 OK):** Returns full merged preferences.

---

## 5. Whoop Integration

### 5.1 Initiate Whoop OAuth

#### GET /v1/integrations/whoop/authorize

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** None

**Example request:**

```bash
curl "https://api.tempo.app/v1/integrations/whoop/authorize?redirect_scheme=tempo" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `redirect_scheme` | string | No | `tempo` | Custom URL scheme for deep-linking back |

**Server-side flow:**

1. Generate cryptographic `state` (32 random bytes, hex).
2. Store `(state, user_id, expires_at)` in Redis with 10-min TTL.
3. Build Whoop authorization URL with scopes: `read:recovery read:sleep read:workout read:cycles read:profile read:body_measurement`.
4. Return URL for client to open in `ASWebAuthenticationSession`.

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "authorization_url": "https://api.prod.whoop.com/oauth/oauth2/auth?client_id=tempo_app&redirect_uri=https://api.tempo.app/v1/integrations/whoop/callback&response_type=code&scope=read:recovery+read:sleep+read:workout+read:cycles+read:profile+read:body_measurement&state=a1b2c3d4e5f6",
    "state": "a1b2c3d4e5f6"
  },
  "meta": { "request_id": "req_whoop01", "timestamp": "2026-03-24T11:00:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid token |
| 409 | 3001 | Whoop already connected |

### 5.2 Whoop OAuth Callback

#### GET /v1/integrations/whoop/callback

**Authentication:** None (state parameter) | **Rate limit:** 10 req/min per IP | **Cache:** None

Handles redirect from Whoop. Exchanges code for tokens, encrypts with AES-256-GCM, triggers initial sync.

**Response:** `302` redirect to `tempo://integrations/whoop/success` or `tempo://integrations/whoop/error?code=3002`.

### 5.3 Whoop Connection Status

#### GET /v1/integrations/whoop/status

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 30s TTL

**Example request:**

```bash
curl https://api.tempo.app/v1/integrations/whoop/status \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "connected": true,
    "whoop_user_id": 12345,
    "connected_at": "2026-03-10T08:00:00Z",
    "last_sync_at": "2026-03-24T08:00:00Z",
    "last_sync_status": "success",
    "scopes": ["read:recovery", "read:sleep", "read:workout", "read:cycles", "read:profile", "read:body_measurement"],
    "token_expires_at": "2026-03-24T12:00:00Z",
    "webhook_active": true
  },
  "meta": { "request_id": "req_whoop02", "timestamp": "2026-03-24T11:05:00Z" }
}
```

### 5.4 Disconnect Whoop

#### DELETE /v1/integrations/whoop

**Authentication:** Required | **Rate limit:** 5 req/min | **Cache:** Invalidates whoop status cache

**Example request:**

```bash
curl -X DELETE https://api.tempo.app/v1/integrations/whoop \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "disconnected": true,
    "data_retained": true,
    "message": "Whoop disconnected. Previously synced data is retained."
  },
  "meta": { "request_id": "req_whoop03", "timestamp": "2026-03-24T11:10:00Z" }
}
```

### 5.5 Trigger Full Sync

#### POST /v1/integrations/whoop/sync

**Authentication:** Required | **Rate limit:** 3 req/hour (Heavy) | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/integrations/whoop/sync \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"days_back": 30}'
```

**Response (202 Accepted):**

```json
{
  "ok": true,
  "data": {
    "sync_id": "sync_abc123",
    "status": "queued",
    "days_back": 30,
    "estimated_seconds": 15
  },
  "meta": { "request_id": "req_whoop04", "timestamp": "2026-03-24T11:15:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 404 | 3005 | Whoop not connected |
| 409 | 3006 | Sync already in progress |
| 502 | 3007 | Whoop API unreachable |

### 5.6 Get Recovery Data

#### GET /v1/whoop/recovery

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 120s TTL on `whoop:{user_id}:recovery:{date}`. CDN: `Cache-Control: private, max-age=120`.

**Example request:**

```bash
curl "https://api.tempo.app/v1/whoop/recovery?date=2026-03-24" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `date` | string | No | today | Single date `YYYY-MM-DD` |
| `start_date` | string | No | -- | Range start |
| `end_date` | string | No | -- | Range end |
| `cursor` | string | No | -- | Pagination cursor |
| `limit` | integer | No | 25 | 1-100 |

**Response (200 OK -- single):**

```json
{
  "ok": true,
  "data": {
    "id": "rec_abc123",
    "whoop_cycle_id": 123456789,
    "date": "2026-03-24",
    "recovery_score": 78,
    "resting_heart_rate": 52,
    "hrv_rmssd_milli": 65.4,
    "spo2_percentage": 97.2,
    "skin_temp_celsius": 36.8,
    "user_calibrating": false,
    "synced_at": "2026-03-24T08:00:00Z"
  },
  "meta": { "request_id": "req_whoop05", "timestamp": "2026-03-24T11:20:00Z" }
}
```

### 5.7 Get Sleep Data

#### GET /v1/whoop/sleep

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 120s TTL

Same query parameters as recovery.

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "id": "slp_abc123",
    "whoop_sleep_id": 987654321,
    "date": "2026-03-24",
    "start_time": "2026-03-23T23:15:00Z",
    "end_time": "2026-03-24T06:45:00Z",
    "score": {
      "stage_summary": {
        "total_in_bed_time_milli": 27000000,
        "total_awake_time_milli": 2700000,
        "total_light_sleep_time_milli": 10800000,
        "total_slow_wave_sleep_time_milli": 7200000,
        "total_rem_sleep_time_milli": 5400000,
        "sleep_cycle_count": 4,
        "disturbance_count": 3
      },
      "sleep_needed": {
        "baseline_milli": 28800000,
        "need_from_sleep_debt_milli": 3600000,
        "need_from_recent_strain_milli": 1800000,
        "need_from_recent_nap_milli": -1800000
      },
      "respiratory_rate": 14.5,
      "sleep_performance_percentage": 88.0,
      "sleep_consistency_percentage": 92.0,
      "sleep_efficiency_percentage": 90.0
    },
    "nap": false,
    "synced_at": "2026-03-24T08:00:00Z"
  },
  "meta": { "request_id": "req_whoop06", "timestamp": "2026-03-24T11:25:00Z" }
}
```

### 5.8 Get Workout Data

#### GET /v1/whoop/workouts

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 120s TTL

**Response (200 OK):**

```json
{
  "ok": true,
  "data": [
    {
      "id": "wkt_abc123",
      "whoop_workout_id": 111222333,
      "date": "2026-03-24",
      "sport_id": 1,
      "sport_name": "Running",
      "start_time": "2026-03-24T07:00:00Z",
      "end_time": "2026-03-24T07:45:00Z",
      "score": {
        "strain": 12.5,
        "average_heart_rate": 155,
        "max_heart_rate": 182,
        "kilojoule": 1850.0,
        "distance_meter": 8500.0,
        "zone_duration": {
          "zone_zero_milli": 0, "zone_one_milli": 300000, "zone_two_milli": 600000,
          "zone_three_milli": 1200000, "zone_four_milli": 600000, "zone_five_milli": 0
        }
      },
      "synced_at": "2026-03-24T08:00:00Z"
    }
  ],
  "pagination": { "cursor": null, "has_more": false, "count": 1 },
  "meta": { "request_id": "req_whoop07", "timestamp": "2026-03-24T11:30:00Z" }
}
```

### 5.9 Get Cycle/Strain Data

#### GET /v1/whoop/cycles

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 120s TTL

### 5.10 Get Whoop Profile

#### GET /v1/whoop/profile

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 3600s TTL

### 5.11 Get Body Measurements

#### GET /v1/whoop/body

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 3600s TTL

### 5.12 Whoop Webhook Handler

#### POST /v1/webhooks/whoop

**Authentication:** HMAC-SHA256 signature (not JWT) | **Rate limit:** 1000 req/min per source IP | **Cache:** None

**Signature verification:**

1. Read raw request body as bytes (do not parse JSON first).
2. Read `X-Whoop-Timestamp` header. Reject if `abs(now - timestamp) > 300` seconds (5-minute replay window).
3. Compute `HMAC-SHA256(WHOOP_WEBHOOK_SECRET, timestamp + "." + raw_body)`.
4. **Timing-safe compare** the computed hex digest with `X-Whoop-Signature` using a constant-time comparison function (e.g., `MessageAuthenticationCode.isValidAuthenticationCode` in Swift Crypto). Do NOT use `==` string comparison -- this leaks signature bytes via timing side-channel.
5. On failure, return `401` with error code `3010`. Log the attempt with source IP for abuse detection.

**Supported events:**

| Event | Action |
|-------|--------|
| `recovery.updated` | Fetch recovery, send morning push |
| `sleep.updated` | Fetch sleep, update snapshot |
| `workout.updated` | Fetch workout, award XP |
| `cycle.updated` | Fetch cycle |
| `body_measurement.updated` | Fetch body data |
| `*.deleted` | Soft-delete local record |

**Response:** Always `200 OK` with `{"ok": true}`. Processing is async.

---

## 6. NutriTrack Proxy

Backend proxies to user's self-hosted NutriTrack Flask server, keeping URL/PIN off mobile network traffic.

### 6.1 Connect NutriTrack

#### POST /v1/integrations/nutritrack/connect

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/integrations/nutritrack/connect \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"base_url": "https://nutritrack.nicoladebbia.com", "pin": "123456"}'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `base_url` | string | Yes | Valid HTTPS URL (HTTP allowed in development only). Private/reserved IP ranges blocked (10.x, 172.16-31.x, 192.168.x, 127.x, 169.254.x, ::1, fc00::/7). DNS resolution checked server-side to prevent DNS rebinding. Max 200 chars. | NutriTrack server URL |
| `pin` | string | Yes | 4-8 digits, `^\d{4,8}$` | NutriTrack access PIN |

**Server-side SSRF protection:** The server resolves the `base_url` hostname to an IP address BEFORE making the connectivity test request. If the resolved IP is in any private/reserved range, the request is rejected with error code `2001`. This prevents DNS rebinding attacks where a hostname initially resolves to a public IP but later resolves to a private IP.

**Server-side:** Tests connectivity, encrypts PIN with AES-256-GCM, stores.

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "connected": true,
    "base_url": "https://nutritrack.nicoladebbia.com",
    "tested_at": "2026-03-24T12:00:00Z",
    "server_version": "1.2.0"
  },
  "meta": { "request_id": "req_nt01", "timestamp": "2026-03-24T12:00:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2001 | Validation failed (invalid URL format, private IP, PIN format) |
| 400 | 3013 | NutriTrack auth failed (wrong PIN) |
| 401 | 1001 | Invalid or expired access token |
| 502 | 3014 | NutriTrack unreachable |
| 504 | 3015 | NutriTrack timeout |

### 6.2 NutriTrack Status

#### GET /v1/integrations/nutritrack/status

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** Redis 30s TTL

### 6.3 Disconnect NutriTrack

#### DELETE /v1/integrations/nutritrack

**Authentication:** Required | **Rate limit:** 5 req/min | **Cache:** Purges all nutritrack cache keys

### 6.4 Get Today's Nutrition

#### GET /v1/nutritrack/today

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 120s TTL. Key: `nutritrack:{user_id}:today:{date}`. `Cache-Control: private, max-age=120`. Stale-while-revalidate: serves expired cache if NutriTrack is unreachable.

**Example request:**

```bash
curl https://api.tempo.app/v1/nutritrack/today \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "date": "2026-03-24",
    "meals": [
      {
        "id": 1, "name": "Breakfast", "time": "08:00",
        "items": [{ "name": "Oatmeal with banana", "calories": 350, "protein_g": 12.0, "carbs_g": 58.0, "fat_g": 8.0, "fiber_g": 6.0 }],
        "totals": { "calories": 350, "protein_g": 12.0, "carbs_g": 58.0, "fat_g": 8.0 }
      }
    ],
    "daily_totals": { "calories": 1850, "protein_g": 145.0, "carbs_g": 220.0, "fat_g": 62.0, "fiber_g": 28.0 },
    "targets": { "calories": 2400, "protein_g": 180.0, "carbs_g": 280.0, "fat_g": 75.0 },
    "cached": true, "cached_at": "2026-03-24T12:13:00Z"
  },
  "meta": { "request_id": "req_nt02", "timestamp": "2026-03-24T12:15:00Z" }
}
```

### 6.5 Get Meal Plan

#### GET /v1/nutritrack/plan/:date

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 300s TTL

### 6.6 Get Macro Balance

#### GET /v1/nutritrack/macros

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 120s TTL

**Example request:**

```bash
curl https://api.tempo.app/v1/nutritrack/macros \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "date": "2026-03-24",
    "consumed": { "calories": 1850, "protein_g": 145.0, "carbs_g": 220.0, "fat_g": 62.0 },
    "target": { "calories": 2400, "protein_g": 180.0, "carbs_g": 280.0, "fat_g": 75.0 },
    "remaining": { "calories": 550, "protein_g": 35.0, "carbs_g": 60.0, "fat_g": 13.0 },
    "percentage": { "calories": 77.1, "protein_g": 80.6, "carbs_g": 78.6, "fat_g": 82.7 },
    "cached": true, "cached_at": "2026-03-24T12:23:00Z"
  },
  "meta": { "request_id": "req_nt03", "timestamp": "2026-03-24T12:25:00Z" }
}
```

### 6.7 Get Weekly Nutrition

#### GET /v1/nutritrack/week/:date

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** Redis 600s TTL

### 6.8 NutriTrack Caching Strategy

| Endpoint | TTL | Invalidation |
|----------|-----|-------------|
| `/nutritrack/today` | 2 min | Auto-expire |
| `/nutritrack/plan/:date` | 5 min | Auto-expire |
| `/nutritrack/macros` | 2 min | Auto-expire |
| `/nutritrack/week/:date` | 10 min | Auto-expire |

**Cache bypass:** `Cache-Control: no-cache` header forces fresh fetch.

**Stale serving:** If NutriTrack unreachable and cache exists (even expired), serve with `"stale": true`. After 3 consecutive failures, mark integration `degraded` for 5 minutes and push-notify user.

---

## 7. Training & Workouts

### 7.1 Get Exercise Library

#### GET /v1/exercises

Browse the exercise catalog. Seeded with common exercises; users can add custom ones.

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 3600s TTL (shared). ETag supported. `Cache-Control: public, max-age=3600`.

**Example request:**

```bash
curl "https://api.tempo.app/v1/exercises?muscle_group=chest&limit=10" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `muscle_group` | string | No | all | Filter: `chest`, `back`, `shoulders`, `arms`, `legs`, `core`, `cardio`, `full_body` |
| `equipment` | string | No | all | Filter: `barbell`, `dumbbell`, `machine`, `bodyweight`, `cable`, `kettlebell`, `band` |
| `q` | string | No | -- | Search by name |
| `cursor` | string | No | -- | Pagination |
| `limit` | integer | No | 25 | 1-100 |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": [
    {
      "id": "ex_bench_press",
      "name": "Barbell Bench Press",
      "muscle_group": "chest",
      "secondary_muscles": ["triceps", "shoulders"],
      "equipment": "barbell",
      "instructions": "Lie flat on a bench. Grip barbell slightly wider than shoulder width...",
      "is_custom": false,
      "created_by": null
    }
  ],
  "pagination": { "cursor": "eyJpZCI6ImV4X2luYyJ9", "has_more": true, "count": 10 },
  "meta": { "request_id": "req_ex01", "timestamp": "2026-03-24T14:00:00Z" }
}
```

### 7.2 Create Custom Exercise

#### POST /v1/exercises

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** Invalidates exercise library cache for user

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/exercises \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Incline Cable Fly",
    "muscle_group": "chest",
    "secondary_muscles": ["shoulders"],
    "equipment": "cable",
    "instructions": "Set cables to lowest position..."
  }'
```

**Response (201 Created):**

```json
{
  "ok": true,
  "data": {
    "id": "ex_usr_abc123_001",
    "name": "Incline Cable Fly",
    "muscle_group": "chest",
    "secondary_muscles": ["shoulders"],
    "equipment": "cable",
    "is_custom": true,
    "created_by": "usr_abc123def456"
  },
  "meta": { "request_id": "req_ex02", "timestamp": "2026-03-24T14:05:00Z" }
}
```

### 7.2b Delete Custom Exercise

#### DELETE /v1/exercises/:id

Delete a custom exercise created by the authenticated user. System exercises cannot be deleted.

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** Invalidates exercise library cache

> **Authorization:** Server MUST verify `exercises.created_by == req.auth.userId`. Returns `403` if the exercise is a system exercise or owned by another user.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 403 | 1015 | Cannot delete system exercises or exercises owned by another user |
| 404 | 2006 | Exercise not found |

### 7.3 Upload Manual Workouts

#### POST /v1/workouts

Upload manually logged workouts (non-Whoop).

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** None. Triggers XP recalculation.

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/workouts \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "workouts": [{
      "client_id": "local_wkt_abc123",
      "type": "strength_training",
      "name": "Upper Body Push",
      "started_at": "2026-03-24T16:00:00Z",
      "ended_at": "2026-03-24T17:15:00Z",
      "duration_minutes": 75,
      "notes": "Felt strong. Increased bench press by 2.5kg.",
      "exercises": [
        {
          "exercise_id": "ex_bench_press",
          "sets": [
            { "weight_kg": 80.0, "reps": 8 },
            { "weight_kg": 80.0, "reps": 8 },
            { "weight_kg": 82.5, "reps": 6 }
          ]
        }
      ]
    }]
  }'
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `workouts` | array | Yes | 1-10 items |
| `workouts[].client_id` | string | Yes | Unique per user (dedup) |
| `workouts[].type` | string | Yes | `strength_training`, `cardio`, `flexibility`, `sport`, `other` |
| `workouts[].started_at` | string | Yes | ISO 8601 |
| `workouts[].ended_at` | string | Yes | ISO 8601, after started_at |
| `workouts[].duration_minutes` | integer | Yes | 1-600 |
| `workouts[].exercises` | array | No | Max 50 items |

**Response (201 Created):**

```json
{
  "ok": true,
  "data": {
    "created": 1,
    "skipped": 0,
    "workouts": [
      { "id": "mwkt_abc123", "client_id": "local_wkt_abc123", "type": "strength_training", "duration_minutes": 75 }
    ]
  },
  "meta": { "request_id": "req_wkt01", "timestamp": "2026-03-24T17:20:00Z" }
}
```

### 7.4 Get Workout History

#### GET /v1/workouts

Combined Whoop + manual workouts.

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 60s TTL

**Example request:**

```bash
curl "https://api.tempo.app/v1/workouts?start_date=2026-03-01&end_date=2026-03-24&limit=10" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

### 7.5 Get Exercise Progression

#### GET /v1/exercises/:id/progression

Track progression for a specific exercise over time (e.g., bench press weight history).

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 300s TTL

**Example request:**

```bash
curl "https://api.tempo.app/v1/exercises/ex_bench_press/progression?period=90d" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `period` | string | `90d` | `30d`, `90d`, `180d`, `365d`, `all` |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "exercise_id": "ex_bench_press",
    "exercise_name": "Barbell Bench Press",
    "data_points": [
      { "date": "2026-01-15", "max_weight_kg": 70.0, "max_reps_at_max_weight": 8, "total_volume_kg": 1680 },
      { "date": "2026-02-01", "max_weight_kg": 72.5, "max_reps_at_max_weight": 8, "total_volume_kg": 1740 },
      { "date": "2026-03-24", "max_weight_kg": 82.5, "max_reps_at_max_weight": 6, "total_volume_kg": 1950 }
    ],
    "estimated_1rm_kg": 95.2,
    "progression_rate_kg_per_week": 0.65
  },
  "meta": { "request_id": "req_prog01", "timestamp": "2026-03-24T14:10:00Z" }
}
```

### 7.6 Get Workout Plans

#### GET /v1/workout-plans

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 300s TTL

### 7.7 Create Workout Plan

#### POST /v1/workout-plans

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** Invalidates plans cache

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/workout-plans \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Push/Pull/Legs",
    "description": "3-day split focused on compound movements",
    "days": [
      {
        "name": "Push Day",
        "day_of_week": 1,
        "exercises": [
          { "exercise_id": "ex_bench_press", "sets": 4, "reps_min": 6, "reps_max": 8 },
          { "exercise_id": "ex_overhead_press", "sets": 3, "reps_min": 8, "reps_max": 10 }
        ]
      }
    ]
  }'
```

**Response (201 Created):**

```json
{
  "ok": true,
  "data": {
    "id": "plan_abc123",
    "name": "Push/Pull/Legs",
    "description": "3-day split focused on compound movements",
    "days": [
      {
        "name": "Push Day", "day_of_week": 1,
        "exercises": [
          { "exercise_id": "ex_bench_press", "exercise_name": "Barbell Bench Press", "sets": 4, "reps_min": 6, "reps_max": 8 }
        ]
      }
    ],
    "created_at": "2026-03-24T14:15:00Z"
  },
  "meta": { "request_id": "req_plan01", "timestamp": "2026-03-24T14:15:00Z" }
}
```

### 7.7b Update Workout Plan

#### PATCH /v1/workout-plans/:id

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** Invalidates plans cache

> **Authorization:** Server MUST verify `workout_plans.user_id == req.auth.userId`.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2001 | Validation failed |
| 401 | 1001 | Invalid or expired access token |
| 404 | 2006 | Workout plan not found (or not owned by user) |

### 7.7c Delete Workout Plan

#### DELETE /v1/workout-plans/:id

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** Invalidates plans cache

> **Authorization:** Server MUST verify `workout_plans.user_id == req.auth.userId`.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 404 | 2006 | Workout plan not found (or not owned by user) |

### 7.7d Delete Manual Workout

#### DELETE /v1/workouts/:id

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** Triggers XP recalculation (may reduce XP)

> **Authorization:** Server MUST verify `manual_workouts.user_id == req.auth.userId`. Whoop-synced workouts cannot be deleted via this endpoint.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 403 | 2001 | Cannot delete Whoop-synced workouts |
| 404 | 2006 | Workout not found (or not owned by user) |

---

## 8. Study Sessions

### 8.1 Upload Study Sessions

#### POST /v1/study-sessions

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/study-sessions \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "sessions": [{
      "client_id": "local_study_abc123",
      "subject": "Distributed Systems",
      "started_at": "2026-03-24T10:00:00Z",
      "ended_at": "2026-03-24T11:30:00Z",
      "duration_minutes": 90,
      "technique": "pomodoro",
      "focus_rating": 4,
      "notes": "Covered consensus algorithms."
    }]
  }'
```

**Response (201 Created):**

```json
{
  "ok": true,
  "data": {
    "created": 1, "skipped": 0,
    "sessions": [{ "id": "study_abc123", "client_id": "local_study_abc123", "subject": "Distributed Systems", "duration_minutes": 90 }]
  },
  "meta": { "request_id": "req_study01", "timestamp": "2026-03-24T17:25:00Z" }
}
```

### 8.2 List Study Sessions

#### GET /v1/study-sessions

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 60s TTL

**Example request:**

```bash
curl "https://api.tempo.app/v1/study-sessions?start_date=2026-03-01&end_date=2026-03-24" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

### 8.2b Delete Study Session

#### DELETE /v1/study-sessions/:id

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** None. Triggers XP recalculation.

> **Authorization:** Server MUST verify `study_sessions.user_id == req.auth.userId`.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 404 | 2006 | Study session not found (or not owned by user) |

### 8.3 Study Analytics

#### GET /v1/study-sessions/analytics

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** Redis 300s TTL

**Example request:**

```bash
curl "https://api.tempo.app/v1/study-sessions/analytics?period=30d" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "period": "30d",
    "total_minutes": 2700,
    "total_sessions": 36,
    "avg_duration_minutes": 75,
    "avg_focus_rating": 3.8,
    "by_subject": [
      { "subject": "Distributed Systems", "minutes": 1200, "sessions": 16 },
      { "subject": "Machine Learning", "minutes": 900, "sessions": 12 }
    ],
    "by_technique": [
      { "technique": "pomodoro", "minutes": 1500, "sessions": 20 },
      { "technique": "deep_work", "minutes": 1200, "sessions": 16 }
    ],
    "daily_avg_minutes": 90,
    "best_day_of_week": "Monday",
    "best_time_of_day": "10:00-12:00"
  },
  "meta": { "request_id": "req_study02", "timestamp": "2026-03-24T14:30:00Z" }
}
```

---

## 9. Daily Snapshots & History

### 9.1 Upload Daily Snapshot

#### POST /v1/snapshots

Primary data sync mechanism from iOS app.

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** Invalidates snapshot cache for date

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/snapshots \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: idem_snap_2026-03-24_v3" \
  -d '{
    "date": "2026-03-24",
    "timezone": "Europe/Rome",
    "recovery": { "score": 78, "hrv_rmssd_milli": 65.4, "resting_heart_rate": 52, "spo2_percentage": 97.2, "skin_temp_celsius": 36.8 },
    "sleep": { "total_duration_milli": 27000000, "sleep_performance_percentage": 88.0, "sleep_efficiency_percentage": 90.0, "rem_duration_milli": 5400000, "deep_duration_milli": 7200000, "respiratory_rate": 14.5, "disturbance_count": 3 },
    "strain": { "day_strain": 8.2, "kilojoule": 7500.0, "average_heart_rate": 72, "max_heart_rate": 182, "workout_count": 1 },
    "nutrition": { "calories": 1850, "protein_g": 145.0, "carbs_g": 220.0, "fat_g": 62.0, "target_calories": 2400, "target_protein_g": 180.0, "adherence_percentage": 77.1, "meals_logged": 3 },
    "study": { "total_minutes": 90, "sessions": 2 },
    "accountability": { "recovery_viewed": true, "workout_completed": true, "meals_logged_count": 3, "study_completed": true, "escalation_tier": 0 },
    "xp_earned": 145,
    "streak_day": 14,
    "device_info": { "model": "iPhone 15 Pro", "os_version": "19.4", "app_version": "1.0.0" }
  }'
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": { "snapshot_id": "snap_abc123", "date": "2026-03-24", "created": false, "updated": true },
  "meta": { "request_id": "req_snap01", "timestamp": "2026-03-24T15:00:00Z" }
}
```

### 9.2 Get Snapshots

#### GET /v1/snapshots

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 60s TTL

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `start_date` | string | 7 days ago | Start date |
| `end_date` | string | today | End date |
| `fields` | string | all | Comma-separated: `recovery,sleep,strain,nutrition,study,accountability` |
| `cursor` | string | -- | Pagination cursor |
| `limit` | integer | 25 | 1-100 |

### 9.3 Get Snapshot Aggregation

#### GET /v1/snapshots/aggregate

Aggregated statistics over a date range.

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** Redis 300s TTL

**Example request:**

```bash
curl "https://api.tempo.app/v1/snapshots/aggregate?start_date=2026-03-01&end_date=2026-03-24&granularity=weekly" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `start_date` | string | 30d ago | Start |
| `end_date` | string | today | End |
| `granularity` | string | `daily` | `daily`, `weekly`, `monthly` |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "granularity": "weekly",
    "buckets": [
      {
        "period_start": "2026-03-18",
        "period_end": "2026-03-24",
        "avg_recovery": 74.2,
        "avg_sleep_performance": 85.1,
        "total_workouts": 4,
        "avg_strain": 10.8,
        "avg_calories": 2180,
        "avg_protein_adherence": 82.5,
        "total_study_minutes": 450,
        "total_xp": 680,
        "streak_maintained": true
      }
    ]
  },
  "meta": { "request_id": "req_agg01", "timestamp": "2026-03-24T15:10:00Z" }
}
```

---

## 10. Arena / Social Endpoints

### 10.1 Record XP Event

#### POST /v1/xp/events

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Invalidates XP caches, triggers leaderboard refresh (debounced)

> **SECURITY: Server-side point calculation.** The client sends the event `type`, `source`, and `reference_id`. The server calculates the `points` value using the XP schedule below. Clients MUST NOT send a `points` field -- it is ignored if present. This prevents XP manipulation. The server validates that `reference_id` corresponds to a real resource owned by the authenticated user (e.g., a real workout, a real study session) before awarding XP. Duplicate `(user_id, type, reference_id)` tuples are rejected (idempotent).

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/xp/events \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "events": [{
      "type": "workout_logged",
      "source": "whoop",
      "reference_id": "wkt_abc123",
      "occurred_at": "2026-03-24T07:45:00Z"
    }]
  }'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `events` | array | Yes | 1-50 items | Batch of XP events |
| `events[].type` | string | Yes | Must be a valid XP event type (see table below) | Event type |
| `events[].source` | string | Yes | `whoop`, `manual`, `system`, `nutritrack` | Origin of the event |
| `events[].reference_id` | string | Yes | Must reference an existing resource owned by the authenticated user | The resource that triggered this XP |
| `events[].occurred_at` | string | Yes | ISO 8601, not in the future, not older than 7 days | When the event happened |

**XP Event Types (server-calculated points):**

| Type | Points | Calculation |
|------|--------|-------------|
| `workout_logged` | 30-100 | Server calculates from strain: `min(100, 30 + strain * 5)` |
| `sleep_target_met` | 40 | Fixed. Server verifies sleep_performance >= 85% from Whoop data |
| `recovery_checked` | 10 | Fixed. Server verifies recovery was viewed (via snapshot) |
| `meal_logged` | 15 | Fixed. Server verifies meal exists in NutriTrack for the date |
| `nutrition_target_met` | 50 | Fixed. Server verifies daily macros from NutriTrack |
| `study_session` | 20-80 | Server calculates from duration: `min(80, duration_minutes * 0.89)` |
| `streak_maintained` | 25 | Fixed. Server verifies streak from snapshots |
| `streak_milestone` | 100-500 | Server determines from streak_days: 7d=100, 14d=150, 30d=200, 60d=300, 90d=350, 180d=400, 365d=500 |
| `challenge_joined` | 10 | Fixed. Server verifies participation record |
| `challenge_won` | 200 | Fixed. Server verifies winner from challenge standings |
| `friend_added` | 5 | Fixed. Server verifies friendship record |
| `insight_viewed` | 10 | Fixed. Server verifies insight exists for user |
| `achievement_unlocked` | 50-200 | Server determines from achievement tier |

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "events_recorded": 1, "events_skipped": 0, "xp_earned": 50,
    "xp_total": 12500, "level": 8, "level_changed": false,
    "next_level_xp": 15000, "achievements_triggered": []
  },
  "meta": { "request_id": "req_xp01", "timestamp": "2026-03-24T13:00:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 4001 | Invalid XP event type |
| 400 | 4002 | Invalid reference_id (resource not found or not owned by user) |
| 400 | 2001 | Validation failed (missing fields, future date, etc.) |
| 401 | 1001 | Invalid or expired access token |
| 409 | 4022 | Duplicate event (reference_id already used for this type) |
| 429 | 5001 | Rate limit exceeded |

### 10.2 Get Today's XP

#### GET /v1/xp/today

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 30s TTL

### 10.3 Get XP History

#### GET /v1/xp/history

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 60s TTL

### 10.4 Get Level Info

#### GET /v1/xp/level

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** ETag. Redis 300s TTL.

**Example request:**

```bash
curl https://api.tempo.app/v1/xp/level \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "level": 8, "title": "Optimizer",
    "xp_total": 12500, "xp_for_current_level": 10000, "xp_for_next_level": 15000,
    "xp_progress": 2500, "xp_needed": 2500, "progress_percentage": 50.0,
    "levels": [
      { "level": 1, "title": "Rookie", "xp_required": 0 },
      { "level": 2, "title": "Beginner", "xp_required": 100 },
      { "level": 3, "title": "Starter", "xp_required": 500 },
      { "level": 4, "title": "Consistent", "xp_required": 1000 },
      { "level": 5, "title": "Dedicated", "xp_required": 2500 },
      { "level": 6, "title": "Driven", "xp_required": 5000 },
      { "level": 7, "title": "Focused", "xp_required": 7500 },
      { "level": 8, "title": "Optimizer", "xp_required": 10000 },
      { "level": 9, "title": "Elite", "xp_required": 15000 },
      { "level": 10, "title": "Master", "xp_required": 25000 },
      { "level": 11, "title": "Legend", "xp_required": 50000 },
      { "level": 12, "title": "Transcendent", "xp_required": 100000 }
    ]
  },
  "meta": { "request_id": "req_xp02", "timestamp": "2026-03-24T13:15:00Z" }
}
```

### 10.5 Leaderboards

#### GET /v1/leaderboards/:period

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 300s TTL. Materialized view refreshes every 5 min.

Path parameter `period`: `weekly`, `monthly`, `alltime`.

> **Authorization:** Leaderboard only includes users who have `privacy.show_on_leaderboard = true`. The authenticated user's rank is always included regardless of visibility setting. Only friends and users with `profile_visibility: "public"` show usernames; others appear as "Anonymous".

**Example request:**

```bash
curl https://api.tempo.app/v1/leaderboards/weekly \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "period": "weekly",
    "week_start": "2026-03-18", "week_end": "2026-03-24",
    "refreshed_at": "2026-03-24T13:00:00Z",
    "my_rank": 2, "my_xp": 680,
    "rankings": [
      {
        "rank": 1,
        "user": { "id": "usr_def456ghi789", "username": "marco_r", "display_name": "Marco R.", "avatar_url": "https://cdn.tempo.app/avatars/usr_def456ghi789.webp", "level": 6 },
        "xp": 720, "is_me": false
      },
      {
        "rank": 2,
        "user": { "id": "usr_abc123def456", "username": "nicola", "display_name": "Nicola D.", "avatar_url": "https://cdn.tempo.app/avatars/usr_abc123def456.webp", "level": 8 },
        "xp": 680, "is_me": true
      }
    ]
  },
  "meta": { "request_id": "req_lb01", "timestamp": "2026-03-24T13:20:00Z" }
}
```

### 10.6 Friendships

#### POST /v1/friends/requests

Send a friend request.

**Authentication:** Required | **Rate limit:** 20 req/min

```bash
curl -X POST https://api.tempo.app/v1/friends/requests \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"user_id": "usr_def456ghi789"}'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `user_id` | string | Yes | Must be a valid user ID, not the authenticated user's own ID, not already friends | Target user |

**Response (201 Created):**

```json
{
  "ok": true,
  "data": {
    "id": "freq_abc123",
    "from_user_id": "usr_abc123def456",
    "to_user_id": "usr_def456ghi789",
    "status": "pending",
    "created_at": "2026-03-24T13:30:00Z"
  },
  "meta": { "request_id": "req_fr01", "timestamp": "2026-03-24T13:30:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 4003 | Missing target user |
| 400 | 4004 | Cannot befriend yourself |
| 401 | 1001 | Invalid or expired access token |
| 404 | 2006 | Target user not found |
| 409 | 4005 | Already friends |
| 409 | 4006 | Request already pending |

#### GET /v1/friends/requests

**Authentication:** Required | **Rate limit:** 60 req/min

#### POST /v1/friends/requests/:id/accept

**Authentication:** Required | **Rate limit:** 20 req/min

#### POST /v1/friends/requests/:id/decline

**Authentication:** Required | **Rate limit:** 20 req/min

#### GET /v1/friends

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 60s TTL

#### DELETE /v1/friends/:id

**Authentication:** Required | **Rate limit:** 10 req/min

#### GET /v1/friends/:id/stats

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 120s TTL

> **Authorization:** Server MUST verify that `:id` is a friendship where the authenticated user is either `user_a_id` or `user_b_id`. Returns `4010 Not friends` otherwise. Only exposes data the friend has opted to share via their `privacy` preferences.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 403 | 4010 | Not friends (IDOR protection) |
| 404 | 4011 | Friendship not found |

### 10.7 Challenges

#### POST /v1/challenges

Create a challenge.

**Authentication:** Required | **Rate limit:** 10 req/min

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/challenges \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "title": "March Madness Fitness",
    "description": "Who can earn the most XP this week?",
    "type": "xp_total",
    "duration_days": 7,
    "starts_at": "2026-03-25T00:00:00Z",
    "max_participants": 10,
    "invite_user_ids": ["usr_def456ghi789"],
    "visibility": "friends_only"
  }'
```

**Challenge types:** `xp_total`, `workout_count`, `workout_strain`, `sleep_score`, `study_minutes`, `streak_maintain`, `nutrition_adherence`

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `title` | string | Yes | 3-100 chars | Challenge title |
| `description` | string | No | Max 500 chars | Challenge description |
| `type` | string | Yes | Must be a valid challenge type | Metric to compete on |
| `duration_days` | integer | Yes | 1-90 | Challenge duration |
| `starts_at` | string | Yes | ISO 8601, must be in the future (within 30 days) | Start time |
| `max_participants` | integer | No | 2-50, default 10 | Max participants |
| `invite_user_ids` | array | No | Max 49 items, must all be friends of the creator | Users to invite |
| `visibility` | string | No | `friends_only`, `public`, default `friends_only` | Who can see/join |

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2001 | Validation failed |
| 400 | 4012 | Invalid challenge type |
| 400 | 4013 | Start date must be in the future |
| 400 | 4014 | Invited user is not a friend |
| 401 | 1001 | Invalid or expired access token |
| 429 | 4015 | Too many active challenges (max 5 created per user) |

#### GET /v1/challenges

List active/upcoming/completed challenges.

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 60s TTL

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `status` | string | `active` | `upcoming`, `active`, `completed`, `all` |
| `cursor` | string | -- | Pagination cursor |
| `limit` | integer | 25 | 1-100 |

> **Authorization:** Only returns challenges where the user is a participant, was invited, or that are `public`/`friends_only` and visible to the user.

#### GET /v1/challenges/:id

Full detail with standings.

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 30s TTL

> **Authorization:** Server MUST verify the authenticated user is a participant, the creator, or the challenge visibility allows access. Returns `4016 Challenge access denied` otherwise.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 403 | 4016 | Challenge access denied |
| 404 | 4017 | Challenge not found |

#### POST /v1/challenges/:id/join

**Authentication:** Required | **Rate limit:** 10 req/min

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 403 | 4016 | Challenge access denied (private challenge, not invited) |
| 404 | 4017 | Challenge not found |
| 409 | 4018 | Already participating |
| 409 | 4019 | Challenge full |
| 409 | 4020 | Challenge already ended |

#### POST /v1/challenges/:id/leave

**Authentication:** Required | **Rate limit:** 10 req/min

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 404 | 4017 | Challenge not found |
| 409 | 4020 | Challenge already ended |
| 409 | 4021 | Not a participant |

#### GET /v1/challenges/history

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 120s TTL

### 10.8 Achievements

#### POST /v1/achievements/check

Trigger achievement evaluation. Server checks all unearned achievements against the user's current data.

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** None

> **Note:** This is also triggered automatically after XP events. Manual trigger is for edge cases (e.g., after data import).

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "checked": 42,
    "newly_earned": [
      { "achievement_id": "ach_streak_14", "name": "Two-Week Warrior", "tier": "silver", "xp_reward": 100 }
    ]
  },
  "meta": { "request_id": "req_ach01", "timestamp": "2026-03-24T13:45:00Z" }
}
```

#### GET /v1/achievements

Earned achievements for the authenticated user.

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 300s TTL

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `category` | string | all | Filter by category |
| `cursor` | string | -- | Pagination cursor |
| `limit` | integer | 25 | 1-100 |

#### GET /v1/achievements/available

Full catalog with progress toward each achievement. ETag supported.

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** ETag. Redis 3600s TTL.

**Achievement tiers:** bronze (50 XP), silver (100 XP), gold (200 XP), diamond (500 XP).

**Achievement categories:** fitness, sleep, nutrition, study, social, streak, milestone.

---

## 11. Non-Negotiables & Accountability

### 11.1 Get Non-Negotiable Config

#### GET /v1/accountability/config

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 300s TTL

**Example request:**

```bash
curl https://api.tempo.app/v1/accountability/config \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "non_negotiables": [
      { "id": "nn_recovery", "name": "Check recovery", "required": true, "xp_reward": 10 },
      { "id": "nn_workout", "name": "Complete a workout", "required": true, "xp_reward": 30 },
      { "id": "nn_meals", "name": "Log 3 meals", "required": true, "min_count": 3, "xp_reward": 15 },
      { "id": "nn_study", "name": "Study session", "required": false, "min_minutes": 30, "xp_reward": 20 }
    ],
    "escalation": {
      "enabled": true,
      "tiers": [
        { "tier": 1, "delay_hours_after_wake": 2, "message": "Gentle nudge" },
        { "tier": 2, "delay_hours_after_wake": 4, "message": "Streak at risk" },
        { "tier": 3, "hours_before_midnight": 3, "message": "Tough love" },
        { "tier": 4, "at": "00:01", "message": "Streak lost" }
      ]
    },
    "ps5_rule": {
      "enabled": true,
      "required_completions": ["nn_recovery", "nn_workout", "nn_meals"],
      "message": "PS5 is earned, not default."
    }
  },
  "meta": { "request_id": "req_acc01", "timestamp": "2026-03-24T15:30:00Z" }
}
```

### 11.2 Update Non-Negotiable Config

#### PUT /v1/accountability/config

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** Invalidates config cache

### 11.3 Get Today's Accountability Status

#### GET /v1/accountability/today

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 30s TTL

**Example request:**

```bash
curl https://api.tempo.app/v1/accountability/today \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "date": "2026-03-24",
    "items": [
      { "id": "nn_recovery", "name": "Check recovery", "completed": true, "completed_at": "2026-03-24T07:00:00Z" },
      { "id": "nn_workout", "name": "Complete a workout", "completed": true, "completed_at": "2026-03-24T07:45:00Z" },
      { "id": "nn_meals", "name": "Log 3 meals", "completed": false, "progress": 2, "target": 3 },
      { "id": "nn_study", "name": "Study session", "completed": true, "completed_at": "2026-03-24T11:30:00Z" }
    ],
    "all_required_complete": false,
    "ps5_earned": false,
    "current_escalation_tier": 0,
    "streak_days": 14,
    "streak_at_risk": true
  },
  "meta": { "request_id": "req_acc02", "timestamp": "2026-03-24T15:35:00Z" }
}
```

### 11.4 Get Accountability History

#### GET /v1/accountability/history

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 120s TTL

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `start_date` | string | 7 days ago | Start date |
| `end_date` | string | today | End date |
| `cursor` | string | -- | Pagination cursor |
| `limit` | integer | 25 | 1-100 |

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2008 | Date in the future |
| 400 | 2009 | Date too far in the past |
| 401 | 1001 | Invalid or expired access token |

---

## 11.5 NutriTrack PIN Update

### PATCH /v1/integrations/nutritrack/credentials

Update NutriTrack connection credentials (base URL and/or PIN) without disconnecting.

**Authentication:** Required | **Rate limit:** 5 req/min | **Cache:** Invalidates NutriTrack cache

**Example request:**

```bash
curl -X PATCH https://api.tempo.app/v1/integrations/nutritrack/credentials \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"pin": "654321"}'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `base_url` | string | No | Valid HTTPS URL, private IPs blocked | NutriTrack server URL |
| `pin` | string | No | 4-8 digits | NutriTrack access PIN |

At least one field must be provided. Server re-tests connectivity after update.

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "connected": true,
    "tested_at": "2026-03-24T12:00:00Z",
    "base_url": "https://nutritrack.nicoladebbia.com"
  },
  "meta": { "request_id": "req_nt_cred01", "timestamp": "2026-03-24T12:00:00Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2001 | Validation failed (invalid URL or PIN format) |
| 401 | 1001 | Invalid or expired access token |
| 404 | 3016 | NutriTrack not connected |
| 400 | 3013 | NutriTrack auth failed with new credentials |
| 502 | 3014 | NutriTrack unreachable |

---

## 11.6 Rate Limit Status

### GET /v1/rate-limits

Returns the authenticated user's current rate limit status across all endpoint categories.

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** None (real-time)

**Example request:**

```bash
curl https://api.tempo.app/v1/rate-limits \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "limits": [
      { "endpoint": "POST /v1/insights/weekly", "limit": 3, "window": "24h", "remaining": 2, "resets_at": "2026-03-25T00:00:00Z" },
      { "endpoint": "POST /v1/insights/pattern", "limit": 5, "window": "24h", "remaining": 4, "resets_at": "2026-03-25T00:00:00Z" },
      { "endpoint": "POST /v1/reports", "limit": 3, "window": "24h", "remaining": 3, "resets_at": "2026-03-25T00:00:00Z" },
      { "endpoint": "POST /v1/exports/gdpr", "limit": 1, "window": "24h", "remaining": 1, "resets_at": "2026-03-25T00:00:00Z" },
      { "endpoint": "POST /v1/integrations/whoop/sync", "limit": 3, "window": "1h", "remaining": 2, "resets_at": "2026-03-24T13:00:00Z" }
    ]
  },
  "meta": { "request_id": "req_rl01", "timestamp": "2026-03-24T12:30:00Z" }
}
```

---

## 12. Sync & Batch Operations

### 12.1 Batch Sync

#### POST /v1/sync/batch

Sync multiple data types in a single request. Reduces round trips on app launch.

> **N+1 Query Prevention:** This endpoint processes all data types in a single database transaction. Exercise IDs referenced in workouts are validated via a single `WHERE id IN (...)` query, not one query per exercise. XP events are inserted as a batch `INSERT ... VALUES (...), (...), (...)`. Snapshot upsert uses `INSERT ... ON CONFLICT (user_id, date) DO UPDATE`.

**Authentication:** Required | **Rate limit:** 10 req/min | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/sync/batch \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "snapshot": { "date": "2026-03-24", "timezone": "Europe/Rome", "recovery": { "score": 78 }, "xp_earned": 145, "streak_day": 14 },
    "workouts": [{ "client_id": "local_wkt_001", "type": "strength_training", "started_at": "2026-03-24T16:00:00Z", "ended_at": "2026-03-24T17:15:00Z", "duration_minutes": 75 }],
    "study_sessions": [{ "client_id": "local_study_001", "subject": "ML", "started_at": "2026-03-24T10:00:00Z", "ended_at": "2026-03-24T11:30:00Z", "duration_minutes": 90 }],
    "xp_events": [{ "type": "workout_logged", "points": 50, "source": "manual", "reference_id": "local_wkt_001", "occurred_at": "2026-03-24T17:15:00Z" }]
  }'
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "snapshot": { "snapshot_id": "snap_abc123", "updated": true },
    "workouts": { "created": 1, "skipped": 0 },
    "study_sessions": { "created": 1, "skipped": 0 },
    "xp_events": { "events_recorded": 1, "events_skipped": 0, "xp_earned": 50 },
    "xp_total": 12550,
    "level": 8,
    "streak_days": 14
  },
  "meta": { "request_id": "req_batch01", "timestamp": "2026-03-24T17:30:00Z" }
}
```

### 12.2 Get Sync Status

#### GET /v1/sync/status

Returns last sync timestamps for all data types, so the client knows what to refresh.

**Authentication:** Required | **Rate limit:** 100 req/min | **Cache:** Redis 10s TTL

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "whoop_last_sync": "2026-03-24T08:00:00Z",
    "nutritrack_last_sync": "2026-03-24T09:30:00Z",
    "snapshot_last_upload": "2026-03-24T15:00:00Z",
    "pending_sync_jobs": 0,
    "server_time": "2026-03-24T17:35:00Z"
  },
  "meta": { "request_id": "req_sync01", "timestamp": "2026-03-24T17:35:00Z" }
}
```

---

## 13. Push Notifications

### 13.1 Register Device

#### POST /v1/devices

**Authentication:** Required | **Rate limit:** 10 req/min

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/devices \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "token": "a1b2c3d4e5f6...",
    "platform": "ios",
    "device_id": "550e8400-e29b-41d4-a716-446655440000",
    "app_version": "1.0.0",
    "os_version": "19.4",
    "environment": "production"
  }'
```

### 13.2 Unregister Device

#### DELETE /v1/devices/:device_id

**Authentication:** Required | **Rate limit:** 10 req/min

### 13.3 Notification Types

| Type | Trigger | Timing |
|------|---------|--------|
| `recovery_morning` | Whoop webhook | Immediate |
| `accountability_tier1` | Cron | 2h after wake |
| `accountability_tier2` | Cron | 4h after wake |
| `accountability_tier3` | Cron | 3h before midnight |
| `accountability_tier4` | Cron | 00:01 user's TZ |
| `leaderboard_change` | Leaderboard refresh | Within 5 min |
| `challenge_invite` | Challenge creation | Immediate |
| `challenge_update` | Cron | 24h and 1h before end |
| `achievement_unlock` | Achievement check | Immediate |
| `weekly_summary` | Cron | Sunday 20:00 user's TZ |

### 13.4 Notification Payloads

All follow APNs format with a `tempo` custom payload:

```json
{
  "aps": {
    "alert": { "title": "Good morning! Recovery: 78%", "subtitle": "HRV 65ms | RHR 52bpm", "body": "You're in the green. Time to push it." },
    "sound": "recovery.caf",
    "badge": 1,
    "category": "RECOVERY_REPORT",
    "thread-id": "recovery"
  },
  "tempo": {
    "type": "recovery_morning",
    "data": { "recovery_score": 78, "hrv": 65.4, "rhr": 52, "date": "2026-03-24" },
    "deep_link": "tempo://recovery/2026-03-24"
  }
}
```

---

## 14. Outbound Webhooks

Tempo sends webhooks to registered URLs for Arena events (for third-party integrations or external displays).

### 14.1 Register Webhook

#### POST /v1/webhooks/outbound

**Authentication:** Required (admin scope) | **Rate limit:** 5 req/min

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/webhooks/outbound \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://my-server.com/tempo-webhook",
    "events": ["challenge.completed", "leaderboard.updated", "achievement.earned"],
    "secret": "whsec_my_secret_key_here"
  }'
```

**Response (201 Created):**

```json
{
  "ok": true,
  "data": {
    "id": "whk_abc123",
    "url": "https://my-server.com/tempo-webhook",
    "events": ["challenge.completed", "leaderboard.updated", "achievement.earned"],
    "active": true,
    "created_at": "2026-03-24T16:00:00Z"
  },
  "meta": { "request_id": "req_whk01", "timestamp": "2026-03-24T16:00:00Z" }
}
```

### 14.2 Webhook Delivery

**Delivery guarantees:**
- At-least-once delivery.
- Retry policy: 3 retries with exponential backoff (1min, 5min, 30min).
- Timeout: 10 seconds per delivery attempt.
- Dead letter queue: after 3 failed attempts, event is moved to DLQ. Retrievable via `GET /v1/webhooks/outbound/:id/dlq`.

**Signature & replay protection:**

Each delivery includes these headers:

| Header | Description |
|--------|-------------|
| `X-Tempo-Signature` | `sha256=<hex-encoded HMAC-SHA256>` |
| `X-Tempo-Timestamp` | Unix timestamp (seconds) when the payload was signed |
| `X-Tempo-Delivery-Id` | Unique delivery ID (for dedup on receiver side) |

**Signature computation:** `HMAC-SHA256(secret, X-Tempo-Timestamp + "." + raw_request_body)`.

**Receiver verification (required steps):**

1. Read `X-Tempo-Timestamp`. Reject if `abs(now - timestamp) > 300` seconds (5-minute replay window).
2. Construct the signed payload: `timestamp + "." + raw_body` (raw bytes, no parsing).
3. Compute `HMAC-SHA256(webhook_secret, signed_payload)`.
4. **Timing-safe compare** the computed hex digest with the value after `sha256=` in `X-Tempo-Signature`. Use a constant-time comparison function (e.g., `crypto.timingSafeEqual` in Node, `hmac.compare_digest` in Python, `MessageAuthenticationCode.isValidAuthenticationCode` in Swift Crypto). Do NOT use `==` string comparison.
5. Track `X-Tempo-Delivery-Id` to reject duplicate deliveries.

### 14.3 List Outbound Webhooks

#### GET /v1/webhooks/outbound

### 14.4 Delete Outbound Webhook

#### DELETE /v1/webhooks/outbound/:id

### 14.5 Get Dead Letter Queue

#### GET /v1/webhooks/outbound/:id/dlq

### 14.6 Retry DLQ Event

#### POST /v1/webhooks/outbound/:id/dlq/:event_id/retry

---

## 15. AI Insights

### 15.1 Generate Weekly Report

#### POST /v1/insights/weekly

**Authentication:** Required | **Rate limit:** 3 req/day per user | **Cache:** Weekly insights cached forever (immutable). Key: `insight:{user_id}:weekly:{week_start}`.

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/insights/weekly \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"week_start": "2026-03-18", "force_regenerate": false}'
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "id": "ins_abc123",
    "type": "weekly",
    "week_start": "2026-03-18",
    "week_end": "2026-03-24",
    "title": "Strong consistency, sleep needs attention",
    "summary": "You maintained your 14-day streak and hit protein targets 6/7 days. Recovery averaged 72% -- down from 81%. Main driver: sleep averaged 6.5h vs 7.5h target.",
    "sections": [
      {
        "title": "Recovery & Sleep", "icon": "bed.double.fill",
        "body": "Average recovery dropped 9 points (72% vs 81%). HRV declined from 68ms to 61ms. Tuesday and Thursday late nights correlated with lowest scores.",
        "sentiment": "warning"
      },
      { "title": "Fitness", "icon": "flame.fill", "body": "4 workouts, avg strain 11.2. 5K pace improved to 5:04/km.", "sentiment": "positive" },
      { "title": "Nutrition", "icon": "fork.knife", "body": "Protein target hit 6/7 days. Calories slightly below on 3 days.", "sentiment": "positive" },
      { "title": "Academics", "icon": "book.fill", "body": "7.5h study across 6 sessions. Monday's 2h deep work was most productive.", "sentiment": "positive" }
    ],
    "action_items": [
      "Set 23:30 bedtime alarm on weeknights.",
      "Shift study earlier on Tuesday/Thursday.",
      "Add 200kcal post-workout snack on under-calorie days."
    ],
    "compared_to_last_week": { "recovery_avg_change": -9, "sleep_avg_change": -43, "workout_count_change": 0, "xp_change": 45, "protein_adherence_change": 14 },
    "generated_at": "2026-03-24T20:00:00Z",
    "model": "claude-sonnet-4-20250514"
  },
  "meta": { "request_id": "req_ins01", "timestamp": "2026-03-24T20:00:05Z" }
}
```

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 5002 | Insufficient data (need 3+ days) |
| 429 | 5003 | Daily AI limit reached |
| 503 | 5004 | Claude API unavailable |

### 15.2 Analyze Patterns

#### POST /v1/insights/pattern

**Authentication:** Required | **Rate limit:** 5 req/day | **Cache:** None (unique questions)

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/insights/pattern \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "question": "How does my sleep affect my workout performance?",
    "date_range": { "start": "2026-02-01", "end": "2026-03-24" },
    "data_types": ["sleep", "workouts", "recovery"]
  }'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `question` | string | Yes | 10-500 chars, stripped of HTML/control chars | Natural language question |
| `date_range.start` | string | Yes | `YYYY-MM-DD`, not before account creation date | Analysis start |
| `date_range.end` | string | Yes | `YYYY-MM-DD`, not in the future, `end >= start`, max 180-day range | Analysis end |
| `data_types` | array | Yes | 1-6 items, each must be: `sleep`, `recovery`, `workouts`, `nutrition`, `study`, `strain` | Data domains to analyze |

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 400 | 2001 | Validation failed (question too short/long, invalid date range, etc.) |
| 400 | 5002 | Insufficient data (need 7+ days with data in the range) |
| 401 | 1001 | Invalid or expired access token |
| 429 | 5003 | Daily AI limit reached |
| 503 | 5004 | Claude API unavailable |

### 15.3 Get Insight History

#### GET /v1/insights/history

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 300s TTL

### 15.4 Cost Control

| Control | Value |
|---------|-------|
| Daily limit per user | 3 weekly + 5 pattern |
| Monthly budget cap | $50 (server-side tracker) |
| Max output tokens | 2000 |
| Model | `claude-sonnet-4-20250514` |
| Retry policy | 2 retries, exponential backoff |

### 15.5 Privacy

No PII sent to Claude. Only aggregated health metrics. No user ID, name, email, or Apple ID.

---

## 16. Reports & Data Export

### 16.1 Generate Report

#### POST /v1/reports

**Authentication:** Required | **Rate limit:** 3 req/day | **Cache:** Generated reports cached in S3 for 24h

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/reports \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "type": "monthly_summary",
    "month": "2026-03",
    "format": "json"
  }'
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `type` | string | Yes | `monthly_summary`, `training_log`, `nutrition_log`, `full_export` |
| `month` | string | Conditional | `YYYY-MM` for monthly reports |
| `start_date` | string | Conditional | For date-range reports |
| `end_date` | string | Conditional | For date-range reports |
| `format` | string | No | `json` (default), `csv` |

**Response (202 Accepted):**

```json
{
  "ok": true,
  "data": {
    "report_id": "rpt_abc123",
    "status": "generating",
    "estimated_seconds": 30,
    "poll_url": "/v1/reports/rpt_abc123"
  },
  "meta": { "request_id": "req_rpt01", "timestamp": "2026-03-24T18:00:00Z" }
}
```

### 16.2 Get Report Status / Download

#### GET /v1/reports/:id

**Authentication:** Required | **Rate limit:** 60 req/min

> **Authorization:** Server MUST verify that the report belongs to the authenticated user (`report.user_id == req.auth.userId`). Returns `404` for mismatched users (not `403`, to avoid leaking report IDs).

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 404 | 2006 | Report not found (or not owned by user) |

**Response (200 OK -- ready):**

```json
{
  "ok": true,
  "data": {
    "report_id": "rpt_abc123",
    "status": "ready",
    "download_url": "https://cdn.tempo.app/reports/rpt_abc123.json?token=signed_url",
    "expires_at": "2026-03-25T18:00:00Z",
    "size_bytes": 45200
  },
  "meta": { "request_id": "req_rpt02", "timestamp": "2026-03-24T18:01:00Z" }
}
```

### 16.3 GDPR Data Export

#### POST /v1/exports/gdpr

Export all user data. Required by GDPR Article 20 (data portability).

**Authentication:** Required | **Rate limit:** 1 req/day | **Cache:** None

**Example request:**

```bash
curl -X POST https://api.tempo.app/v1/exports/gdpr \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{"format": "json"}'
```

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `format` | string | No | `json` (default) | Export format |

**Response (202 Accepted):**

```json
{
  "ok": true,
  "data": {
    "export_id": "exp_abc123",
    "status": "generating",
    "estimated_minutes": 5,
    "includes": ["profile", "preferences", "whoop_data", "nutrition_data", "workouts", "study_sessions", "snapshots", "xp_events", "achievements", "friendships", "challenges", "insights"],
    "notification": "You will receive a push notification when your export is ready."
  },
  "meta": { "request_id": "req_gdpr01", "timestamp": "2026-03-24T18:10:00Z" }
}
```

### 16.4 Get Export Status

#### GET /v1/exports/:id

**Authentication:** Required | **Rate limit:** 60 req/min

> **Authorization:** Server MUST verify that the export belongs to the authenticated user (`export.user_id == req.auth.userId`). Returns `404` for mismatched users.

**Error responses:**

| Status | Code | Condition |
|--------|------|-----------|
| 401 | 1001 | Invalid or expired access token |
| 404 | 2006 | Export not found (or not owned by user) |

---

## 17. Search

### 17.1 Search Exercises

#### GET /v1/search/exercises

**Authentication:** Required | **Rate limit:** 60 req/min | **Cache:** Redis 60s TTL

```bash
curl "https://api.tempo.app/v1/search/exercises?q=bench+press&limit=5" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

### 17.2 Search Users

#### GET /v1/search/users

Canonical user search endpoint. `GET /v1/users/search` is a deprecated alias that returns a `301` redirect to this endpoint. New clients MUST use `/v1/search/users`.

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** None (real-time search)

| Parameter | Type | Required | Validation | Description |
|-----------|------|----------|------------|-------------|
| `q` | string | Yes | 2-50 chars, stripped of special characters | Search query (matches username, display_name) |
| `limit` | integer | No | 1-20, default 10 | Max results |

### 17.3 Search Challenges

#### GET /v1/search/challenges

Search public or friend-visible challenges.

**Authentication:** Required | **Rate limit:** 30 req/min | **Cache:** None

```bash
curl "https://api.tempo.app/v1/search/challenges?q=fitness&status=active&limit=10" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

---

## 18. Admin Endpoints

All admin endpoints require `scopes: ["user", "admin"]` in the JWT.

### 18.1 List Users

#### GET /v1/admin/users

**Authentication:** Required (admin) | **Rate limit:** 30 req/min

```bash
curl "https://api.tempo.app/v1/admin/users?limit=25&sort=created_at" \
  -H "Authorization: Bearer eyJhbGciOiJFUzI1NiIs..."
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": [
    {
      "id": "usr_abc123def456", "username": "nicola_d", "display_name": "Nicola Debbia",
      "xp_total": 12450, "level": 8, "streak_days": 14,
      "integrations": { "whoop": true, "nutritrack": true },
      "created_at": "2026-01-15T12:00:00Z", "last_active_at": "2026-03-24T15:00:00Z",
      "deleted_at": null
    }
  ],
  "pagination": { "cursor": "eyJpZCI6InVzcl8ifQ==", "has_more": true, "count": 25 },
  "meta": { "request_id": "req_adm01", "timestamp": "2026-03-24T19:00:00Z" }
}
```

### 18.2 Get System Stats

#### GET /v1/admin/stats

**Authentication:** Required (admin) | **Rate limit:** 30 req/min | **Cache:** Redis 60s TTL

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "users": { "total": 142, "active_today": 87, "active_this_week": 128, "new_this_week": 12 },
    "integrations": { "whoop_connected": 95, "nutritrack_connected": 48 },
    "xp": { "total_awarded_this_week": 48500, "avg_per_user_this_week": 379 },
    "challenges": { "active": 23, "completed_this_week": 8 },
    "ai": { "insights_generated_today": 15, "monthly_cost_cents": 1240, "monthly_budget_cents": 5000 },
    "infrastructure": {
      "db_connections_active": 12, "db_connections_max": 50,
      "redis_memory_mb": 45, "redis_keys": 12400,
      "background_jobs_queued": 3, "background_jobs_running": 1
    }
  },
  "meta": { "request_id": "req_adm02", "timestamp": "2026-03-24T19:05:00Z" }
}
```

### 18.3 Ban/Suspend User

#### POST /v1/admin/users/:id/suspend

**Authentication:** Required (admin) | **Rate limit:** 10 req/min

### 18.4 Get Audit Log

#### GET /v1/admin/audit-log

**Authentication:** Required (admin) | **Rate limit:** 30 req/min

Returns log of sensitive operations (account deletions, suspensions, integration connects/disconnects, admin actions).

---

## 19. App Configuration

### 19.1 Get App Config

#### GET /v1/config

Feature flags, minimum version, maintenance mode. Checked on every app launch.

**Authentication:** None | **Rate limit:** 100 req/min per IP | **Cache:** `Cache-Control: public, max-age=300`. CDN: 5 min. Redis: 60s.

**Example request:**

```bash
curl https://api.tempo.app/v1/config \
  -H "X-Client-Version: 1.0.0"
```

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "minimum_version": "1.0.0",
    "latest_version": "1.2.0",
    "force_update": false,
    "maintenance_mode": false,
    "maintenance_message": null,
    "feature_flags": {
      "arena_enabled": true,
      "ai_insights_enabled": true,
      "workout_plans_enabled": false,
      "dark_mode_enabled": true,
      "whoop_webhooks_enabled": true
    },
    "api_status": "operational",
    "announcement": {
      "id": "ann_001",
      "title": "New: AI Insights",
      "body": "Get weekly AI-powered performance analysis.",
      "type": "info",
      "dismissible": true
    }
  },
  "meta": { "request_id": "req_cfg01", "timestamp": "2026-03-24T20:00:00Z" }
}
```

---

## 20. Real-Time (WebSocket)

### 20.1 WebSocket Connection

#### GET /v1/ws

Upgrade to WebSocket for live updates.

**Authentication:** JWT passed as query parameter: `/v1/ws?token=eyJhbGci...`

> **Security note:** JWT in query parameters is a known trade-off for WebSocket (browsers do not support `Authorization` headers on WebSocket upgrades). To mitigate log exposure: (1) the server MUST strip the `token` parameter from access logs, (2) the token is validated and consumed immediately on upgrade -- it is not stored or logged, (3) use short-lived access tokens (15 min) to minimize the window of exposure.

**Connection flow:**

1. Client connects with JWT in query string.
2. Server validates JWT (same as middleware). On failure, responds with HTTP `401` before upgrade.
3. Connection established. Server sends `{"type": "connected", "user_id": "usr_abc123"}`.
4. Server pushes events. Client can send heartbeats.
5. Token expiry: server sends `{"type": "token_expiring", "expires_in": 60}`. Client should refresh and reconnect.
6. On reconnect, client may send `{"type": "resume", "last_event_id": "evt_abc123"}` to replay missed events (server buffers last 5 minutes of events per user in Redis).

### 20.2 Server-Sent Events

| Event Type | Payload | When |
|------------|---------|------|
| `connected` | `{user_id}` | WebSocket connection established |
| `token_expiring` | `{expires_in}` | JWT expiring soon (60s warning) |
| `leaderboard.update` | `{period, rankings}` | Leaderboard refresh |
| `challenge.score_update` | `{challenge_id, standings}` | Any participant's score changes |
| `challenge.completed` | `{challenge_id, winner}` | Challenge ends |
| `challenge.invite` | `{challenge_id, title, from_user}` | Invited to a challenge |
| `achievement.earned` | `{achievement_id, name, tier, xp_reward}` | Achievement unlocked |
| `friend.request` | `{from_user, request_id}` | New friend request |
| `friend.accepted` | `{user_id, friendship_id}` | Friend request accepted |
| `xp.earned` | `{amount, total, level, level_changed}` | XP awarded |
| `xp.level_up` | `{new_level, title, xp_total}` | Level up event |
| `sync.whoop_completed` | `{sync_id, status, records_synced}` | Whoop sync job finished |
| `sync.whoop_failed` | `{sync_id, error_code, message}` | Whoop sync job failed |
| `accountability.tier_change` | `{tier, message, streak_at_risk}` | Escalation tier changed |
| `integration.degraded` | `{integration, reason}` | NutriTrack/Whoop connectivity issue |
| `integration.restored` | `{integration}` | Integration back online |
| `report.ready` | `{report_id, download_url}` | Report generation complete |
| `export.ready` | `{export_id, download_url}` | GDPR export complete |

**Event message format:**

```json
{
  "type": "xp.earned",
  "data": { "amount": 50, "total": 12500, "level": 8, "level_changed": false },
  "timestamp": "2026-03-24T13:00:00Z",
  "event_id": "evt_abc123"
}
```

Clients should use `event_id` for dedup in case of reconnection replays.

### 20.3 Heartbeat

Client sends `{"type": "ping"}` every 30 seconds. Server responds `{"type": "pong"}`. If no ping received for 90 seconds, server closes connection.

---

## 21. Database Schema

### 21.1 Complete Schema

```sql
-- ============================================================
-- Extensions
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- Users
-- ============================================================
CREATE TABLE users (
    id              TEXT PRIMARY KEY DEFAULT 'usr_' || encode(gen_random_bytes(12), 'hex'),
    apple_user_id   TEXT UNIQUE NOT NULL,
    username        TEXT UNIQUE NOT NULL,
    display_name    TEXT NOT NULL DEFAULT '',
    bio             TEXT DEFAULT NULL,
    avatar_url      TEXT DEFAULT NULL,
    timezone        TEXT NOT NULL DEFAULT 'UTC',
    xp_total        INTEGER NOT NULL DEFAULT 0,
    level           INTEGER NOT NULL DEFAULT 1,
    streak_days     INTEGER NOT NULL DEFAULT 0,
    streak_last_date DATE DEFAULT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ DEFAULT NULL,
    suspended_at    TIMESTAMPTZ DEFAULT NULL,
    last_active_at  TIMESTAMPTZ DEFAULT NULL,

    CONSTRAINT username_format CHECK (username ~ '^[a-zA-Z0-9_]{3,30}$'),
    CONSTRAINT bio_length CHECK (char_length(bio) <= 160),
    CONSTRAINT display_name_length CHECK (char_length(display_name) <= 50)
);

CREATE INDEX idx_users_apple_user_id ON users(apple_user_id);
CREATE INDEX idx_users_username ON users(username) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_xp_total ON users(xp_total DESC);
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_users_last_active ON users(last_active_at DESC) WHERE deleted_at IS NULL;

-- ============================================================
-- User Preferences
-- ============================================================
CREATE TABLE user_preferences (
    user_id     TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    prefs       JSONB NOT NULL DEFAULT '{}',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- Refresh Tokens
-- ============================================================
CREATE TABLE refresh_tokens (
    id          TEXT PRIMARY KEY DEFAULT 'rt_' || encode(gen_random_bytes(24), 'hex'),
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id   TEXT NOT NULL,
    token_hash  TEXT NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ DEFAULT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT token_not_expired CHECK (expires_at > created_at)
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash) WHERE revoked_at IS NULL;
CREATE INDEX idx_refresh_tokens_device ON refresh_tokens(user_id, device_id);
CREATE INDEX idx_refresh_tokens_cleanup ON refresh_tokens(expires_at) WHERE revoked_at IS NULL;

-- ============================================================
-- Apple Auth
-- ============================================================
CREATE TABLE apple_auth (
    user_id             TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    apple_refresh_token TEXT NOT NULL,
    last_validated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- Whoop Integration
-- ============================================================
CREATE TABLE whoop_integrations (
    user_id             TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    whoop_user_id       INTEGER UNIQUE NOT NULL,
    access_token_enc    TEXT NOT NULL,
    refresh_token_enc   TEXT NOT NULL,
    token_expires_at    TIMESTAMPTZ NOT NULL,
    scopes              TEXT[] NOT NULL DEFAULT '{}',
    webhook_id          TEXT DEFAULT NULL,
    last_sync_at        TIMESTAMPTZ DEFAULT NULL,
    last_sync_status    TEXT DEFAULT NULL,
    connected_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    disconnected_at     TIMESTAMPTZ DEFAULT NULL
);

CREATE INDEX idx_whoop_integrations_whoop_user_id ON whoop_integrations(whoop_user_id);

-- ============================================================
-- Whoop Recovery
-- ============================================================
CREATE TABLE whoop_recovery (
    id                  TEXT PRIMARY KEY DEFAULT 'rec_' || encode(gen_random_bytes(8), 'hex'),
    user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    whoop_cycle_id      BIGINT NOT NULL,
    date                DATE NOT NULL,
    recovery_score      INTEGER,
    resting_heart_rate  INTEGER,
    hrv_rmssd_milli     REAL,
    spo2_percentage     REAL,
    skin_temp_celsius   REAL,
    user_calibrating    BOOLEAN NOT NULL DEFAULT FALSE,
    synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ DEFAULT NULL,

    CONSTRAINT uq_whoop_recovery_user_date UNIQUE (user_id, date)
);

CREATE INDEX idx_whoop_recovery_user_date ON whoop_recovery(user_id, date DESC);
CREATE INDEX idx_whoop_recovery_whoop_cycle ON whoop_recovery(whoop_cycle_id);

-- ============================================================
-- Whoop Sleep
-- ============================================================
CREATE TABLE whoop_sleep (
    id                              TEXT PRIMARY KEY DEFAULT 'slp_' || encode(gen_random_bytes(8), 'hex'),
    user_id                         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    whoop_sleep_id                  BIGINT UNIQUE NOT NULL,
    date                            DATE NOT NULL,
    start_time                      TIMESTAMPTZ NOT NULL,
    end_time                        TIMESTAMPTZ NOT NULL,
    total_in_bed_milli              BIGINT,
    total_awake_milli               BIGINT,
    total_light_sleep_milli         BIGINT,
    total_slow_wave_sleep_milli     BIGINT,
    total_rem_sleep_milli           BIGINT,
    sleep_cycle_count               INTEGER,
    disturbance_count               INTEGER,
    baseline_sleep_need_milli       BIGINT,
    need_from_sleep_debt_milli      BIGINT,
    need_from_strain_milli          BIGINT,
    need_from_nap_milli             BIGINT,
    respiratory_rate                REAL,
    sleep_performance_percentage    REAL,
    sleep_consistency_percentage    REAL,
    sleep_efficiency_percentage     REAL,
    is_nap                          BOOLEAN NOT NULL DEFAULT FALSE,
    synced_at                       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at                      TIMESTAMPTZ DEFAULT NULL,

    -- Uniqueness is on whoop_sleep_id (column-level UNIQUE above).
    -- No (user_id, date, is_nap) constraint: users can have multiple naps per day.
);

CREATE INDEX idx_whoop_sleep_user_date ON whoop_sleep(user_id, date DESC);

-- ============================================================
-- Whoop Workouts
-- ============================================================
CREATE TABLE whoop_workouts (
    id                  TEXT PRIMARY KEY DEFAULT 'wkt_' || encode(gen_random_bytes(8), 'hex'),
    user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    whoop_workout_id    BIGINT UNIQUE NOT NULL,
    date                DATE NOT NULL,
    sport_id            INTEGER NOT NULL,
    sport_name          TEXT NOT NULL,
    start_time          TIMESTAMPTZ NOT NULL,
    end_time            TIMESTAMPTZ NOT NULL,
    strain              REAL,
    average_heart_rate  INTEGER,
    max_heart_rate      INTEGER,
    kilojoule           REAL,
    percent_recorded    REAL,
    distance_meter      REAL,
    altitude_gain_meter REAL,
    altitude_change_meter REAL,
    zone_zero_milli     BIGINT DEFAULT 0,
    zone_one_milli      BIGINT DEFAULT 0,
    zone_two_milli      BIGINT DEFAULT 0,
    zone_three_milli    BIGINT DEFAULT 0,
    zone_four_milli     BIGINT DEFAULT 0,
    zone_five_milli     BIGINT DEFAULT 0,
    synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ DEFAULT NULL
);

CREATE INDEX idx_whoop_workouts_user_date ON whoop_workouts(user_id, date DESC);

-- ============================================================
-- Whoop Cycles, Body, Profiles (same as original)
-- ============================================================
CREATE TABLE whoop_cycles (
    id TEXT PRIMARY KEY DEFAULT 'cyc_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    whoop_cycle_id BIGINT UNIQUE NOT NULL,
    date DATE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    strain REAL,
    kilojoule REAL,
    average_heart_rate INTEGER,
    max_heart_rate INTEGER,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uq_whoop_cycles_user_date UNIQUE (user_id, date)
);

CREATE INDEX idx_whoop_cycles_user_date ON whoop_cycles(user_id, date DESC);

CREATE TABLE whoop_body (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    height_meter REAL,
    weight_kilogram REAL,
    max_heart_rate INTEGER,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE whoop_profiles (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    whoop_user_id INTEGER NOT NULL,
    email TEXT,
    first_name TEXT,
    last_name TEXT,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- NutriTrack Integration
-- ============================================================
CREATE TABLE nutritrack_integrations (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    base_url TEXT NOT NULL,
    pin_enc TEXT NOT NULL,
    last_success_at TIMESTAMPTZ DEFAULT NULL,
    failure_count INTEGER NOT NULL DEFAULT 0,
    degraded_until TIMESTAMPTZ DEFAULT NULL,
    connected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- XP Events (partitioned by month for high volume)
-- NOTE: PostgreSQL does not support foreign keys on partitioned
-- tables referencing non-partitioned tables. user_id integrity
-- is enforced at the application layer. A nightly job checks
-- for orphaned rows: DELETE FROM xp_events WHERE user_id NOT IN
-- (SELECT id FROM users).
-- ============================================================
CREATE TABLE xp_events (
    id              TEXT NOT NULL DEFAULT 'xp_evt_' || encode(gen_random_bytes(8), 'hex'),
    user_id         TEXT NOT NULL,
    type            TEXT NOT NULL,
    points          INTEGER NOT NULL,
    source          TEXT NOT NULL,
    reference_id    TEXT DEFAULT NULL,
    occurred_at     TIMESTAMPTZ NOT NULL,
    metadata        JSONB DEFAULT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT xp_points_positive CHECK (points > 0 AND points <= 500),
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Create monthly partitions
CREATE TABLE xp_events_2026_01 PARTITION OF xp_events FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE xp_events_2026_02 PARTITION OF xp_events FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE xp_events_2026_03 PARTITION OF xp_events FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE xp_events_2026_04 PARTITION OF xp_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
-- ... continue for future months (auto-created by background job)

CREATE INDEX idx_xp_events_user_date ON xp_events(user_id, occurred_at DESC);
CREATE INDEX idx_xp_events_user_type ON xp_events(user_id, type);
CREATE UNIQUE INDEX idx_xp_events_dedup ON xp_events(user_id, type, reference_id) WHERE reference_id IS NOT NULL;

-- ============================================================
-- Exercise Library
-- ============================================================
CREATE TABLE exercises (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    muscle_group    TEXT NOT NULL,
    secondary_muscles TEXT[] DEFAULT '{}',
    equipment       TEXT,
    instructions    TEXT,
    is_custom       BOOLEAN NOT NULL DEFAULT FALSE,
    created_by      TEXT REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_exercises_muscle_group ON exercises(muscle_group);
CREATE INDEX idx_exercises_name_search ON exercises USING gin(to_tsvector('english', name));
CREATE INDEX idx_exercises_created_by ON exercises(created_by) WHERE created_by IS NOT NULL;

-- ============================================================
-- Workout Plans
-- ============================================================
CREATE TABLE workout_plans (
    id          TEXT PRIMARY KEY DEFAULT 'plan_' || encode(gen_random_bytes(8), 'hex'),
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT,
    days        JSONB NOT NULL DEFAULT '[]',
    active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_workout_plans_user ON workout_plans(user_id) WHERE active = TRUE;

-- ============================================================
-- Friendships, Friend Requests, Challenges, etc. (same structure as original)
-- ============================================================
CREATE TABLE friendships (
    id TEXT PRIMARY KEY DEFAULT 'fr_' || encode(gen_random_bytes(8), 'hex'),
    user_a_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT friendship_order CHECK (user_a_id < user_b_id),
    CONSTRAINT uq_friendship UNIQUE (user_a_id, user_b_id)
);
CREATE INDEX idx_friendships_user_a ON friendships(user_a_id);
CREATE INDEX idx_friendships_user_b ON friendships(user_b_id);

CREATE TABLE friend_requests (
    id TEXT PRIMARY KEY DEFAULT 'freq_' || encode(gen_random_bytes(8), 'hex'),
    from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT no_self_request CHECK (from_user_id != to_user_id),
    CONSTRAINT valid_status CHECK (status IN ('pending', 'accepted', 'declined'))
);
CREATE INDEX idx_friend_requests_to_user ON friend_requests(to_user_id, status);
CREATE INDEX idx_friend_requests_from_user ON friend_requests(from_user_id, status);
CREATE UNIQUE INDEX idx_friend_requests_pending ON friend_requests(from_user_id, to_user_id) WHERE status = 'pending';

CREATE TABLE challenges (
    id TEXT PRIMARY KEY DEFAULT 'ch_' || encode(gen_random_bytes(8), 'hex'),
    title TEXT NOT NULL,
    description TEXT DEFAULT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'upcoming',
    created_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    max_participants INTEGER NOT NULL DEFAULT 10,
    visibility TEXT NOT NULL DEFAULT 'friends_only',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT valid_challenge_type CHECK (type IN ('xp_total', 'workout_count', 'workout_strain', 'sleep_score', 'study_minutes', 'streak_maintain', 'nutrition_adherence')),
    CONSTRAINT valid_status CHECK (status IN ('upcoming', 'active', 'completed')),
    CONSTRAINT valid_dates CHECK (ends_at > starts_at)
);
CREATE INDEX idx_challenges_status ON challenges(status);
CREATE INDEX idx_challenges_ends_at ON challenges(ends_at) WHERE status = 'active';

CREATE TABLE challenge_participants (
    id TEXT PRIMARY KEY DEFAULT 'cp_' || encode(gen_random_bytes(8), 'hex'),
    challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    score REAL NOT NULL DEFAULT 0,
    rank INTEGER NOT NULL DEFAULT 0,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uq_challenge_participant UNIQUE (challenge_id, user_id)
);
CREATE INDEX idx_challenge_participants_challenge ON challenge_participants(challenge_id, score DESC);

CREATE TABLE challenge_daily_scores (
    id TEXT PRIMARY KEY DEFAULT 'cds_' || encode(gen_random_bytes(8), 'hex'),
    challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    score REAL NOT NULL DEFAULT 0,
    CONSTRAINT uq_challenge_daily UNIQUE (challenge_id, user_id, date)
);

-- ============================================================
-- Achievements
-- ============================================================
CREATE TABLE achievement_definitions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    icon TEXT NOT NULL,
    tier TEXT NOT NULL,
    xp_reward INTEGER NOT NULL,
    category TEXT NOT NULL,
    criteria_json JSONB NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT valid_tier CHECK (tier IN ('bronze', 'silver', 'gold', 'diamond')),
    CONSTRAINT valid_category CHECK (category IN ('fitness', 'sleep', 'nutrition', 'study', 'social', 'streak', 'milestone'))
);

CREATE TABLE user_achievements (
    id TEXT PRIMARY KEY DEFAULT 'uach_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    achievement_id TEXT NOT NULL REFERENCES achievement_definitions(id),
    xp_awarded INTEGER NOT NULL,
    earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_achievement UNIQUE (user_id, achievement_id)
);
CREATE INDEX idx_user_achievements_user ON user_achievements(user_id, earned_at DESC);

-- ============================================================
-- Daily Snapshots (partitioned quarterly)
-- NOTE: Same FK limitation as xp_events. user_id integrity
-- enforced at application layer + nightly orphan cleanup.
-- ============================================================
CREATE TABLE daily_snapshots (
    id TEXT NOT NULL DEFAULT 'snap_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL,
    date DATE NOT NULL,
    timezone TEXT NOT NULL,
    recovery JSONB DEFAULT NULL,
    sleep JSONB DEFAULT NULL,
    strain JSONB DEFAULT NULL,
    nutrition JSONB DEFAULT NULL,
    study JSONB DEFAULT NULL,
    accountability JSONB DEFAULT NULL,
    xp_earned INTEGER DEFAULT 0,
    streak_day INTEGER DEFAULT 0,
    device_info JSONB DEFAULT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, date)
) PARTITION BY RANGE (date);

CREATE TABLE daily_snapshots_2026_q1 PARTITION OF daily_snapshots FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
CREATE TABLE daily_snapshots_2026_q2 PARTITION OF daily_snapshots FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');
-- ... quarterly partitions

CREATE UNIQUE INDEX idx_snapshots_user_date ON daily_snapshots(user_id, date);

-- ============================================================
-- Manual Workouts, Study Sessions
-- ============================================================
CREATE TABLE manual_workouts (
    id TEXT PRIMARY KEY DEFAULT 'mwkt_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id TEXT NOT NULL,
    type TEXT NOT NULL,
    name TEXT DEFAULT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL,
    notes TEXT DEFAULT NULL,
    exercises JSONB DEFAULT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_manual_workout_client UNIQUE (user_id, client_id),
    CONSTRAINT valid_workout_type CHECK (type IN ('strength_training', 'cardio', 'flexibility', 'sport', 'other')),
    CONSTRAINT valid_duration CHECK (duration_minutes BETWEEN 1 AND 600)
);
CREATE INDEX idx_manual_workouts_user_date ON manual_workouts(user_id, started_at DESC);

CREATE TABLE study_sessions (
    id TEXT PRIMARY KEY DEFAULT 'study_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id TEXT NOT NULL,
    subject TEXT DEFAULT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL,
    technique TEXT DEFAULT NULL,
    focus_rating INTEGER DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_study_session_client UNIQUE (user_id, client_id),
    CONSTRAINT valid_technique CHECK (technique IS NULL OR technique IN ('pomodoro', 'deep_work', 'review', 'other')),
    CONSTRAINT valid_focus CHECK (focus_rating IS NULL OR (focus_rating BETWEEN 1 AND 5)),
    CONSTRAINT valid_duration CHECK (duration_minutes BETWEEN 1 AND 480)
);
CREATE INDEX idx_study_sessions_user_date ON study_sessions(user_id, started_at DESC);

-- ============================================================
-- Device Tokens, Insights, Sync Jobs
-- ============================================================
CREATE TABLE device_tokens (
    id TEXT PRIMARY KEY DEFAULT 'dev_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios',
    app_version TEXT NOT NULL,
    os_version TEXT DEFAULT NULL,
    environment TEXT NOT NULL DEFAULT 'production',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_device_token UNIQUE (user_id, device_id),
    CONSTRAINT valid_environment CHECK (environment IN ('production', 'sandbox'))
);
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
CREATE UNIQUE INDEX idx_device_tokens_token ON device_tokens(token);

CREATE TABLE insights (
    id TEXT PRIMARY KEY DEFAULT 'ins_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    content JSONB NOT NULL,
    question TEXT DEFAULT NULL,
    week_start DATE DEFAULT NULL,
    week_end DATE DEFAULT NULL,
    model TEXT NOT NULL,
    input_tokens INTEGER DEFAULT NULL,
    output_tokens INTEGER DEFAULT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT valid_insight_type CHECK (type IN ('weekly', 'pattern'))
);
CREATE INDEX idx_insights_user ON insights(user_id, generated_at DESC);
CREATE UNIQUE INDEX idx_insights_weekly_dedup ON insights(user_id, week_start) WHERE type = 'weekly';

CREATE TABLE sync_jobs (
    id TEXT PRIMARY KEY DEFAULT 'sync_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued',
    days_back INTEGER DEFAULT NULL,
    started_at TIMESTAMPTZ DEFAULT NULL,
    completed_at TIMESTAMPTZ DEFAULT NULL,
    error_message TEXT DEFAULT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_sync_jobs_user ON sync_jobs(user_id, created_at DESC);
CREATE INDEX idx_sync_jobs_status ON sync_jobs(status) WHERE status IN ('queued', 'running');

-- ============================================================
-- Reports
-- ============================================================
CREATE TABLE reports (
    id          TEXT PRIMARY KEY DEFAULT 'rpt_' || encode(gen_random_bytes(8), 'hex'),
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'generating',
    format      TEXT NOT NULL DEFAULT 'json',
    month       TEXT DEFAULT NULL,
    start_date  DATE DEFAULT NULL,
    end_date    DATE DEFAULT NULL,
    download_url TEXT DEFAULT NULL,
    expires_at  TIMESTAMPTZ DEFAULT NULL,
    size_bytes  INTEGER DEFAULT NULL,
    started_at  TIMESTAMPTZ DEFAULT NULL,
    completed_at TIMESTAMPTZ DEFAULT NULL,
    error_message TEXT DEFAULT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT valid_report_type CHECK (type IN ('monthly_summary', 'training_log', 'nutrition_log', 'full_export')),
    CONSTRAINT valid_report_status CHECK (status IN ('generating', 'ready', 'failed', 'expired')),
    CONSTRAINT valid_report_format CHECK (format IN ('json', 'csv'))
);
CREATE INDEX idx_reports_user ON reports(user_id, created_at DESC);
CREATE INDEX idx_reports_status ON reports(status) WHERE status = 'generating';

-- ============================================================
-- GDPR Exports
-- ============================================================
CREATE TABLE exports (
    id          TEXT PRIMARY KEY DEFAULT 'exp_' || encode(gen_random_bytes(8), 'hex'),
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      TEXT NOT NULL DEFAULT 'generating',
    format      TEXT NOT NULL DEFAULT 'json',
    download_url TEXT DEFAULT NULL,
    expires_at  TIMESTAMPTZ DEFAULT NULL,
    size_bytes  INTEGER DEFAULT NULL,
    started_at  TIMESTAMPTZ DEFAULT NULL,
    completed_at TIMESTAMPTZ DEFAULT NULL,
    error_message TEXT DEFAULT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT valid_export_status CHECK (status IN ('generating', 'ready', 'failed', 'expired'))
);
CREATE INDEX idx_exports_user ON exports(user_id, created_at DESC);

-- ============================================================
-- Audit Log (for sensitive operations)
-- ============================================================
CREATE TABLE audit_log (
    id          BIGSERIAL PRIMARY KEY,
    user_id     TEXT,
    actor_id    TEXT,
    action      TEXT NOT NULL,
    resource    TEXT NOT NULL,
    resource_id TEXT,
    details     JSONB DEFAULT NULL,
    ip_address  INET,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_log_user ON audit_log(user_id, created_at DESC);
CREATE INDEX idx_audit_log_action ON audit_log(action, created_at DESC);
CREATE INDEX idx_audit_log_created ON audit_log(created_at DESC);

-- ============================================================
-- Outbound Webhooks
-- ============================================================
CREATE TABLE outbound_webhooks (
    id      TEXT PRIMARY KEY DEFAULT 'whk_' || encode(gen_random_bytes(8), 'hex'),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    url     TEXT NOT NULL,
    events  TEXT[] NOT NULL,
    secret_enc TEXT NOT NULL,
    active  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE outbound_webhook_deliveries (
    id          BIGSERIAL PRIMARY KEY,
    webhook_id  TEXT NOT NULL REFERENCES outbound_webhooks(id) ON DELETE CASCADE,
    event_type  TEXT NOT NULL,
    payload     JSONB NOT NULL,
    status      TEXT NOT NULL DEFAULT 'pending',
    attempts    INTEGER NOT NULL DEFAULT 0,
    last_attempt_at TIMESTAMPTZ,
    next_retry_at TIMESTAMPTZ,
    response_status INTEGER,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_webhook_deliveries_retry ON outbound_webhook_deliveries(next_retry_at) WHERE status = 'pending';

-- ============================================================
-- Materialized Views for Leaderboards
-- ============================================================
CREATE MATERIALIZED VIEW mv_leaderboard_weekly AS
SELECT user_id, date_trunc('week', occurred_at)::DATE AS week_start,
    SUM(points) AS xp_total,
    RANK() OVER (PARTITION BY date_trunc('week', occurred_at) ORDER BY SUM(points) DESC) AS rank
FROM xp_events WHERE occurred_at >= date_trunc('week', NOW())
GROUP BY user_id, date_trunc('week', occurred_at);
CREATE UNIQUE INDEX idx_mv_leaderboard_weekly ON mv_leaderboard_weekly(week_start, user_id);

CREATE MATERIALIZED VIEW mv_leaderboard_monthly AS
SELECT user_id, date_trunc('month', occurred_at)::DATE AS month_start,
    SUM(points) AS xp_total,
    RANK() OVER (PARTITION BY date_trunc('month', occurred_at) ORDER BY SUM(points) DESC) AS rank
FROM xp_events WHERE occurred_at >= date_trunc('month', NOW())
GROUP BY user_id, date_trunc('month', occurred_at);
CREATE UNIQUE INDEX idx_mv_leaderboard_monthly ON mv_leaderboard_monthly(month_start, user_id);

CREATE MATERIALIZED VIEW mv_leaderboard_alltime AS
SELECT user_id, SUM(points) AS xp_total,
    RANK() OVER (ORDER BY SUM(points) DESC) AS rank
FROM xp_events GROUP BY user_id;
CREATE UNIQUE INDEX idx_mv_leaderboard_alltime ON mv_leaderboard_alltime(user_id);

-- ============================================================
-- Triggers
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_snapshots_updated_at BEFORE UPDATE ON daily_snapshots FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_device_tokens_updated_at BEFORE UPDATE ON device_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_preferences_updated_at BEFORE UPDATE ON user_preferences FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tr_workout_plans_updated_at BEFORE UPDATE ON workout_plans FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 21.2 Data Retention Policy

| Table | Retention | Strategy |
|-------|-----------|----------|
| `users` | Indefinite (soft-delete) | Soft-delete at `deleted_at`. Hard-delete 30 days later. |
| `refresh_tokens` | 30 days past expiry | Nightly cleanup job |
| `whoop_*` data | 2 years | Archive to cold storage (S3 Parquet) after 2 years |
| `xp_events` | 2 years | Partitioned by month. Drop partitions > 2 years. |
| `daily_snapshots` | 2 years | Partitioned quarterly. Archive older. |
| `audit_log` | 1 year | Partitioned. Archived to S3. |
| `sync_jobs` | 90 days | Nightly cleanup |
| `insights` | Indefinite | User-owned content |
| `outbound_webhook_deliveries` | 30 days | Nightly cleanup |

### 21.3 Soft Delete vs Hard Delete

| Table | Strategy | Reason |
|-------|----------|--------|
| `users` | Soft (30-day grace) | Account recovery |
| `whoop_recovery/sleep/workouts` | Soft | Whoop may re-send |
| `friendships` | Hard | No recovery needed |
| `friend_requests` | Hard (after 90 days if declined) | Cleanup |
| `challenges` | Soft (keep completed) | Historical record |
| `xp_events` | Hard (partitioned) | Volume management |

### 21.4 Entity-Relationship Summary

```
users
├── user_preferences (1:1)
├── refresh_tokens (1:N)
├── apple_auth (1:1)
├── whoop_integrations (1:1)
│   ├── whoop_recovery (1:N)
│   ├── whoop_sleep (1:N)
│   ├── whoop_workouts (1:N)
│   ├── whoop_cycles (1:N)
│   ├── whoop_body (1:1)
│   └── whoop_profiles (1:1)
├── nutritrack_integrations (1:1)
├── xp_events (1:N, partitioned)
├── exercises (1:N, custom)
├── workout_plans (1:N)
├── friendships (N:M)
├── friend_requests (1:N)
├── challenges (1:N as creator)
│   └── challenge_participants (N:M)
├── user_achievements (1:N)
├── daily_snapshots (1:N, partitioned)
├── manual_workouts (1:N)
├── study_sessions (1:N)
├── device_tokens (1:N)
├── insights (1:N)
├── sync_jobs (1:N)
├── reports (1:N)
├── exports (1:N)
├── outbound_webhooks (1:N)
└── audit_log (1:N)
```

---

## 22. Caching Strategy

### 22.1 Cache Layers

| Layer | Technology | Purpose |
|-------|-----------|---------|
| L1: HTTP | `Cache-Control`, `ETag` headers | Client-side caching |
| L2: CDN | CloudFront | Static assets (avatars, exercise images) |
| L3: Application | Redis 7 | Server-side response caching |
| L4: Database | PostgreSQL materialized views | Pre-computed leaderboards |

### 22.2 Per-Endpoint Cache Rules

| Endpoint | Redis TTL | Cache-Control | ETag | CDN | Invalidation |
|----------|-----------|---------------|------|-----|-------------|
| `GET /v1/users/me` | 60s | `private, max-age=60` | Yes | No | On PATCH |
| `GET /v1/users/:id` | 60s | `private, max-age=60` | Yes | No | On target PATCH |
| `GET /v1/users/me/preferences` | 300s | `private, max-age=300` | No | No | On PUT/PATCH |
| `GET /v1/whoop/recovery` | 120s | `private, max-age=120` | No | No | On Whoop webhook |
| `GET /v1/whoop/sleep` | 120s | `private, max-age=120` | No | No | On Whoop webhook |
| `GET /v1/whoop/workouts` | 120s | `private, max-age=120` | No | No | On Whoop webhook |
| `GET /v1/nutritrack/*` | 120-600s | `private, max-age=120` | No | No | Auto-expire |
| `GET /v1/xp/today` | 30s | `private, max-age=30` | No | No | On XP event |
| `GET /v1/xp/level` | 300s | `private, max-age=300` | Yes | No | On XP event |
| `GET /v1/leaderboards/*` | 300s | `private, max-age=300` | No | No | On MV refresh |
| `GET /v1/exercises` | 3600s | `public, max-age=3600` | Yes | Yes | On exercise create |
| `GET /v1/achievements/available` | 3600s | `public, max-age=3600` | Yes | Yes | On new achievement def |
| `GET /v1/config` | 60s | `public, max-age=300` | Yes | Yes | On config change |
| `GET /v1/.well-known/jwks.json` | 86400s | `public, max-age=86400` | No | Yes | On key rotation |

### 22.3 Cache Invalidation

Redis cache invalidation happens via explicit key deletion on write operations. Key format: `cache:{entity}:{user_id}:{params_hash}`.

For shared caches (exercises, achievements, config), a version counter is stored in Redis. The cache key includes the version: `cache:exercises:v{N}:{params}`. Incrementing the version effectively invalidates all entries.

---

## 23. Error Codes

### 23.1 Authentication Errors (1xxx)

| Code | HTTP | Message |
|------|------|---------|
| 1001 | 401 | Access token invalid or expired |
| 1002 | 400 | Invalid identity token |
| 1003 | 400 | Nonce mismatch |
| 1004 | 400 | Authorization code invalid |
| 1005 | 401 | Identity token verification failed |
| 1006 | 401 | Identity token expired |
| 1007 | 409 | Account in recovery window |
| 1008 | 400 | Missing or malformed refresh token |
| 1009 | 401 | Refresh token expired |
| 1010 | 401 | Refresh token revoked or not found |
| 1011 | 401 | Refresh token replay detected |
| 1012 | 401 | Device ID mismatch |
| 1013 | 404 | No deleted account found |
| 1014 | 410 | Recovery window expired |
| 1015 | 403 | Admin scope required |

### 23.2 Validation Errors (2xxx)

| Code | HTTP | Message |
|------|------|---------|
| 2001 | 400 | Validation failed |
| 2002 | 409 | Username already taken |
| 2003 | 400 | File too large |
| 2004 | 400 | Invalid file format |
| 2005 | 400 | Image too small |
| 2006 | 404 | User not found |
| 2007 | 400 | Invalid confirmation |
| 2008 | 400 | Date in the future |
| 2009 | 400 | Date too far in the past |
| 2010 | 404 | Device token not found |
| 2011 | 404 | No pending upload |

### 23.3 Integration Errors (3xxx)

| Code | HTTP | Message |
|------|------|---------|
| 3001 | 409 | Whoop already connected |
| 3002 | 400 | Invalid OAuth state |
| 3003 | 502 | Whoop token exchange failed |
| 3004 | 400 | Whoop authorization denied |
| 3005 | 404 | Whoop not connected |
| 3006 | 409 | Sync already in progress |
| 3007 | 502 | Whoop API unreachable |
| 3008 | 404 | No data for date |
| 3009 | 400 | Missing webhook signature |
| 3010 | 401 | Invalid webhook signature |
| 3011 | 401 | Webhook timestamp expired |
| 3012 | 404 | Unknown Whoop user |
| 3013 | 400 | NutriTrack auth failed |
| 3014 | 502 | NutriTrack unreachable |
| 3015 | 504 | NutriTrack timeout |
| 3016 | 404 | NutriTrack not connected |

### 23.4 Social / Arena Errors (4xxx)

| Code | HTTP | Message |
|------|------|---------|
| 4001 | 400 | Invalid XP event type |
| 4002 | 400 | XP points out of range |
| 4003 | 400 | Missing target user |
| 4004 | 400 | Cannot befriend yourself |
| 4005 | 409 | Already friends |
| 4006 | 409 | Request already pending |
| 4007 | 403 | Not the recipient |
| 4008 | 404 | Friend request not found |
| 4009 | 409 | Request already resolved |
| 4010 | 403 | Not friends |
| 4011 | 404 | Friendship not found |
| 4012 | 400 | Invalid challenge type |
| 4013 | 400 | Start date must be future |
| 4014 | 400 | Invite target not a friend |
| 4015 | 429 | Too many active challenges |
| 4016 | 403 | Challenge access denied |
| 4017 | 404 | Challenge not found |
| 4018 | 409 | Already participating |
| 4019 | 409 | Challenge full |
| 4020 | 409 | Challenge ended |
| 4021 | 409 | Not a participant |
| 4022 | 409 | Duplicate XP event (reference_id already used) |

### 23.5 Server Errors (5xxx)

| Code | HTTP | Message |
|------|------|---------|
| 5000 | 500 | Internal server error |
| 5001 | 429 | Rate limit exceeded |
| 5002 | 400 | Insufficient data |
| 5003 | 429 | AI insight limit reached |
| 5004 | 503 | AI service unavailable |
| 5005 | 503 | Service maintenance |
| 5006 | 413 | Payload too large |
| 5007 | 415 | Unsupported media type |

---

## 24. Security

### 24.1 Transport Security

- **TLS 1.3** required. TLS 1.2 accepted as fallback.
- **HSTS:** `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`
- **Certificate pinning** recommended in iOS app.

### 24.2 Security Headers (All Responses)

```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'none'
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

### 24.3 Data Encryption at Rest

| Data | Encryption | Key Management |
|------|-----------|----------------|
| PostgreSQL database | AWS RDS AES-256 | AWS KMS |
| Whoop tokens | AES-256-GCM (app-level) | `ENCRYPTION_KEY` env var, rotated quarterly |
| NutriTrack PIN | AES-256-GCM (app-level) | Same `ENCRYPTION_KEY` |
| Apple refresh token | AES-256-GCM (app-level) | Same `ENCRYPTION_KEY` |
| Redis cache | TLS in-transit | Ephemeral data |
| S3 avatars | SSE-S3 (AES-256) | AWS managed |

### 24.4 Authorization Boundary (IDOR Prevention)

Every endpoint that accesses a user-scoped resource MUST enforce object-level authorization. This is NOT optional -- it is the most common API vulnerability.

**Rules:**

| Resource Type | Authorization Check |
|--------------|-------------------|
| Own profile/prefs (`/users/me/*`) | `resource.user_id == req.auth.userId` |
| Other user profile (`/users/:id`) | Allowed (public data only). Private fields filtered by `privacy` prefs. |
| Whoop/NutriTrack data | `resource.user_id == req.auth.userId`. No user can see another's health data. |
| Workouts, study sessions | `resource.user_id == req.auth.userId` |
| Snapshots | `resource.user_id == req.auth.userId` |
| XP events/history | `resource.user_id == req.auth.userId` |
| Friend stats (`/friends/:id/stats`) | Must verify friendship exists between authenticated user and target |
| Challenges (`/challenges/:id`) | Must be participant, creator, or challenge is visible to user |
| Reports (`/reports/:id`) | `resource.user_id == req.auth.userId` |
| Exports (`/exports/:id`) | `resource.user_id == req.auth.userId` |
| Insights (`/insights/*`) | `resource.user_id == req.auth.userId` |
| Outbound webhooks | `scopes.contains("admin")` |
| Admin endpoints | `scopes.contains("admin")` |

**Implementation pattern:** Every Fluent query for user-scoped data MUST include `.filter(\.$userId == req.auth.userId)` as a WHERE clause. Never fetch-then-check -- always filter in the query.

**On authorization failure:** Return `404 Not Found` (not `403 Forbidden`) for user-scoped resources. This avoids leaking whether a resource exists. Use `403` only for scope-based checks (admin endpoints).

### 24.5 OWASP Top 10 Mitigations

| Threat | Mitigation |
|--------|-----------|
| A01: Broken Access Control | JWT auth middleware on all protected routes. Scoped permissions. Object-level authorization checks (see 24.4). |
| A02: Cryptographic Failures | AES-256-GCM for secrets at rest. ES256 for JWTs. TLS 1.3. No sensitive data in logs. |
| A03: Injection | Fluent ORM parameterized queries. No raw SQL. Input validation on all fields. |
| A04: Insecure Design | Rate limiting. Idempotency keys. Refresh token rotation with replay detection. |
| A05: Security Misconfiguration | Security headers. No debug info in production errors. Environment-specific config. |
| A06: Vulnerable Components | `swift package audit`. Dependabot alerts. Monthly dependency updates. |
| A07: Auth Failures | Brute force protection (10 req/min on auth). Token rotation. Device binding. |
| A08: Data Integrity Failures | HMAC webhook verification. JWT signature verification. Idempotency keys. |
| A09: Logging Failures | Structured JSON logging. Audit log for sensitive ops. Request ID tracing. |
| A10: SSRF | NutriTrack URL validation (HTTPS only in prod, private IP ranges blocked). |

### 24.6 Brute Force Protection

Auth endpoints (`/auth/*`) enforce:
- 10 requests per minute per IP.
- After 5 failed attempts from an IP in 10 minutes: 15-minute lockout.
- After 10 failed attempts: 1-hour lockout.
- Lockout headers: `Retry-After: <seconds>`.

### 24.7 Token Security

- Refresh tokens stored as SHA-256 hashes.
- Access tokens: 15-min TTL.
- Refresh token rotation: each use invalidates old token.
- Replay detection triggers full session revocation.

### 24.8 Input Validation

| Rule | Implementation |
|------|---------------|
| String fields | Strip whitespace, reject control characters |
| JSON body size | Max 1MB |
| URL fields | HTTPS required in production, private IPs blocked |
| Date fields | Valid ISO 8601, range 2020-2100 |
| Integer fields | Within documented bounds |
| Enum fields | Exact match (case-sensitive) |
| Array fields | Max documented length |
| JSONB/metadata | Max 10KB |
| SQL injection | Parameterized queries (Fluent ORM) |
| XSS | JSON output only, display names sanitized of HTML |

### 24.9 CORS Policy

No CORS headers (native iOS only). If web dashboard is added, configure per-origin.

### 24.10 Key Rotation Schedule

| Key | Frequency | Process |
|-----|-----------|---------|
| JWT signing (ES256) | 90 days | New pair, publish to JWKS, old key kept 15 min |
| `ENCRYPTION_KEY` | Quarterly | Re-encryption migration |
| Whoop client secret | Per Whoop policy | Update env var, restart |
| APNs key | Annual | Update key file |
| Claude API key | On compromise | Rotate in Anthropic dashboard |

---

## 25. Rate Limiting

### 25.1 Per-Endpoint Limits

| Endpoint | Limit | Window | Scope | Burst |
|----------|-------|--------|-------|-------|
| `POST /auth/*` | 10 | 1 min | Per IP | 3/sec |
| `GET /users/search` | 30 | 1 min | Per user | 5/sec |
| `POST /xp/events` | 60 | 1 min | Per user | 10/sec |
| `POST /insights/*` | 3-5 | 24 hours | Per user | 1/sec |
| `POST /reports` | 3 | 24 hours | Per user | 1/sec |
| `POST /integrations/whoop/sync` | 3 | 1 hour | Per user | 1/sec |
| `POST /webhooks/*` | 1000 | 1 min | Per IP | 50/sec |
| `POST /users/me/avatar*` | 5 | 1 min | Per user | 1/sec |
| `DELETE /users/me` | 3 | 1 hour | Per user | 1/sec |
| `POST /sync/batch` | 10 | 1 min | Per user | 2/sec |
| `POST /exports/gdpr` | 1 | 24 hours | Per user | 1/sec |
| All other GET | 100 | 1 min | Per user | 20/sec |
| All other POST/PATCH | 30 | 1 min | Per user | 5/sec |

### 25.2 Implementation

Redis sliding window algorithm. Key: `ratelimit:{scope}:{identifier}:{endpoint_pattern}`.

**Response headers on every request:**

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 97
X-RateLimit-Reset: 1711276800
```

**429 Response:**

```
Retry-After: 30
```

```json
{
  "ok": false,
  "error": {
    "code": 5001,
    "message": "Rate limit exceeded",
    "detail": "You have exceeded 100 requests per minute for this endpoint.",
    "retry_after_seconds": 30
  }
}
```

---

## 26. Background Jobs

### 26.1 Job Catalog

| Job | Trigger | Frequency | Timeout | Retries | Concurrency | Monitoring |
|-----|---------|-----------|---------|---------|-------------|-----------|
| Whoop full sync | Manual or first connect | On demand | 60s | 3 (exp backoff) | 1 per user | `sync_jobs` table |
| Whoop incremental sync | Webhook event | Real-time | 30s | 3 | 1 per user | `sync_jobs` table |
| Leaderboard refresh | Debounced after XP events | Max every 5 min | 30s | 1 | 1 global | Log + metric |
| Challenge status update | Cron | Every 1 min | 10s | 0 | 1 global | Log |
| Accountability check | Cron | Every 15 min | 30s | 0 | 1 global | Log |
| Push notification send | Various events | Real-time | 10s | 2 | 10 concurrent | Counter metric |
| Weekly summary generation | Cron Sunday 19:50 UTC | Weekly | 120s | 2 | 5 concurrent | `insights` table |
| Achievement check | After XP events | Real-time | 10s | 1 | 5 concurrent | Log |
| Account hard-delete | Cron daily 02:00 UTC | Daily | 300s | 0 | 1 global | Audit log |
| Stale token cleanup | Cron daily 03:00 UTC | Daily | 60s | 0 | 1 global | Log |
| Stale data cleanup | Cron daily 04:00 UTC | Daily | 300s | 0 | 1 global | Log |
| GDPR export generation | On request | On demand | 600s | 1 | 2 concurrent | `exports` table |
| Report generation | On request | On demand | 120s | 1 | 3 concurrent | `reports` table |
| Webhook delivery | On event | Real-time | 10s | 3 (1m/5m/30m) | 10 concurrent | Deliveries table |
| Partition creation | Cron monthly | Monthly | 30s | 0 | 1 global | Log |
| Analytics aggregation | Cron daily 05:00 UTC | Daily | 300s | 0 | 1 global | Log |

### 26.2 Job Execution

Jobs run in the same Vapor process using Swift concurrency (`Task`s and actors). For production scale, extract to a separate worker process using `--worker` flag.

---

## 27. Observability

### 27.1 Structured Logging

All logs are JSON:

```json
{
  "timestamp": "2026-03-24T20:00:00.123Z",
  "level": "info",
  "message": "Request completed",
  "request_id": "req_abc123",
  "user_id": "usr_abc123def456",
  "method": "GET",
  "path": "/v1/users/me",
  "status": 200,
  "duration_ms": 12,
  "ip": "203.0.113.1",
  "user_agent": "Tempo/1.0.0 iOS/19.4",
  "trace_id": "trace_abc123def456"
}
```

### 27.2 Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `http_request_duration_ms` | Histogram (p50/p95/p99) | method, path, status |
| `http_request_total` | Counter | method, path, status |
| `active_connections` | Gauge | -- |
| `db_query_duration_ms` | Histogram | query_type |
| `db_pool_active` | Gauge | -- |
| `db_pool_max` | Gauge | -- |
| `redis_operation_duration_ms` | Histogram | operation |
| `redis_memory_bytes` | Gauge | -- |
| `whoop_api_duration_ms` | Histogram | endpoint |
| `claude_api_duration_ms` | Histogram | -- |
| `claude_api_cost_cents` | Counter | -- |
| `push_notifications_sent` | Counter | type, status |
| `active_users_daily` | Gauge | -- |
| `sync_jobs_total` | Counter | type, status |
| `background_jobs_queued` | Gauge | type |
| `rate_limit_hits` | Counter | endpoint |

### 27.3 Health Checks

#### GET /v1/health

Full dependency check.

**Authentication:** None | **Rate limit:** None | **Cache:** None

**Response (200 OK):**

```json
{
  "ok": true,
  "data": {
    "status": "healthy",
    "version": "1.0.0",
    "uptime_seconds": 86400,
    "checks": {
      "database": { "status": "healthy", "latency_ms": 2, "pool_active": 12, "pool_max": 50 },
      "redis": { "status": "healthy", "latency_ms": 1, "memory_mb": 45, "keys": 12400 },
      "whoop_api": { "status": "healthy", "latency_ms": 120 },
      "claude_api": { "status": "healthy", "latency_ms": 200 }
    }
  },
  "meta": { "request_id": "req_health01", "timestamp": "2026-03-24T20:00:00Z" }
}
```

#### GET /v1/health/ready

Lightweight readiness probe. `200` = ready, `503` = not ready.

#### GET /v1/health/live

Liveness probe. `200` = process running. No dependency checks.

### 27.4 Distributed Tracing

Every request generates a `trace_id` (or adopts `X-Trace-Id` from the client). The trace ID propagates to:
- All database queries
- Redis operations
- Outbound HTTP calls (Whoop, NutriTrack, Claude, Apple)
- Background jobs spawned by the request
- Push notifications triggered

### 27.5 Alerting

| Alert | Condition | Severity |
|-------|-----------|----------|
| Error rate | >5% 5xx for 5 min | Critical |
| Latency | p99 > 2000ms for 5 min | Warning |
| DB pool | >80% utilization for 5 min | Warning |
| Claude budget | >80% monthly budget | Warning |
| Claude budget | >95% monthly budget | Critical |
| Disk space | <20% free | Warning |
| Whoop sync failures | >3 consecutive per user | Info (notify user) |
| Certificate expiry | <14 days | Warning |

---

## 28. Deployment

### 28.1 Multi-Stage Dockerfile

```dockerfile
# ============================================================
# Build stage
# ============================================================
FROM swift:5.10-jammy AS build

WORKDIR /app

# Resolve dependencies first (cache layer)
COPY Package.swift Package.resolved ./
RUN swift package resolve

# Copy source and build
COPY . .
RUN swift build -c release --static-swift-stdlib \
    -Xlinker -ljemalloc

# ============================================================
# Runtime stage
# ============================================================
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libcurl4 \
    libjemalloc2 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN useradd -r -s /bin/false tempo
USER tempo

WORKDIR /app
COPY --from=build --chown=tempo:tempo /app/.build/release/App ./
COPY --from=build --chown=tempo:tempo /app/Resources ./Resources

ENV ENVIRONMENT=production
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/v1/health/live || exit 1

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
```

### 28.2 Docker Compose (Development)

```yaml
version: "3.9"

services:
  api:
    build: .
    ports:
      - "8080:8080"
    environment:
      - ENVIRONMENT=development
      - DATABASE_URL=postgres://tempo:tempo_dev@db:5432/tempo_dev
      - REDIS_URL=redis://redis:6379/0
      - LOG_LEVEL=debug
      - JWT_SIGNING_KEY=dev-key-base64
      - ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - .:/app
    command: swift run App serve --hostname 0.0.0.0 --port 8080

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: tempo
      POSTGRES_PASSWORD: tempo_dev
      POSTGRES_DB: tempo_dev
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U tempo -d tempo_dev"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redisdata:/data

volumes:
  pgdata:
  redisdata:
```

### 28.3 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ENVIRONMENT` | Yes | -- | `development`, `staging`, `production` |
| `DATABASE_URL` | Yes | -- | PostgreSQL connection string |
| `DATABASE_POOL_SIZE` | No | `25` | Max DB connections |
| `REDIS_URL` | Yes | -- | Redis connection string |
| `LOG_LEVEL` | No | `info` | `trace`/`debug`/`info`/`notice`/`warning`/`error`/`critical` |
| `PORT` | No | `8080` | HTTP port |
| `JWT_SIGNING_KEY` | Yes | -- | Base64-encoded ES256 private key |
| `ENCRYPTION_KEY` | Yes | -- | 32-byte hex AES-256 key |
| `APPLE_BUNDLE_ID` | Yes | -- | e.g., `app.tempo.ios` |
| `APPLE_TEAM_ID` | Yes | -- | Apple Developer Team ID |
| `APPLE_KEY_ID` | Yes | -- | Sign in with Apple key ID |
| `APPLE_PRIVATE_KEY` | Yes | -- | PEM format |
| `WHOOP_CLIENT_ID` | Yes | -- | Whoop OAuth client ID |
| `WHOOP_CLIENT_SECRET` | Yes | -- | Whoop OAuth client secret |
| `WHOOP_REDIRECT_URI` | Yes | -- | OAuth redirect URI |
| `WHOOP_WEBHOOK_SECRET` | Yes | -- | HMAC secret |
| `APNS_KEY_ID` | Yes | -- | APNs key ID |
| `APNS_TEAM_ID` | Yes | -- | APNs team ID |
| `APNS_PRIVATE_KEY` | Yes | -- | P8 format |
| `APNS_TOPIC` | Yes | -- | Bundle ID |
| `APNS_ENVIRONMENT` | No | `production` | `production`/`sandbox` |
| `CLAUDE_API_KEY` | Yes | -- | Anthropic API key |
| `CLAUDE_MODEL` | No | `claude-sonnet-4-20250514` | Model ID |
| `CLAUDE_MAX_TOKENS` | No | `2000` | Max output tokens |
| `CLAUDE_MONTHLY_BUDGET_CENTS` | No | `5000` | $50 default |
| `S3_BUCKET` | Yes | -- | Avatar storage |
| `S3_REGION` | Yes | -- | AWS region |
| `CDN_BASE_URL` | Yes | -- | CloudFront URL |
| `RATE_LIMIT_ENABLED` | No | `true` | Toggle rate limiting |

### 28.4 Production Deployment (Railway/Fly.io)

**Railway:**
```toml
# railway.toml
[build]
builder = "dockerfile"

[deploy]
healthcheckPath = "/v1/health/live"
healthcheckTimeout = 5
startCommand = "./App serve --env production --hostname 0.0.0.0 --port $PORT"
numReplicas = 2
```

**Fly.io:**
```toml
# fly.toml
app = "tempo-api"
primary_region = "fra"

[build]
dockerfile = "Dockerfile"

[http_service]
internal_port = 8080
force_https = true
auto_stop_machines = false
auto_start_machines = true
min_machines_running = 2

[[services.http_checks]]
interval = "30s"
timeout = "5s"
path = "/v1/health/live"
```

### 28.5 Database Connection Pooling

```swift
// configure.swift
app.databases.use(.postgres(
    configuration: .init(
        hostname: env.DB_HOST,
        port: env.DB_PORT,
        username: env.DB_USER,
        password: env.DB_PASS,
        database: env.DB_NAME,
        tls: .require(try .init(configuration: .clientDefault))
    ),
    maxConnectionsPerEventLoop: 4,  // * 8 cores = 32 max connections
    connectionPoolTimeout: .seconds(10)
), as: .psql)
```

### 28.6 Database Backup Strategy

| Type | Frequency | Retention | Method |
|------|-----------|-----------|--------|
| Continuous WAL | Continuous | 7 days | AWS RDS automated |
| Daily snapshot | Daily 03:00 UTC | 30 days | RDS automated |
| Weekly full export | Sunday 04:00 UTC | 90 days | `pg_dump` to S3 |
| Pre-migration | Before each migration | 7 days | Manual RDS snapshot |

### 28.7 CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: tempo_test
        ports: ["5432:5432"]
      redis:
        image: redis:7-alpine
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
        with:
          swift-version: "5.10"
      - run: swift test --parallel
        env:
          DATABASE_URL: postgres://test:test@localhost:5432/tempo_test
          REDIS_URL: redis://localhost:6379/0

  deploy-staging:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to staging
        run: railway up --environment staging

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to production
        run: railway up --environment production
      - name: Run migrations
        run: railway run vapor run migrate --yes
      - name: Smoke test
        run: curl -f https://api.tempo.app/v1/health
```

---

## 29. Migration Strategy

### 29.1 Migration Naming

Numbered sequentially: `001_CreateUsers.swift`, `002_CreateRefreshTokens.swift`, etc.

Each migration implements:
- `prepare(on database:)` — forward migration
- `revert(on database:)` — rollback

### 29.2 Zero-Downtime Migrations

All schema changes follow the **expand-and-contract** pattern:

1. **Expand:** Add new columns as nullable or with defaults. Add new tables. Add new indexes concurrently.
2. **Deploy:** New code handles both old and new schema.
3. **Migrate data:** Backfill new columns if needed.
4. **Contract:** Remove old columns/tables in a later migration (after all code references removed).

**Never in a single migration:**
- Rename columns (add new, copy, drop old)
- Change column types (add new column, backfill, swap)
- Drop columns with active code references

### 29.3 Running Migrations

```bash
# Development: auto-run on startup
swift run App serve  # migrations run automatically

# Production: explicit
vapor run migrate         # apply pending
vapor run migrate --revert  # rollback last batch
vapor run migrate --revert-all  # rollback everything (dangerous)
```

### 29.4 Rollback Procedure

1. Take RDS snapshot before migration.
2. Run migration: `vapor run migrate --yes`.
3. If issues detected: `vapor run migrate --revert`.
4. If revert fails: restore from RDS snapshot (PITR).

---

## 30. API Versioning & Deprecation

### 30.1 Strategy

- URL-path versioning: `/v1/`, `/v2/`, etc.
- Major version only in URL. Minor/patch changes are backward-compatible.
- When `v2` launches, `v1` continues for minimum 12 months.

### 30.2 Deprecation Headers

Deprecated endpoints include:

```
Sunset: Sat, 01 Jan 2028 00:00:00 GMT
Deprecation: true
Link: <https://api.tempo.app/v2/users/me>; rel="successor-version"
```

### 30.3 Client Version Gating

The `X-Client-Version` header allows the server to:
- Gate features by app version
- Return deprecation warnings
- Force update (via `GET /v1/config`)

### 30.4 Breaking Change Policy

A "breaking change" is:
- Removing an endpoint
- Removing or renaming a response field
- Changing the type of a response field
- Adding a required request field
- Changing error code meanings

**Not breaking:**
- Adding new optional fields to responses
- Adding new endpoints
- Adding new optional request fields
- Adding new error codes

### 30.5 Changelog Format

```
## v1.3.0 (2026-04-01)
### Added
- POST /v1/workout-plans: Create custom workout plans
- GET /v1/exercises/:id/progression: Track exercise progression

### Changed
- GET /v1/leaderboards/:period: Added `daily_breakdown` field to response

### Deprecated
- GET /v1/sync/snapshots: Use GET /v1/snapshots instead. Sunset: 2026-10-01.
```

---

## 31. Load Testing & Capacity Planning

### 31.1 Expected QPS by Endpoint

| Endpoint | QPS at 100 users | QPS at 1,000 users | QPS at 10,000 users |
|----------|-------------------|---------------------|----------------------|
| `GET /v1/users/me` | 2 | 15 | 120 |
| `GET /v1/whoop/recovery` | 1 | 8 | 60 |
| `GET /v1/nutritrack/today` | 1 | 10 | 80 |
| `GET /v1/xp/today` | 2 | 15 | 100 |
| `GET /v1/leaderboards/*` | 1 | 5 | 40 |
| `POST /v1/snapshots` | 0.5 | 4 | 30 |
| `POST /v1/xp/events` | 1 | 8 | 60 |
| `POST /v1/webhooks/whoop` | 0.5 | 5 | 50 |
| `POST /v1/auth/*` | 0.1 | 1 | 5 |
| **Total** | **~10** | **~80** | **~600** |

### 31.2 Resource Sizing

| Resource | 100 users | 1,000 users | 10,000 users |
|----------|-----------|-------------|--------------|
| **Vapor instances** | 1 (1 vCPU, 512MB) | 2 (2 vCPU, 1GB each) | 4 (4 vCPU, 2GB each) |
| **PostgreSQL** | db.t4g.micro (2 vCPU, 1GB) | db.t4g.small (2 vCPU, 2GB) | db.r6g.large (2 vCPU, 16GB) |
| **DB connections** | 10 | 25 | 80 |
| **Redis** | 256MB | 512MB | 2GB |
| **Redis keys (est.)** | 5,000 | 40,000 | 300,000 |
| **S3 storage (avatars)** | 25MB | 250MB | 2.5GB |
| **DB storage** | 500MB | 5GB | 50GB |

### 31.3 Estimated Monthly Costs (AWS)

| Component | 100 users | 1,000 users | 10,000 users |
|-----------|-----------|-------------|--------------|
| Compute (Fargate/Railway) | $10 | $40 | $200 |
| PostgreSQL (RDS) | $15 | $30 | $150 |
| Redis (ElastiCache) | $15 | $25 | $50 |
| S3 + CloudFront | $1 | $5 | $20 |
| Claude API | $5 | $50 | $200 |
| APNs | $0 | $0 | $0 |
| **Total** | **~$46/mo** | **~$150/mo** | **~$620/mo** |

### 31.4 Performance Targets

| Metric | Target |
|--------|--------|
| p50 latency (GET) | < 50ms |
| p95 latency (GET) | < 200ms |
| p99 latency (GET) | < 500ms |
| p50 latency (POST) | < 100ms |
| p95 latency (POST) | < 500ms |
| p99 latency (POST) | < 1000ms |
| Error rate | < 0.1% |
| Uptime | 99.9% (8.7h downtime/year) |

---

## Appendix A: Complete Endpoint Index

| # | Method | Path | Auth | Rate Limit | Section |
|---|--------|------|------|------------|---------|
| 1 | POST | `/v1/auth/apple` | No | 10/min/IP | 2.1 |
| 2 | POST | `/v1/auth/refresh` | No | 10/min/IP | 2.2 |
| 3 | POST | `/v1/auth/logout` | Yes | 10/min | 2.4 |
| 4 | POST | `/v1/auth/rotate` | Yes | 3/hr | 2.5 |
| 5 | POST | `/v1/auth/recover` | No | 5/hr/IP | 3.9 |
| 6 | GET | `/v1/.well-known/jwks.json` | No | 100/min/IP | 2.6 |
| 7 | GET | `/v1/users/me` | Yes | 100/min | 3.1 |
| 8 | PATCH | `/v1/users/me` | Yes | 20/min | 3.2 |
| 9 | POST | `/v1/users/me/avatar/presign` | Yes | 5/min | 3.3 |
| 10 | POST | `/v1/users/me/avatar/confirm` | Yes | 5/min | 3.4 |
| 11 | POST | `/v1/users/me/avatar` | Yes | 5/min | 3.5 |
| 12 | GET | `/v1/users/:id` | Yes | 100/min | 3.6 |
| 13 | GET | `/v1/users/search` | Yes | 30/min | 3.7 |
| 14 | DELETE | `/v1/users/me` | Yes | 3/hr | 3.8 |
| 15 | GET | `/v1/users/me/preferences` | Yes | 100/min | 4.1 |
| 16 | PUT | `/v1/users/me/preferences` | Yes | 20/min | 4.2 |
| 17 | PATCH | `/v1/users/me/preferences` | Yes | 20/min | 4.3 |
| 18 | GET | `/v1/integrations/whoop/authorize` | Yes | 10/min | 5.1 |
| 19 | GET | `/v1/integrations/whoop/callback` | No | 10/min/IP | 5.2 |
| 20 | GET | `/v1/integrations/whoop/status` | Yes | 100/min | 5.3 |
| 21 | DELETE | `/v1/integrations/whoop` | Yes | 5/min | 5.4 |
| 22 | POST | `/v1/integrations/whoop/sync` | Yes | 3/hr | 5.5 |
| 23 | GET | `/v1/whoop/recovery` | Yes | 100/min | 5.6 |
| 24 | GET | `/v1/whoop/sleep` | Yes | 100/min | 5.7 |
| 25 | GET | `/v1/whoop/workouts` | Yes | 100/min | 5.8 |
| 26 | GET | `/v1/whoop/cycles` | Yes | 100/min | 5.9 |
| 27 | GET | `/v1/whoop/profile` | Yes | 100/min | 5.10 |
| 28 | GET | `/v1/whoop/body` | Yes | 100/min | 5.11 |
| 29 | POST | `/v1/webhooks/whoop` | HMAC | 1000/min/IP | 5.12 |
| 30 | POST | `/v1/integrations/nutritrack/connect` | Yes | 10/min | 6.1 |
| 31 | GET | `/v1/integrations/nutritrack/status` | Yes | 30/min | 6.2 |
| 32 | DELETE | `/v1/integrations/nutritrack` | Yes | 5/min | 6.3 |
| 33 | GET | `/v1/nutritrack/today` | Yes | 60/min | 6.4 |
| 34 | GET | `/v1/nutritrack/plan/:date` | Yes | 60/min | 6.5 |
| 35 | GET | `/v1/nutritrack/macros` | Yes | 60/min | 6.6 |
| 36 | GET | `/v1/nutritrack/week/:date` | Yes | 30/min | 6.7 |
| 37 | GET | `/v1/exercises` | Yes | 60/min | 7.1 |
| 38 | POST | `/v1/exercises` | Yes | 10/min | 7.2 |
| 39 | POST | `/v1/workouts` | Yes | 30/min | 7.3 |
| 40 | GET | `/v1/workouts` | Yes | 100/min | 7.4 |
| 41 | GET | `/v1/exercises/:id/progression` | Yes | 60/min | 7.5 |
| 42 | GET | `/v1/workout-plans` | Yes | 60/min | 7.6 |
| 43 | POST | `/v1/workout-plans` | Yes | 10/min | 7.7 |
| 44 | POST | `/v1/study-sessions` | Yes | 30/min | 8.1 |
| 45 | GET | `/v1/study-sessions` | Yes | 100/min | 8.2 |
| 46 | GET | `/v1/study-sessions/analytics` | Yes | 30/min | 8.3 |
| 47 | POST | `/v1/snapshots` | Yes | 30/min | 9.1 |
| 48 | GET | `/v1/snapshots` | Yes | 60/min | 9.2 |
| 49 | GET | `/v1/snapshots/aggregate` | Yes | 30/min | 9.3 |
| 50 | POST | `/v1/xp/events` | Yes | 60/min | 10.1 |
| 51 | GET | `/v1/xp/today` | Yes | 100/min | 10.2 |
| 52 | GET | `/v1/xp/history` | Yes | 100/min | 10.3 |
| 53 | GET | `/v1/xp/level` | Yes | 100/min | 10.4 |
| 54 | GET | `/v1/leaderboards/:period` | Yes | 60/min | 10.5 |
| 55 | POST | `/v1/friends/requests` | Yes | 20/min | 10.6 |
| 56 | GET | `/v1/friends/requests` | Yes | 60/min | 10.6 |
| 57 | POST | `/v1/friends/requests/:id/accept` | Yes | 20/min | 10.6 |
| 58 | POST | `/v1/friends/requests/:id/decline` | Yes | 20/min | 10.6 |
| 59 | GET | `/v1/friends` | Yes | 60/min | 10.6 |
| 60 | DELETE | `/v1/friends/:id` | Yes | 10/min | 10.6 |
| 61 | GET | `/v1/friends/:id/stats` | Yes | 60/min | 10.6 |
| 62 | POST | `/v1/challenges` | Yes | 10/min | 10.7 |
| 63 | GET | `/v1/challenges` | Yes | 60/min | 10.7 |
| 64 | GET | `/v1/challenges/:id` | Yes | 60/min | 10.7 |
| 65 | POST | `/v1/challenges/:id/join` | Yes | 10/min | 10.7 |
| 66 | POST | `/v1/challenges/:id/leave` | Yes | 10/min | 10.7 |
| 67 | GET | `/v1/challenges/history` | Yes | 60/min | 10.7 |
| 68 | POST | `/v1/achievements/check` | Yes | 10/min | 10.8 |
| 69 | GET | `/v1/achievements` | Yes | 60/min | 10.8 |
| 70 | GET | `/v1/achievements/available` | Yes | 30/min | 10.8 |
| 71 | GET | `/v1/accountability/config` | Yes | 100/min | 11.1 |
| 72 | PUT | `/v1/accountability/config` | Yes | 10/min | 11.2 |
| 73 | GET | `/v1/accountability/today` | Yes | 100/min | 11.3 |
| 74 | POST | `/v1/sync/batch` | Yes | 10/min | 12.1 |
| 75 | GET | `/v1/sync/status` | Yes | 100/min | 12.2 |
| 76 | POST | `/v1/devices` | Yes | 10/min | 13.1 |
| 77 | DELETE | `/v1/devices/:device_id` | Yes | 10/min | 13.2 |
| 78 | POST | `/v1/webhooks/outbound` | Yes (admin) | 5/min | 14.1 |
| 79 | GET | `/v1/webhooks/outbound` | Yes (admin) | 30/min | 14.3 |
| 80 | DELETE | `/v1/webhooks/outbound/:id` | Yes (admin) | 5/min | 14.4 |
| 81 | GET | `/v1/webhooks/outbound/:id/dlq` | Yes (admin) | 30/min | 14.5 |
| 82 | POST | `/v1/webhooks/outbound/:id/dlq/:event_id/retry` | Yes (admin) | 10/min | 14.6 |
| 83 | POST | `/v1/insights/weekly` | Yes | 3/day | 15.1 |
| 84 | POST | `/v1/insights/pattern` | Yes | 5/day | 15.2 |
| 85 | GET | `/v1/insights/history` | Yes | 60/min | 15.3 |
| 86 | POST | `/v1/reports` | Yes | 3/day | 16.1 |
| 87 | GET | `/v1/reports/:id` | Yes | 60/min | 16.2 |
| 88 | POST | `/v1/exports/gdpr` | Yes | 1/day | 16.3 |
| 89 | GET | `/v1/exports/:id` | Yes | 60/min | 16.4 |
| 90 | GET | `/v1/search/exercises` | Yes | 60/min | 17.1 |
| 91 | GET | `/v1/search/users` | Yes | 30/min | 17.2 |
| 92 | GET | `/v1/search/challenges` | Yes | 30/min | 17.3 |
| 93 | GET | `/v1/admin/users` | Yes (admin) | 30/min | 18.1 |
| 94 | GET | `/v1/admin/stats` | Yes (admin) | 30/min | 18.2 |
| 95 | POST | `/v1/admin/users/:id/suspend` | Yes (admin) | 10/min | 18.3 |
| 96 | GET | `/v1/admin/audit-log` | Yes (admin) | 30/min | 18.4 |
| 97 | GET | `/v1/config` | No | 100/min/IP | 19.1 |
| 98 | GET | `/v1/ws` | Yes (query) | -- | 20.1 |
| 99 | GET | `/v1/health` | No | None | 27.3 |
| 100 | GET | `/v1/health/ready` | No | None | 27.3 |
| 101 | GET | `/v1/health/live` | No | None | 27.3 |
| 102 | GET | `/v1/accountability/history` | Yes | 60/min | 11.4 |
| 103 | PATCH | `/v1/integrations/nutritrack/credentials` | Yes | 5/min | 11.5 |
| 104 | GET | `/v1/rate-limits` | Yes | 100/min | 11.6 |

**Total endpoints: 104**

---

## Appendix B: ID Prefixes

| Prefix | Entity |
|--------|--------|
| `usr_` | User |
| `rt_` | Refresh token |
| `rec_` | Whoop recovery |
| `slp_` | Whoop sleep |
| `wkt_` | Whoop workout |
| `cyc_` | Whoop cycle |
| `xp_evt_` | XP event |
| `fr_` | Friendship |
| `freq_` | Friend request |
| `ch_` | Challenge |
| `cp_` | Challenge participant |
| `cds_` | Challenge daily score |
| `ach_` | Achievement definition |
| `uach_` | User achievement |
| `snap_` | Daily snapshot |
| `mwkt_` | Manual workout |
| `study_` | Study session |
| `dev_` | Device token |
| `ins_` | Insight |
| `sync_` | Sync job |
| `plan_` | Workout plan |
| `ex_` | Exercise |
| `whk_` | Outbound webhook |
| `rpt_` | Report |
| `exp_` | Data export |
| `req_` | Request ID |
| `tok_` | JWT token ID |
| `idem_` | Idempotency key |
| `nn_` | Non-negotiable |

---

## Appendix C: Claude Prompt Template (Weekly)

```
You are an AI health and performance coach analyzing one week of data for a university student who tracks fitness (via Whoop), nutrition (via NutriTrack), study sessions, and daily habits.

Analyze the following data and provide:
1. A one-line title summarizing the week
2. A 2-3 sentence executive summary
3. Sections for each domain (Recovery & Sleep, Fitness, Nutrition, Academics)
4. 3 actionable recommendations
5. Week-over-week comparisons

Be specific with numbers. Reference actual dates. Be encouraging but honest.

USER CONTEXT:
- Timezone: {{timezone}}
- Streak: {{streak_days}} days
- Level: {{level}} ({{xp_total}} XP)

THIS WEEK ({{week_start}} to {{week_end}}):
RECOVERY: {{#each recovery_data}} - {{date}}: Score {{score}}%, HRV {{hrv}}ms, RHR {{rhr}}bpm {{/each}}
SLEEP: {{#each sleep_data}} - {{date}}: {{duration_hours}}h, Performance {{performance}}% {{/each}}
WORKOUTS: {{#each workout_data}} - {{date}}: {{sport_name}}, Strain {{strain}} {{/each}}
NUTRITION: {{#each nutrition_data}} - {{date}}: {{calories}}kcal, Protein {{protein}}g/{{target_protein}}g {{/each}}
STUDY: {{#each study_data}} - {{date}}: {{minutes}}min, Focus: {{focus_rating}}/5 {{/each}}

LAST WEEK (comparison):
- Recovery: {{prev_avg_recovery}}%, Sleep: {{prev_avg_sleep_hours}}h, Workouts: {{prev_workout_count}}, Protein adherence: {{prev_protein_adherence}}%

Respond in JSON: {"title","summary","sections":[{"title","icon","body","sentiment"}],"action_items":[],"compared_to_last_week":{}}
```

**Privacy:** No PII sent. Only aggregated metrics. No user ID, name, email, or Apple ID.
