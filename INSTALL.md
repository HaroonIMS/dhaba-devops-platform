# Dhaba 24-dish menu upgrade

This upgrade keeps the existing order API, kitchen dashboard, statistics dashboard,
and PostgreSQL data volume. It does not delete existing orders.

## 1. Back up the database first

From the repository root:

```bash
cd ~/dhaba-devops-platform
mkdir -p backups
docker compose -f dev/docker-compose.yml exec -T postgres \
  pg_dump -U dhaba -d dhaba > "backups/dhaba-before-menu-upgrade-$(date +%Y%m%d-%H%M%S).sql"
```

Check that the backup is non-empty:

```bash
ls -lh backups/
```

## 2. Apply the menu migration

```bash
docker compose -f dev/docker-compose.yml exec -T postgres \
  psql -v ON_ERROR_STOP=1 -U dhaba -d dhaba \
  < db/migrations/002_expand_pakistani_menu.sql
```

Clear the cached old menu:

```bash
docker compose -f dev/docker-compose.yml exec -T redis redis-cli DEL menu:cache
```

## 3. Validate the database menu

```bash
docker compose -f dev/docker-compose.yml exec -T postgres \
  psql -U dhaba -d dhaba -c "SELECT COUNT(*) AS dish_count, MIN(price), MAX(price) FROM menu;"
```

Expected dish_count: 24.

## 4. Rebuild the frontend

```bash
docker compose -f dev/docker-compose.yml build web
docker compose -f dev/docker-compose.yml up -d web
```

## 5. Run frontend checks

```bash
cd web
npm test
npm run lint
npm run build
cd ..
```

## 6. Check the live menu and website

```bash
curl -fsS http://localhost:8088/api/menu
curl -sS -o /dev/null -w "Website HTTP %{http_code}\n" http://localhost:8088/
```

The menu's descriptions, categories and image references are maintained in the React
frontend; the menu API continues returning the existing id/name/price contract. Prices
are stored in PostgreSQL as PKR numeric values.

Food photography is loaded from Unsplash URLs, so the browser needs internet access to
display those remote images. Ordering itself does not depend on image availability.
