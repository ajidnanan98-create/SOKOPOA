# SOKOPOA development status — Milestone 1

## Included in this package
- Retained the approved Light Professional visual direction.
- Expanded desktop/mobile navigation for the agreed business modules.
- Added reusable module workspace scaffolds.
- Added a local SQLite initialization layer with Windows desktop FFI setup.
- Expanded local SQLite schema for products, units, sales, customers, suppliers,
  stock movements, payments, expenses, workers, worker payments, sync outbox and audit.
- Added UI/library dependencies for charts, tables, barcode scanning, PDF/printing,
  secure storage, connectivity and preferences.
- Expanded PostgreSQL schema with customer, supplier, expense, worker and cost-layer tables.
- Preserved the FastAPI backend foundation and added a capability/status endpoint.

## Important status disclosure
This is a development milestone, NOT a production-ready wholesale system.
Module pages are navigation/workspace scaffolds. Their action buttons explicitly state
that they do not yet create business records. The local database currently initializes
the core schema, but repository/service CRUD, transactional POS, costing, permission
enforcement, cloud PostgreSQL persistence, JWT sessions, synchronization, conflict
resolution, backup/restore and acceptance tests still need implementation.

The API authentication route remains an in-memory development placeholder and must not
be used with real business accounts or deployed as production authentication.

## Next implementation sequence
1. Complete local database migrations and repositories.
2. Implement products, categories, units and stock ledger CRUD.
3. Implement atomic POS checkout, payment allocation and receipt numbering.
4. Implement customer balances, supplier balances, expenses and worker payments.
5. Add costing engine and accounting/reporting queries.
6. Replace placeholder backend authentication with PostgreSQL-backed JWT sessions.
7. Implement idempotent sync protocol, conflict review and remote administration.
8. Add automated tests, backup/restore and platform builds.
