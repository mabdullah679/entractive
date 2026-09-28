# ---- build stage -----------------------------------------------------------
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- serve stage -----------------------------------------------------------
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
# 20-*.sh runs before nginx starts (nginx:alpine entrypoint convention), so the
# runtime config exists before the first request can be served.
COPY docker/env.sh /docker-entrypoint.d/20-app-env.sh
RUN chmod +x /docker-entrypoint.d/20-app-env.sh
EXPOSE 80
