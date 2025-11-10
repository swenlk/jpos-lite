class Item {
  final String id;
  final String category;
  final String code;
  final String displayName;
  final bool inventoried;
  final List<Inventory> inventory;
  final String name;
  final String? purchasePrice;
  final String? salesPrice;

  Item({
    required this.id,
    required this.category,
    required this.code,
    required this.displayName,
    required this.inventoried,
    required this.inventory,
    required this.name,
    this.purchasePrice,
    this.salesPrice,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['_id'] ?? '',
      category: json['category'] ?? '',
      code: json['code'] ?? '',
      displayName: json['displayName'] ?? '',
      inventoried: json['inventoried'] ?? false,
      inventory: (json['inventory'] as List<dynamic>?)
          ?.map((inv) => Inventory.fromJson(inv))
          .toList() ?? [],
      name: json['name'] ?? '',
      purchasePrice: json['purchasePrice']?.toString(),
      salesPrice: json['salesPrice']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'category': category,
      'code': code,
      'displayName': displayName,
      'inventoried': inventoried,
      'inventory': inventory.map((inv) => inv.toJson()).toList(),
      'name': name,
      'purchasePrice': purchasePrice,
      'salesPrice': salesPrice,
    };
  }
}

class Inventory {
  final String id;
  final String batchNumber;
  final String createdDate;
  final String purchasePrice;
  final String salesPrice;
  final String stock;

  Inventory({
    required this.id,
    required this.batchNumber,
    required this.createdDate,
    required this.purchasePrice,
    required this.salesPrice,
    required this.stock,
  });

  factory Inventory.fromJson(Map<String, dynamic> json) {
    return Inventory(
      id: json['_id'] ?? '',
      batchNumber: json['batchNumber'] ?? '',
      createdDate: json['createdDate'] ?? '',
      purchasePrice: json['purchasePrice']?.toString() ?? '0.0',
      salesPrice: json['salesPrice']?.toString() ?? '0.0',
      stock: json['stock']?.toString() ?? '0.0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'batchNumber': batchNumber,
      'createdDate': createdDate,
      'purchasePrice': purchasePrice,
      'salesPrice': salesPrice,
      'stock': stock,
    };
  }
}
