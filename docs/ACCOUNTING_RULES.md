# Accounting invariants
1. Money is represented as integer minor units (KES cents) in persisted records.
2. Stock quantities are converted to a product's base unit before posting.
3. A posted sale and its stock movements are committed atomically.
4. A sale/payment sync event has a stable UUID idempotency key.
5. Credit sales create receivables; they do not increase cash received.
6. Customer receipts, supplier payments, salary payments and expenses are distinct transaction types.
7. Profit uses assigned historical cost (FIFO or weighted average); never substitute current purchase cost.
8. Posted transactions are corrected by reversal/refund/adjustment, not deletion.
9. Every stock balance is derived from opening stock plus immutable stock movements.
