class CustomerRepaymentHistoryEntry {
  const CustomerRepaymentHistoryEntry({
    required this.paymentId,
    required this.saleId,
    required this.receiptNumber,
    required this.amountMinor,
    required this.method,
    required this.reference,
    required this.receivedBy,
    required this.occurredAt,
  });

  final String paymentId;
  final String saleId;
  final String receiptNumber;
  final int amountMinor;
  final String method;
  final String? reference;
  final String receivedBy;
  final DateTime occurredAt;

  factory CustomerRepaymentHistoryEntry.fromMap(
    Map<String, dynamic> map,
  ) {
    return CustomerRepaymentHistoryEntry(
      paymentId: map['payment_id'] as String,
      saleId: map['sale_id'] as String,
      receiptNumber: map['receipt_number'] as String,
      amountMinor: (map['amount_minor'] as num).toInt(),
      method: map['method'] as String,
      reference: map['reference'] as String?,
      receivedBy: map['received_by'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
    );
  }
}
