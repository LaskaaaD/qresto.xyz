FROM node:20.19.0-alpine3.20@sha256:9a9c00587bcb88209b164b2dba1f59c7389ac3a2cec2cfe490fc43cd947ed531

ENV NODE_ENV=production
WORKDIR /usr/src/app

COPY app/package*.json ./
RUN npm ci --omit=dev

COPY app/ .

RUN mkdir -p /usr/src/app/public/uploads \
  && chown -R node:node /usr/src/app

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "require('http').get('http://127.0.0.1:3000/live', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "server.js"]
