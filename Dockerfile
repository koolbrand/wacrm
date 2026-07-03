# syntax=docker/dockerfile:1

# wacrm — Docker image for Coolify (koolbrand fork).
#
# Multi-stage build on `next start` (not standalone output): the repo's
# own package.json defines `"start": "next start"`, so this runs the app
# exactly as its authors intend. It does not depend on the internal
# .next/standalone layout — which the repo's AGENTS.md warns may differ
# from upstream Next.js.
#
# The runner carries the FULL node_modules (not a --omit=dev prune)
# on purpose: `next start` loads the TypeScript `next.config.ts` at
# runtime, which needs the `typescript` package (a devDependency).
# Pruning dev deps would break startup.

# ---- Stage 1: install deps ----
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- Stage 2: build ----
FROM node:22-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# NEXT_PUBLIC_* vars are inlined at build time, so they must be present
# now (not just at runtime). Coolify passes these as build args.
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_SITE_URL
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY \
    NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL \
    NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ---- Stage 3: runtime ----
FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0
COPY --from=builder --chown=node:node /app/node_modules  ./node_modules
COPY --from=builder --chown=node:node /app/.next         ./.next
COPY --from=builder --chown=node:node /app/public        ./public
COPY --from=builder --chown=node:node /app/package.json  ./package.json
COPY --from=builder --chown=node:node /app/next.config.ts ./next.config.ts
COPY --from=builder --chown=node:node /app/tsconfig.json  ./tsconfig.json
USER node
EXPOSE 3000
CMD ["npm", "run", "start"]
