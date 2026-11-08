CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE businesses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'KES',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  username TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','manager','cashier','worker')),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (business_id, username)
);

CREATE TABLE devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  device_name TEXT NOT NULL,
  platform TEXT NOT NULL,
  revoked_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ
);

CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  code TEXT,
  name TEXT NOT NULL,
  category TEXT,
  base_unit TEXT NOT NULL,
  minimum_quantity NUMERIC(18,4) NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (business_id, code)
);

CREATE TABLE product_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id),
  unit_name TEXT NOT NULL,
  base_units_per_unit NUMERIC(18,6) NOT NULL CHECK (base_units_per_unit > 0),
  UNIQUE(product_id, unit_name)
);

CREATE TABLE stock_movements (
  id UUID PRIMARY KEY,
  business_id UUID NOT NULL REFERENCES businesses(id),
  product_id UUID NOT NULL REFERENCES products(id),
  movement_type TEXT NOT NULL,
  quantity_base NUMERIC(18,4) NOT NULL,
  reference_type TEXT,
  reference_id UUID,
  reason TEXT,
  actor_user_id UUID NOT NULL REFERENCES users(id),
  device_id UUID NOT NULL REFERENCES devices(id),
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sales (
  id UUID PRIMARY KEY,
  business_id UUID NOT NULL REFERENCES businesses(id),
  receipt_number TEXT NOT NULL,
  customer_id UUID,
  cashier_user_id UUID NOT NULL REFERENCES users(id),
  subtotal_minor BIGINT NOT NULL,
  discount_minor BIGINT NOT NULL DEFAULT 0,
  total_minor BIGINT NOT NULL,
  paid_minor BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  device_id UUID NOT NULL REFERENCES devices(id),
  UNIQUE(business_id, receipt_number)
);

CREATE TABLE payments (
  id UUID PRIMARY KEY,
  business_id UUID NOT NULL REFERENCES businesses(id),
  related_type TEXT NOT NULL,
  related_id UUID NOT NULL,
  method TEXT NOT NULL CHECK (method IN ('cash','mpesa','bank','cheque','credit')),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  reference TEXT,
  received_by UUID NOT NULL REFERENCES users(id),
  occurred_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE sync_events (
  event_id UUID PRIMARY KEY,
  business_id UUID NOT NULL REFERENCES businesses(id),
  device_id UUID NOT NULL REFERENCES devices(id),
  aggregate_type TEXT NOT NULL,
  aggregate_id UUID NOT NULL,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  actor_user_id UUID REFERENCES users(id),
  device_id UUID REFERENCES devices(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  previous_value JSONB,
  new_value JSONB,
  reason TEXT,
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_stock_product_time ON stock_movements(product_id, occurred_at);
CREATE INDEX idx_sales_business_time ON sales(business_id, occurred_at);
CREATE INDEX idx_sync_business_received ON sync_events(business_id, received_at);
CREATE INDEX idx_audit_business_time ON audit_log(business_id, created_at);


-- Additional domain tables for the next implementation stages.
CREATE TABLE IF NOT EXISTS categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  name TEXT NOT NULL,
  UNIQUE (business_id, name)
);

CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  credit_limit_minor BIGINT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  category TEXT NOT NULL,
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  payment_method TEXT NOT NULL,
  description TEXT,
  actor_user_id UUID NOT NULL REFERENCES users(id),
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  full_name TEXT NOT NULL,
  phone TEXT,
  role TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  hired_at DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS worker_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  worker_id UUID NOT NULL REFERENCES workers(id),
  payment_type TEXT NOT NULL CHECK (payment_type IN ('salary','wage','advance','deduction','bonus')),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  description TEXT,
  paid_at TIMESTAMPTZ NOT NULL,
  recorded_by UUID NOT NULL REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS stock_cost_layers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id),
  product_id UUID NOT NULL REFERENCES products(id),
  source_movement_id UUID NOT NULL REFERENCES stock_movements(id),
  quantity_remaining_base NUMERIC(18,4) NOT NULL CHECK (quantity_remaining_base >= 0),
  unit_cost_minor BIGINT NOT NULL CHECK (unit_cost_minor >= 0),
  received_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_customers_business_name ON customers(business_id, name);
CREATE INDEX IF NOT EXISTS idx_suppliers_business_name ON suppliers(business_id, name);
CREATE INDEX IF NOT EXISTS idx_expenses_business_time ON expenses(business_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_workers_business_name ON workers(business_id, full_name);
CREATE INDEX IF NOT EXISTS idx_cost_layers_product_time ON stock_cost_layers(product_id, received_at);
