#!/usr/bin/env python3
"""
Mint a Tempo access token for smoke-testing without going through iOS Sign in with Apple.
Per INTELLIGENCE_REMEDIATION_PLAN.md §5 verification.

Usage:
    JWT_SECRET=tempo-dev-only-change-me python3 mint_test_jwt.py <user_id>

The user_id must already exist in the `users` table (the JWT middleware doesn't
re-check user existence, but the SubscriptionMiddleware does on every AI route).

Output: a single JWT line you can paste into curl with:
    curl -H "Authorization: Bearer <token>" ...

Requires:
    pip3 install pyjwt
"""
import os
import sys
import time
import uuid

try:
    import jwt
except ImportError:
    print("Need pyjwt: pip3 install pyjwt", file=sys.stderr)
    sys.exit(1)

if len(sys.argv) != 2:
    print(__doc__)
    sys.exit(1)

user_id = sys.argv[1]
secret = os.environ.get("JWT_SECRET", "tempo-dev-only-change-me")
now = int(time.time())

# Must match TempoAccessToken in JWTService.swift
payload = {
    "sub": user_id,
    "iss": "tempo-api",
    "aud": ["app.tempo.ios"],
    "iat": now,
    "exp": now + 900,  # 15 min
    "jti": str(uuid.uuid4()),
    "device_id": "smoke-test-device",  # snake_case per CodingKeys
    "scopes": ["user"],
}

token = jwt.encode(payload, secret, algorithm="HS256")
print(token)
