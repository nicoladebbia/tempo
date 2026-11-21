import { defineRailway, preserve, project, service } from "railway/iac";

// Railway Infrastructure as Code for the Tempo backend.
// Replaces the old railway.toml (Railway's Config as Code ended 2026-12-01).
// This repo manages only the backend service; Postgres and Redis stay as they are.
// Preview a change with `railway config plan`, then apply it with `railway config apply`.
export const partial = "tempo-backend";

export default defineRailway(() => {
  const tempoBackend = service("tempo-backend", {
    // Build with our Dockerfile, not Railway's auto-detected builder.
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    // Secrets and settings live in Railway, never in git. preserve() keeps each
    // value exactly as Railway holds it. IMPORTANT: a variable missing from this
    // list is DELETED on the next `railway config apply`, so add any new one here.
    env: {
      ANTHROPIC_API_KEY: preserve(),
      APNS_KEY_ID: preserve(),
      APNS_KEY_P8: preserve(),
      APNS_TEAM_ID: preserve(),
      APNS_TOPIC: preserve(),
      APPLE_BUNDLE_ID: preserve(),
      CLAUDE_MONTHLY_BUDGET_CENTS: preserve(),
      DATABASE_URL: preserve(),
      ENVIRONMENT: preserve(),
      JWT_SECRET: preserve(),
      LOG_LEVEL: preserve(),
      OPENAI_API_KEY: preserve(),
      PRO_ALLOWLIST: preserve(),
      REDIS_URL: preserve(),
      USDA_API_KEY: preserve(),
      WHOOP_CLIENT_ID: preserve(),
      WHOOP_CLIENT_SECRET: preserve(),
      WHOOP_REDIRECT_URI: preserve(),
      WHOOP_TOKEN_ENCRYPTION_KEY: preserve(),
    },
    deploy: {
      startCommand: "./app serve --auto-migrate --hostname 0.0.0.0 --port 8080",
      // The Docker HEALTHCHECK pings /health; Railway waits for it before routing traffic.
      healthcheckPath: "/health",
      healthcheckTimeout: 30,
      // Restart policy: Railway's default (restart on failure, up to 10 times),
      // same as the old railway.toml. Railway stores the default as empty, so
      // writing it here would show up as a change on every plan.
    },
  });
  return project("tempo-backend", {
    resources: [tempoBackend],
  });
});
