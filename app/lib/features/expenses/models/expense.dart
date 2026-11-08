class Expense {
  final String id;
  final String category;
  final int amountMinor;
  final String paymentMethod;
  final String? description;
  final String actorUserId;
  final DateTime occurredAt;
  final String syncState;

  const Expense({
    required this.id,
    required this.category,
    required this.amountMinor,
    required this.paymentMethod,
    this.description,
    required this.actorUserId,
    required this.occurredAt,
    this.syncState = 'pending',
  });

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      category: map['category'] as String,
      amountMinor: map['amount_minor'] as int,
      paymentMethod: map['payment_method'] as String,
      description: map['description'] as String?,
      actorUserId: map['actor_user_id'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount_minor': amountMinor,
      'payment_method': paymentMethod,
      'description': description,
      'actor_user_id': actorUserId,
      'occurred_at': occurredAt.toIso8601String(),
      'sync_state': syncState,
    };
  }
}
