class IncomeReceipt {
  final String id;
  final DateTime date;
  final double amount;
  final String payerName;
  final String? description;

  IncomeReceipt({
    required this.id,
    required this.date,
    required this.amount,
    required this.payerName,
    this.description,
  });

  factory IncomeReceipt.fromJson(Map<String, dynamic> json) {
    return IncomeReceipt(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      amount: (json['amount'] as num).toDouble(),
      payerName: json['payer_name'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'amount': amount,
      'payer_name': payerName,
      'description': description,
    };
  }
}
