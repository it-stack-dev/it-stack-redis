# Lab 04-02 — External Dependencies

**Module:** 04 — Redis cache and session store  
**Duration:** See [lab manual](https://github.com/it-stack-dev/it-stack-docs)  
**Test Script:** 	ests/labs/test-lab-04-02.sh  
**Compose File:** docker/docker-compose.lan.yml

## Objective

Connect redis to external PostgreSQL and Redis on separate containers.

## Prerequisites

- Lab 04-01 passes
- External PostgreSQL and Redis accessible

## Steps

### 1. Prepare Environment

```bash
cd it-stack-redis
cp .env.example .env  # edit as needed
```

### 2. Start Services

```bash
make test-lab-02
```

Or manually:

```bash
docker compose -f docker/docker-compose.lan.yml up -d
```

### 3. Verify

```bash
docker compose ps
curl -sf http://localhost:6379/health
```

### 4. Run Test Suite

```bash
bash tests/labs/test-lab-04-02.sh
```

## Expected Results

All tests pass with FAIL: 0.

## Cleanup

```bash
docker compose -f docker/docker-compose.lan.yml down -v
```

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for common issues.
