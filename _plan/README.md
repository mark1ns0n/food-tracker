# foodtracker — план: ВЫТЕСНЕН планом super-app

⚠️ Все 44 задачи в `pending/` — **superseded**, не выполнять:

- **001–018** (перенос debt-фич из `ban`) — отменены: `ban` мигрирует в super-app
  собственным C-треком (`../super-app/_plan/pending/C01–C06`), дублировать его
  фичи здесь больше не нужно.
- **019–044** (собственный sync-бэкенд: Postgres, k8s на mPi5, ArgoCD, GHCR) —
  отменены: бэкенд заменён общим B-треком super-app
  (`../super-app/_plan/pending/B00–B05`: Rust + axum + SQLite, self-host,
  device-токен). Второй бэкенд не строим.

Актуальный план миграции foodtracker — один файл
**`../super-app/_plan/pending/F01-food-sync-and-migration.md`** (19 атомарных
задач, фазы 0–4). Физический перенос файлов отсюда в `_plan/superseded/` —
задача **F01.04** (этот README — её опережающая часть, чтобы никто не начал
выполнять устаревшие задачи до неё).

Каталог фич — `super-app/_plan/pending/S06`; перенос UI в оболочку —
F01.16–F01.19.
