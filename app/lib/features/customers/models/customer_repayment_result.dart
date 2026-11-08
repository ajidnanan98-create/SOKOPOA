class CustomerRepaymentAllocation {
  const CustomerRepaymentAllocation({
    required this.saleId,
    required this.receiptNumber,
    required this.amountMinor,
    required this.paidMinor,
    required this.balanceMinor,
    required this.saleStatus,
  });

  /// Sale receiving part or all of the repayment.
  final String saleId;

  /// Receipt number for traceability.
  final String receiptNumber;

  /// Amount allocated to this sale in KES minor units.
  final int amountMinor;

  /// Total amount paid on this sale after allocation.
  final int paidMinor;

  /// Remaining balance on this sale after allocation.
  final int balanceMinor;

  /// Updated sale status: paid, unpaid or part_paid.
  final String saleStatus;
}

class CustomerRepaymentResult {
  const CustomerRepaymentResult({
    required this.customerId,
    required this.amountMinor,
    required this.method,
    required this.reference,
    required this.receivedBy,
    required this.occurredAt,
    required this.allocations,
    required this.remainingDebtMinor,
  });

  final String customerId;
  final int amountMinor;
  final String method;
  final String? reference;
  final String receivedBy;
  final DateTime occurredAt;

  /// Shows how the repayment was distributed across outstanding sales.
  final List<CustomerRepaymentAllocation> allocations;

  /// Customer's total outstanding debt after this repayment.
  final int remainingDebtMinor;
}
