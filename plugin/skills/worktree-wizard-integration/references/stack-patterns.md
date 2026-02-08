# Stack Patterns Reference

Per-framework Dockerfile, dev command, and compose service patterns for worktree-wizard integration.

## Python

### FastAPI

**Dockerfile:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

**Compose service:**
```yaml
  backend:
    build: ./backend
    labels:
      wt.base-port: "8000"
    ports:
      - "${WT_BACKEND_PORT:-8000}:8000"
    volumes:
      - ./backend:/app
```

**Entry point detection:** `main.py` with `FastAPI()`, or `uvicorn` in requirements.txt/pyproject.toml

### Django

**Dockerfile:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
```

**Compose service:**
```yaml
  backend:
    build: ./backend
    labels:
      wt.base-port: "8000"
    ports:
      - "${WT_BACKEND_PORT:-8000}:8000"
    volumes:
      - ./backend:/app
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings
```

**Entry point detection:** `manage.py` exists, or `django` in requirements

### Flask

**Dockerfile:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV FLASK_APP=app.py
CMD ["flask", "run", "--reload", "--host", "0.0.0.0", "--port", "5000"]
```

**Compose service:**
```yaml
  backend:
    build: ./backend
    labels:
      wt.base-port: "5000"
    ports:
      - "${WT_BACKEND_PORT:-5000}:5000"
    volumes:
      - ./backend:/app
    environment:
      - FLASK_APP=app.py
      - FLASK_DEBUG=1
```

**Entry point detection:** `flask` in requirements, `app.py` or `Flask(__name__)` in source

## Node.js

### Vite (Frontend)

**Dockerfile:**
```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]
```

**Compose service:**
```yaml
  frontend:
    build: ./frontend
    labels:
      wt.base-port: "3000"
    ports:
      - "${WT_FRONTEND_PORT:-3000}:3000"
    volumes:
      - ./frontend:/app
      - /app/node_modules
```

**package.json dev script:** `"dev": "vite --host 0.0.0.0 --port 3000"`

**Entry point detection:** `vite` in devDependencies

### Next.js (Frontend/Fullstack)

**Dockerfile:**
```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]
```

**Compose service:**
```yaml
  frontend:
    build: ./frontend
    labels:
      wt.base-port: "3000"
    ports:
      - "${WT_FRONTEND_PORT:-3000}:3000"
    volumes:
      - ./frontend:/app
      - /app/node_modules
      - /app/.next
```

**package.json dev script:** `"dev": "next dev --hostname 0.0.0.0 --port 3000"`

**Entry point detection:** `next` in dependencies/devDependencies

### Express (Backend)

**Dockerfile:**
```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]
```

**Compose service:**
```yaml
  backend:
    build: ./backend
    labels:
      wt.base-port: "3000"
    ports:
      - "${WT_BACKEND_PORT:-3000}:3000"
    volumes:
      - ./backend:/app
      - /app/node_modules
```

**package.json dev script:** `"dev": "nodemon index.js"` or `"dev": "tsx watch src/index.ts"`

**Entry point detection:** `express` in dependencies

### NestJS (Backend)

**Dockerfile:**
```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
CMD ["npm", "run", "start:dev"]
```

**Compose service:**
```yaml
  backend:
    build: ./backend
    labels:
      wt.base-port: "3000"
    ports:
      - "${WT_BACKEND_PORT:-3000}:3000"
    volumes:
      - ./backend:/app
      - /app/node_modules
      - /app/dist
```

**Entry point detection:** `@nestjs/core` in dependencies

## Go

### Standard / Gin / Echo / Fiber

**Dockerfile:**
```dockerfile
FROM golang:1.22
WORKDIR /app
RUN go install github.com/air-verse/air@latest
COPY go.mod go.sum ./
RUN go mod download
COPY . .
CMD ["air"]
```

**Compose service:**
```yaml
  backend:
    build: .
    labels:
      wt.base-port: "8080"
    ports:
      - "${WT_BACKEND_PORT:-8080}:8080"
    volumes:
      - ./:/app
```

**Air config (`.air.toml`):** Created automatically if not present. Default watches `*.go`.

