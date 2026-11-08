PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS app_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE,
  name TEXT NOT NULL,
  category TEXT,
  description TEXT,
  base_unit TEXT NOT NULL,
  buying_cost_minor INTEGER NOT NULL DEFAULT 0,
  selling_price_minor INTEGER NOT NULL DEFAULT 0,
  minimum_quantity REAL NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending',
  image_path TEXT
);

CREATE TABLE IF NOT EXISTS product_units (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id),
  unit_name TEXT NOT NULL,
  base_units_per_unit REAL NOT NULL CHECK(base_units_per_unit > 0),
  UNIQUE(product_id, unit_name)
);

CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  credit_limit_minor INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS sales (
  id TEXT PRIMARY KEY,
  receipt_number TEXT NOT NULL UNIQUE,
  customer_id TEXT,
  cashier_user_id TEXT NOT NULL,
  subtotal_minor INTEGER NOT NULL,
  discount_minor INTEGER NOT NULL DEFAULT 0,
  total_minor INTEGER NOT NULL,
  paid_minor INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  device_id TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS sale_lines (
  id TEXT PRIMARY KEY,
  sale_id TEXT NOT NULL REFERENCES sales(id),
  product_id TEXT NOT NULL REFERENCES products(id),
  quantity REAL NOT NULL CHECK(quantity > 0),
  unit_name TEXT NOT NULL,
  base_quantity REAL NOT NULL CHECK(base_quantity > 0),
  unit_price_minor INTEGER NOT NULL,
  cost_minor INTEGER NOT NULL,
  line_total_minor INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS stock_movements (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id),
  movement_type TEXT NOT NULL,
  quantity_base REAL NOT NULL,
  unit_name TEXT NOT NULL,
  entered_quantity REAL NOT NULL DEFAULT 0,
  conversion_factor REAL NOT NULL DEFAULT 1,
  reference_type TEXT,
  reference_id TEXT,
  reason TEXT,
  actor_user_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS stocktakes (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK(status IN ('draft', 'completed', 'cancelled')),
  actor_user_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  reason TEXT,
  started_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS stocktake_lines (
  id TEXT PRIMARY KEY,
  stocktake_id TEXT NOT NULL
    REFERENCES stocktakes(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id),
  system_quantity_base REAL NOT NULL,
  counted_quantity_base REAL NOT NULL
    CHECK(counted_quantity_base >= 0),
  variance_quantity_base REAL NOT NULL,
  unit_name TEXT NOT NULL,
  entered_quantity REAL NOT NULL
    CHECK(entered_quantity >= 0),
  conversion_factor REAL NOT NULL
    CHECK(conversion_factor > 0),
  reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(stocktake_id, product_id)
);

CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  related_type TEXT NOT NULL,
  related_id TEXT NOT NULL,
  method TEXT NOT NULL,
  amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
  reference TEXT,
  received_by TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  payment_method TEXT NOT NULL,
  description TEXT,
  actor_user_id TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS workers (
  id TEXT PRIMARY KEY,
  full_name TEXT NOT NULL,
  phone TEXT,
  role TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  hired_at TEXT,
  created_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS worker_payments (
  id TEXT PRIMARY KEY,
  worker_id TEXT NOT NULL REFERENCES workers(id),
  payment_type TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  description TEXT,
  paid_at TEXT NOT NULL,
  recorded_by TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS sync_outbox (
  event_id TEXT PRIMARY KEY,
  aggregate_type TEXT NOT NULL,
  aggregate_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS audit_log (
  id TEXT PRIMARY KEY,
  actor_user_id TEXT,
  device_id TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  previous_value_json TEXT,
  new_value_json TEXT,
  reason TEXT,
  occurred_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_stock_product_time
  ON stock_movements(product_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_stocktakes_status
  ON stocktakes(status, started_at);

CREATE INDEX IF NOT EXISTS idx_stocktake_lines_session
  ON stocktake_lines(stocktake_id);

CREATE INDEX IF NOT EXISTS idx_stocktake_lines_product
  ON stocktake_lines(product_id);

CREATE INDEX IF NOT EXISTS idx_sales_time
  ON sales(occurred_at);

CREATE INDEX IF NOT EXISTS idx_outbox_status
  ON sync_outbox(status, created_at);
