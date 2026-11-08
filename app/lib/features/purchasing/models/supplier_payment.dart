class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.supplierInvoiceId,
    required this.supplierId,
    required this.amountMinor,
    required this.paymentMethod,
    this.reference,
    required this.paidBy,
    required this.deviceId,
    required this.occurredAt,
    required this.createdAt,
    this.syncState = 'pending',
  });

  final String id;
  final String supplierInvoiceId;
  final String supplierId;
  final int amountMinor;
  final String paymentMethod;
  final String? reference;
  final String paidBy;
  final String deviceId;
  final String occurredAt;
  final String createdAt;
  final String syncState;

  factory SupplierPayment.fromMap(Map<String, dynamic> map) {
    return SupplierPayment(
      id: map['id'] as String,
      supplierInvoiceId: map['supplier_invoice_id'] as String,
      supplierId: map['supplier_id'] as String,
      amountMinor: (map['amount_minor'] as num).toInt(),
      paymentMethod: map['payment_method'] as String,
      reference: map['reference'] as String?,
      paidBy: map['paid_by'] as String,
      deviceId: map['device_id'] as String,
      occurredAt: map['occurred_at'] as String,
      createdAt: map['created_at'] as String,
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_invoice_id': supplierInvoiceId,
      'supplier_id': supplierId,
      'amount_minor': amountMinor,
      'payment_method': paymentMethod,
      'reference': reference,
      'paid_by': paidBy,
      'device_id': deviceId,
      'occurred_at': occurredAt,
      'created_at': createdAt,
      'sync_state': syncState,
    };
  }
}