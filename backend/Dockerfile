# node:20-alpine (musl libc) hace que el binario nativo precompilado de bcrypt
# cargue pero reviente con SIGSEGV al usarlo (problema conocido de bcrypt en
# Alpine). node:20-slim es Debian (glibc), donde el binario sí es compatible.
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "src/index.js"]
