class Transaction {
  final String id;
  final String balance;
  final String bankPayment;
  final String cardPayment;
  final String cashPayment;
  final String chequePayment;
  final String contactNumber;
  final String createdDate;
  final String customerId;
  final String customerName;
  final String discount;
  final dynamic info;
  final List<LineItem> lineItems;
  final dynamic note;
  final String orderDate;
  final String? paymentReferenceBank;
  final String? paymentReferenceCheque;
  final String? paymentReferenceVoucher;
  final String status;
  final String subTotal;
  final String total;
  final String transactionId;
  final String voucherPayment;
  final String? vatAmount;
  final String? totalDiscountPercentage;
  final String? totalDiscountValue;

  Transaction({
    required this.id,
    required this.balance,
    required this.bankPayment,
    required this.cardPayment,
    required this.cashPayment,
    required this.chequePayment,
    required this.contactNumber,
    required this.createdDate,
    required this.customerId,
    required this.customerName,
    required this.discount,
    this.info,
    required this.lineItems,
    this.note,
    required this.orderDate,
    this.paymentReferenceBank,
    this.paymentReferenceCheque,
    this.paymentReferenceVoucher,
    required this.status,
    required this.subTotal,
    required this.total,
    required this.transactionId,
    required this.voucherPayment,
    this.vatAmount,
    this.totalDiscountPercentage,
    this.totalDiscountValue,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Helper function to convert value to string
    String _toString(dynamic value, String defaultValue) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      if (value is int) return value.toString();
      if (value is double) return value.toStringAsFixed(2);
      return value.toString();
    }

    return Transaction(
      id: _toString(json['_id'], ''),
      balance: _toString(json['balance'], '0.00'),
      bankPayment: _toString(json['bankPayment'], '0.00'),
      cardPayment: _toString(json['cardPayment'], '0.00'),
      cashPayment: _toString(json['cashPayment'], '0.00'),
      chequePayment: _toString(json['chequePayment'], '0.00'),
      contactNumber: _toString(json['contactNumber'], ''),
      createdDate: _toString(json['createdDate'], ''),
      customerId: _toString(json['customerId'], ''),
      customerName: _toString(json['customerName'], ''),
      discount: _toString(json['discount'], '0.00'),
      info: json['info'],
      lineItems: (json['lineItems'] as List<dynamic>?)
              ?.map((item) => LineItem.fromJson(item))
              .toList() ??
          [],
      note: json['note'],
      orderDate: _toString(json['orderDate'], ''),
      paymentReferenceBank: json['paymentReferenceBank']?.toString(),
      paymentReferenceCheque: json['paymentReferenceCheque']?.toString(),
      paymentReferenceVoucher: json['paymentReferenceVoucher']?.toString(),
      status: _toString(json['status'], ''),
      subTotal: _toString(json['subTotal'], '0.00'),
      total: _toString(json['total'], '0.00'),
      transactionId: _toString(json['transactionId'], ''),
      voucherPayment: _toString(json['voucherPayment'], '0.00'),
      vatAmount: json['vatAmount']?.toString(),
      totalDiscountPercentage: json['totalDiscountPercentage']?.toString(),
      totalDiscountValue: json['totalDiscountValue']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'balance': balance,
      'bankPayment': bankPayment,
      'cardPayment': cardPayment,
      'cashPayment': cashPayment,
      'chequePayment': chequePayment,
      'contactNumber': contactNumber,
      'createdDate': createdDate,
      'customerId': customerId,
      'customerName': customerName,
      'discount': discount,
      'info': info,
      'lineItems': lineItems.map((item) => item.toJson()).toList(),
      'note': note,
      'orderDate': orderDate,
      'paymentReferenceBank': paymentReferenceBank,
      'paymentReferenceCheque': paymentReferenceCheque,
      'paymentReferenceVoucher': paymentReferenceVoucher,
      'status': status,
      'subTotal': subTotal,
      'total': total,
      'transactionId': transactionId,
      'voucherPayment': voucherPayment,
      'vatAmount': vatAmount,
      'totalDiscountPercentage': totalDiscountPercentage,
      'totalDiscountValue': totalDiscountValue,
    };
  }
}

class LineItem {
  final String? batchNumber;
  final String categoryName;
  final String count;
  final String discount;
  final String discountPercentage;
  final String? inventoryId;
  final String itemCode;
  final String itemId;
  final String itemName;
  final String lineTotal;
  final String purchasePrice;
  final String salesPrice;
  final String? staffId;
  final String? staffName;

  LineItem({
    this.batchNumber,
    required this.categoryName,
    required this.count,
    required this.discount,
    required this.discountPercentage,
    this.inventoryId,
    required this.itemCode,
    required this.itemId,
    required this.itemName,
    required this.lineTotal,
    required this.purchasePrice,
    required this.salesPrice,
    this.staffId,
    this.staffName,
  });

  factory LineItem.fromJson(Map<String, dynamic> json) {
    // Helper function to convert value to string
    String _toString(dynamic value, String defaultValue) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      if (value is int) return value.toString();
      if (value is double) return value.toStringAsFixed(2);
      return value.toString();
    }

    return LineItem(
      batchNumber: json['batchNumber']?.toString(),
      categoryName: _toString(json['categoryName'], ''),
      count: _toString(json['count'], '0'),
      discount: _toString(json['discount'], '0.00'),
      discountPercentage: _toString(json['discountPercentage'], '0.00'),
      inventoryId: json['inventoryId']?.toString(),
      itemCode: _toString(json['itemCode'], ''),
      itemId: _toString(json['itemId'], ''),
      itemName: _toString(json['itemName'], ''),
      lineTotal: _toString(json['lineTotal'], '0.00'),
      purchasePrice: _toString(json['purchasePrice'], '0.00'),
      salesPrice: _toString(json['salesPrice'], '0.00'),
      staffId: json['staffId']?.toString(),
      staffName: json['staffName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batchNumber': batchNumber,
      'categoryName': categoryName,
      'count': count,
      'discount': discount,
      'discountPercentage': discountPercentage,
      'inventoryId': inventoryId,
      'itemCode': itemCode,
      'itemId': itemId,
      'itemName': itemName,
      'lineTotal': lineTotal,
      'purchasePrice': purchasePrice,
      'salesPrice': salesPrice,
      'staffId': staffId,
      'staffName': staffName,
    };
  }
}

