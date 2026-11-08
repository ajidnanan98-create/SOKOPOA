class SupplierInvoice {
  const SupplierInvoice({
    required this.id,
    required this.supplierId,
    required this.invoiceNumber,
    required this.invoiceDate,
    this.purchaseOrderId,
    this.dueDate,
    this.subtotalMinor = 0,
    this.taxMinor = 0,
    this.otherChargesMinor = 0,
    this.totalMinor = 0,
    this.status = 'open',
    this.notes,
    required this.actorUserId,
    required this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.syncState = 'pending',
  });

  final String id;
  final String supplierId;
  final String invoiceNumber;
  final String? purchaseOrderId;
  final String invoiceDate;
  final String? dueDate;
  final int subtotalMinor;
  final int taxMinor;
  final int otherChargesMinor;
  final int totalMinor;
  final String status;
  final String? notes;
  final String actorUserId;
  final String deviceId;
  final String createdAt;
  final String updatedAt;
  final String syncState;

  factory SupplierInvoice.fromMap(Map<String, dynamic> map) {
    return SupplierInvoice(
      id: map['id'] as String,
      supplierId: map['supplier_id'] as String,
      invoiceNumber: map['invoice_number'] as String,
      purchaseOrderId: map['purchase_order_id'] as String?,
      invoiceDate: map['invoice_date'] as String,
      dueDate: map['due_date'] as String?,
      subtotalMinor: (map['subtotal_minor'] as num).toInt(),
      taxMinor: (map['tax_minor'] as num).toInt(),
      otherChargesMinor:
          (map['other_charges_minor'] as num).toInt(),
      totalMinor: (map['total_minor'] as num).toInt(),
      status: map['status'] as String? ?? 'open',
      notes: map['notes'] as String?,
      actorUserId: map['actor_user_id'] as String,
      deviceId: map['device_id'] as String,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'invoice_number': invoiceNumber,
      'purchase_order_id': purchaseOrderId,
      'invoice_date': invoiceDate,
      'due_date': dueDate,
      'subtotal_minor': subtotalMinor,
      'tax_minor': taxMinor,
      'other_charges_minor': otherChargesMinor,
      'total_minor': totalMinor,
      'status': status,
      'notes': notes,
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'sync_state': syncState,
    };
  }
}