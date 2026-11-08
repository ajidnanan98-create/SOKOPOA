class SalePayment {
  const SalePayment({
    required this.method,
    required this.amountMinor,
    this.reference,
  });

  /// Supported methods: cash, mpesa, card, bank.
  final String method;

  /// Payment amount in KES minor units.
  final int amountMinor;

  /// Optional transaction reference, e.g. M-PESA receipt number.
  final String? reference;

  static const supportedMethods = <String>[
    'cash',
    'mpesa',
    'card',
    'bank',
  ];

  bool get hasValidMethod => supportedMethods.contains(method);

  bool get hasValidAmount => amountMinor > 0;
}
