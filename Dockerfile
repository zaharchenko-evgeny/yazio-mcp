# syntax=docker/dockerfile:1

############################
# Stage 1 — build (dev deps)
############################
FROM node:22-alpine AS build
WORKDIR /app

# Install with the lockfile, but never run package install scripts.
# (Only esbuild/fsevents declare scripts here, both dev-only, but we block
#  arbitrary code execution at install time regardless.)
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# Prune to production dependencies only (still no scripts).
RUN npm prune --omit=dev --ignore-scripts

############################
# Stage 2 — runtime (minimal)
############################
FROM node:22-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# Copy only what is needed to run: compiled output, prod node_modules, and
# package.json (index.ts reads ../package.json for its version string).
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json

# Drop to the unprivileged user that the node image already provides.
USER node

# stdio MCP server — no ports are exposed, communication is over stdin/stdout.
ENTRYPOINT ["node", "dist/index.js"]
