class ExpenseModel {
  final String id;
  final String title;
  final double amount;
  final String description;
  final String receiptUrl;
  final String createdBy;
  final String status;
  final DateTime createdAt;

  ExpenseModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.description,
    required this.receiptUrl,
    required this.createdBy,
    required this.status,
    required this.createdAt,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map, String docId) {
    return ExpenseModel(
      id: docId,
      title: map['title'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      description: map['description'] ?? '',
      receiptUrl: map['receiptUrl'] ?? '',
      createdBy: map['createdBy'] ?? '',
      status: map['status'] ?? 'pending',
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'description': description,
      'receiptUrl': receiptUrl,
      'createdBy': createdBy,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
