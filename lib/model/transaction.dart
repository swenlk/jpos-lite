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
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['_id'] ?? '',
      balance: json['balance'] ?? '0.00',
      bankPayment: json['bankPayment'] ?? '0.00',
      cardPayment: json['cardPayment'] ?? '0.00',
      cashPayment: json['cashPayment'] ?? '0.00',
      chequePayment: json['chequePayment'] ?? '0.00',
      contactNumber: json['contactNumber'] ?? '',
      createdDate: json['createdDate'] ?? '',
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'] ?? '',
      discount: json['discount'] ?? '0.00',
      info: json['info'],
      lineItems: (json['lineItems'] as List<dynamic>?)
              ?.map((item) => LineItem.fromJson(item))
              .toList() ??
          [],
      note: json['note'],
      orderDate: json['orderDate'] ?? '',
      paymentReferenceBank: json['paymentReferenceBank'],
      paymentReferenceCheque: json['paymentReferenceCheque'],
      paymentReferenceVoucher: json['paymentReferenceVoucher'],
      status: json['status'] ?? '',
      subTotal: json['subTotal'] ?? '0.00',
      total: json['total'] ?? '0.00',
      transactionId: json['transactionId'] ?? '',
      voucherPayment: json['voucherPayment'] ?? '0.00',
      vatAmount: json['vatAmount'],
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
    return LineItem(
      batchNumber: json['batchNumber'],
      categoryName: json['categoryName'] ?? '',
      count: json['count'] ?? '0',
      discount: json['discount'] ?? '0.00',
      discountPercentage: json['discountPercentage'] ?? '0.00',
      inventoryId: json['inventoryId'],
      itemCode: json['itemCode'] ?? '',
      itemId: json['itemId'] ?? '',
      itemName: json['itemName'] ?? '',
      lineTotal: json['lineTotal'] ?? '0.00',
      purchasePrice: json['purchasePrice'] ?? '0.00',
      salesPrice: json['salesPrice'] ?? '0.00',
      staffId: json['staffId'],
      staffName: json['staffName'],
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

