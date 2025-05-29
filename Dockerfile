ARG PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# ------------------------------
# Base
# ------------------------------
# Base stage: Contains only the minimal dependencies required for runtime
# (node_modules and Playwright system dependencies)
FROM node:22-bookworm-slim AS base

ARG PLAYWRIGHT_BROWSERS_PATH
ENV PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH}

# Set the working directory
WORKDIR /app

# Install system dependencies first (can be cached separately)
RUN npx -y playwright-core install-deps chromium && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install production dependencies
RUN --mount=type=cache,target=/root/.npm,sharing=locked,id=npm-cache \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
  npm ci --omit=dev

# ------------------------------
# Builder
# ------------------------------
FROM base AS builder

RUN --mount=type=cache,target=/root/.npm,sharing=locked,id=npm-cache \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
  npm ci

# Copy the rest of the app
COPY *.json *.js *.ts .
COPY src src/

# Build the app
RUN npm run build

# ------------------------------
# Browser
# ------------------------------
# Cache optimization:
# - Browser is downloaded only when node_modules or Playwright system dependencies change
# - Cache is reused when only source code changes
FROM base AS browser

# Install browser
# RUN npx -y playwright-core install --no-shell chromium
RUN npx -y playwright-core install --no-shell chromium chrome
# RUN npx -y playwright-core install --no-shell chromium chrome msedge

# ------------------------------
# Runtime
# ------------------------------
FROM node:22-bookworm-slim

ARG PLAYWRIGHT_BROWSERS_PATH
ARG USERNAME=node
ENV NODE_ENV=production
ENV PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH}

# Set the working directory
WORKDIR /app

# Install only chromium system dependencies
RUN npx -y playwright-core@latest install-deps chromium && \
    rm -rf /var/cache/apt/archives/* && \
    apt-get clean

# Copy production dependencies from base
COPY --from=base --chown=${USERNAME}:${USERNAME} /app/node_modules /app/node_modules

# Copy browser binaries
COPY --from=browser --chown=${USERNAME}:${USERNAME} ${PLAYWRIGHT_BROWSERS_PATH} ${PLAYWRIGHT_BROWSERS_PATH}
COPY --from=browser --chown=${USERNAME}:${USERNAME} /opt/google/ /opt/google/
# COPY --from=browser --chown=${USERNAME}:${USERNAME} /opt/microsoft/ /opt/microsoft/

# Copy built application
COPY --chown=${USERNAME}:${USERNAME} cli.js package.json ./
COPY --from=builder --chown=${USERNAME}:${USERNAME} /app/lib /app/lib

USER ${USERNAME}

# Run in headless and only with chromium (other browsers need more dependencies not included in this image)
ENTRYPOINT ["node", "cli.js", "--headless", "--browser", "chromium", "--no-sandbox"]
