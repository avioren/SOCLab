FROM node:22-bookworm-slim
WORKDIR /renderer
RUN npm install --omit=dev --no-audit --no-fund beautiful-mermaid@1.1.3
COPY render.mjs /renderer/render.mjs
ENTRYPOINT ["node", "/renderer/render.mjs"]
