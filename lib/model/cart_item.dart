import 'item.dart';

class CartItem {
  final String itemId;
  final String itemDisplayName;
  final String? batchNumber;
  final String salesPrice;
  final int quantity;
  final int maxQuantity;

  CartItem({
    required this.itemId,
    required this.itemDisplayName,
    this.batchNumber,
    required this.salesPrice,
    required this.quantity,
    required this.maxQuantity,
  });

  double get totalPrice => quantity * double.parse(salesPrice);

  CartItem copyWith({
    String? itemId,
    String? itemDisplayName,
    String? batchNumber,
    String? salesPrice,
    int? quantity,
    int? maxQuantity,
  }) {
    return CartItem(
      itemId: itemId ?? this.itemId,
      itemDisplayName: itemDisplayName ?? this.itemDisplayName,
      batchNumber: batchNumber ?? this.batchNumber,
      salesPrice: salesPrice ?? this.salesPrice,
      quantity: quantity ?? this.quantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'itemDisplayName': itemDisplayName,
      'batchNumber': batchNumber,
      'salesPrice': salesPrice,
      'quantity': quantity,
      'maxQuantity': maxQuantity,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      itemId: json['itemId'] ?? '',
      itemDisplayName: json['itemDisplayName'] ?? '',
      batchNumber: json['batchNumber'],
      salesPrice: json['salesPrice'] ?? '0.0',
      quantity: json['quantity'] ?? 1,
      maxQuantity: json['maxQuantity'] ?? 1,
    );
  }
}