**Entry point detection:** `go.mod` exists, `main.go` or `cmd/` directory

## Rust

### Actix-web / Axum / Rocket

**Dockerfile:**
```dockerfile
FROM rust:1.77
WORKDIR /app
RUN cargo install cargo-watch
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build && rm -rf src
COPY . .
CMD ["cargo", "watch", "-x", "run"]
```

**Compose service:**
```yaml
  backend:
    build: .
    labels:
      wt.base-port: "8080"
    ports:
      - "${WT_BACKEND_PORT:-8080}:8080"
    volumes:
      - ./:/app
      - cargo-cache:/usr/local/cargo/registry
volumes:
  cargo-cache:
```

**Entry point detection:** `Cargo.toml` with `actix-web`, `axum`, or `rocket` in dependencies

## Ruby

### Rails

**Dockerfile:**
```dockerfile
FROM ruby:3.3-slim
WORKDIR /app
RUN apt-get update && apt-get install -y build-essential libpq-dev
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]
```

**Compose service:**
```yaml
  backend:
    build: .
    labels:
      wt.base-port: "3000"
    ports:
      - "${WT_BACKEND_PORT:-3000}:3000"
    volumes:
      - ./:/app
      - bundle-cache:/usr/local/bundle
volumes:
  bundle-cache:
```

**Entry point detection:** `Gemfile` with `rails`, or `bin/rails` exists

## Java / Kotlin

### Spring Boot

**Dockerfile (Maven):**
```dockerfile
FROM eclipse-temurin:21-jdk
WORKDIR /app
COPY . .
RUN ./mvnw dependency:resolve
CMD ["./mvnw", "spring-boot:run"]
```

**Dockerfile (Gradle):**
```dockerfile
FROM eclipse-temurin:21-jdk
WORKDIR /app
COPY . .
RUN ./gradlew dependencies --no-daemon
CMD ["./gradlew", "bootRun"]
```

**Compose service:**
```yaml
  backend:
    build: .
    labels:
      wt.base-port: "8080"
    ports:
      - "${WT_BACKEND_PORT:-8080}:8080"
    volumes:
      - ./src:/app/src
```

Note: Spring Boot devtools must be in dependencies for auto-restart. Full source mount (`./:/app`) works but is slow due to build artifacts.

**Entry point detection:** `pom.xml` with `spring-boot-starter`, or `build.gradle` with `org.springframework.boot`

## Common Infrastructure Services

### PostgreSQL
```yaml
  db:
    image: postgres:16
    labels:
      wt.base-port: "5432"
      wt.data-dir: "/var/lib/postgresql/data"
    ports:
      - "${WT_DB_PORT:-5432}:5432"
    volumes:
      - ${WT_DB_DATA:-./.docker-data/db}:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=app
```

### MySQL
```yaml
  db:
    image: mysql:8
    labels:
      wt.base-port: "3306"
      wt.data-dir: "/var/lib/mysql"
    ports:
      - "${WT_DB_PORT:-3306}:3306"
    volumes:
      - ${WT_DB_DATA:-./.docker-data/db}:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=root
      - MYSQL_DATABASE=app
```

### MongoDB
```yaml
  mongo:
    image: mongo:7
    labels:
      wt.base-port: "27017"
      wt.data-dir: "/data/db"
    ports:
      - "${WT_MONGO_PORT:-27017}:27017"
    volumes:
      - ${WT_MONGO_DATA:-./.docker-data/mongo}:/data/db
```

### Redis
```yaml
  redis:
    image: redis:7-alpine
    labels:
      wt.base-port: "6379"
    ports:
      - "${WT_REDIS_PORT:-6379}:6379"
```

### RabbitMQ
```yaml
  rabbitmq:
    image: rabbitmq:3-management
    labels:
      wt.base-port: "5672"
    ports:
      - "${WT_RABBITMQ_PORT:-5672}:5672"
      - "${WT_RABBITMQ_MGMT_PORT:-15672}:15672"
```

Note: Services with multiple ports need a separate `wt.base-port` only for the primary port. Additional ports can use manual env var patterns.
