FROM node:24-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY *.mjs ./
COPY public ./public
ENV NODE_ENV=production S2T_BIND_HOST=0.0.0.0
EXPOSE 4317
CMD ["node", "server.mjs"]
