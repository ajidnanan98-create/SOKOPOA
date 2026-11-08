class SaleResult {
  const SaleResult({
    required this.saleId,
    required this.receiptNumber,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.paidMinor,
    required this.balanceMinor,
    required this.status,
    required this.occurredAt,
  });

  final String saleId;
  final String receiptNumber;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
  final int paidMinor;
  final int balanceMinor;
  final String status;
  final DateTime occurredAt;

  bool get isFullyPaid => balanceMinor == 0;

  bool get hasOutstandingBalance => balanceMinor > 0;
}
