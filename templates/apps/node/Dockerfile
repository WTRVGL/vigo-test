# Production Node.js (multi-stage)
# Build stage
FROM node:20-alpine AS build
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
# If you have a build step (e.g., Next.js, Nest), run it here:
# RUN npm run build

# Runtime stage
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
USER node
COPY --from=build /app .
EXPOSE 3000
CMD ["node", "server.js"]

