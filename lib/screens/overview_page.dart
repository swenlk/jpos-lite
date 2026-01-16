import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/endpoints.dart';
import '../utils/app_configs.dart';
import '../utils/snackbar_manager.dart';
import '../model/transaction.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  int _selectedIndex = 0;
  final List<String> _options = [
    'Today',
    'Yesterday',
    'Week',
    'Month',
    'Year',
    'Custom',
  ];
  String? activeToken;
  bool _isLoading = false;
  List<Transaction> _transactions = [];

  // Transaction Summary fields
  int _pendingCount = 0;
  int _completedCount = 0;
  int _totalTransactions = 0;

  // Sales Summary fields
  double _preDiscountSales = 0.0;
  double _totalDiscounts = 0.0;
  double _totalVat = 0.0;
  double _totalSales = 0.0;

  // Payment Summary fields
  double _paymentCash = 0.0;
  double _paymentCard = 0.0;
  double _paymentBank = 0.0;
  double _paymentCheque = 0.0;
  double _paymentVoucher = 0.0;
  double _paymentTotal = 0.0;

  // Opening Float Summary fields
  String? _openingFloat;
  double _cashPayment = 0.0;
  double _expenses = 0.0;
  double _balanceReturned = 0.0;
  double _currentCashInDrawer = 0.0;

  // ========== NEW: Item Sales Summary fields ==========
  List<ItemSalesSummary> _itemSalesSummary = [];

  // ========== NEW: Category Sales Summary fields ==========
  List<CategorySalesSummary> _categorySalesSummary = [];
  int _itemCategorySelectedIndex = 0; // 0 = Item, 1 = Category
  // ====================================================

  @override
  void initState() {
    super.initState();
    _openingFloat = '-'; // Default value
    _expenses = 0.0; // Default value
    _loadActiveToken();
  }

  Future<void> _loadActiveToken() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      activeToken = prefs.getString('activeToken');
    });
    // Calculate and print date range for "Today" on initialization
    if (activeToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleDateRangeSelection(0);
      });
    }
  }

  void _handleDateRangeSelection(int index) {
    setState(() {
      _selectedIndex = index;
    });

    DateTime startDate;
    DateTime endDate;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (index) {
      case 0: // Today
        startDate = today;
        endDate = today;
        break;
      case 1: // Yesterday
        startDate = today.subtract(const Duration(days: 1));
        endDate = today.subtract(const Duration(days: 1));
        break;
      case 2: // Week
        // Monday of current week
        int daysFromMonday = now.weekday - 1;
        startDate = today.subtract(Duration(days: daysFromMonday));
        // Sunday of current week
        endDate = startDate.add(const Duration(days: 6));
        break;
      case 3: // Month
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case 4: // Year
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        break;
      case 5: // Custom
        _showDatePicker(context);
        return;
      default:
        return;
    }
    _fetchTransactions(startDate, endDate);
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      final selectedDate = DateTime(picked.year, picked.month, picked.day);
      _fetchTransactions(selectedDate, selectedDate);
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    Color valueColor, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 12 : 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Future<void> _fetchTransactions(DateTime startDate, DateTime endDate) async {
    if (activeToken == null) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final requestBody = {
        'activeToken': activeToken,
        'startDate': _formatDate(startDate),
        'endDate': _formatDate(endDate),
      };

      print('📡 Calling get_transactions API with: $requestBody');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.getTransactions,
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          validateStatus: (status) {
            return status != null && status < 500;
          },
        ),
      );

      print('✅ Get transactions response: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (jsonResponse['status_code'] == 'S1000') {
          final List<dynamic>? transactionsList = jsonResponse['transactions'];

          // Assign the transactions array to a separate local array
          _transactions =
              transactionsList
                  ?.map((transaction) => Transaction.fromJson(transaction))
                  .toList() ??
              [];

          // Call the transactionSummary function
          transactionSummary(_transactions);
        } else {
          final errorMessage =
              jsonResponse['status_description'] ??
              'Failed to fetch transactions';
          setState(() {
            _isLoading = false;
          });
          SnackbarManager.showError(context, message: errorMessage);
        }
      } else {
        final errorMessage =
            jsonResponse['status_description'] ??
            'Server returned status ${response.statusCode}';
        setState(() {
          _isLoading = false;
        });
        SnackbarManager.showError(context, message: errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during get transactions: $e');
      String errorMessage = 'Error fetching transactions';

      if (e.response != null) {
        print('Response status: ${e.response?.statusCode}');
        print('Response data: ${e.response?.data}');

        if (e.response?.statusCode == 403) {
          errorMessage =
              'Access denied. Please check your permissions or try logging in again.';
        } else if (e.response?.statusCode == 401) {
          errorMessage = 'Authentication failed. Please login again.';
        } else {
          errorMessage =
              e.response?.data?['status_description'] ??
              e.response?.data?['message'] ??
              'Server error (${e.response?.statusCode})';
        }
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Connection timeout. Please check your internet connection.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Receive timeout. Please try again.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage =
            'Connection error. Please check your internet connection.';
      }

      setState(() {
        _isLoading = false;
      });
      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ Unexpected error during get transactions: $e');
      setState(() {
        _isLoading = false;
      });
      SnackbarManager.showError(
        context,
        message: 'An unexpected error occurred: ${e.toString()}',
      );
    }
  }

  void transactionSummary(List<Transaction> transactions) {
    double cashPayment = 0.0;
    double balanceReturned = 0.0;
    int pendingCount = 0;
    int completedCount = 0;
    double preDiscountSales = 0.0;
    double totalDiscounts = 0.0;
    double totalVat = 0.0;
    double totalSales = 0.0;
    double paymentCash = 0.0;
    double paymentCard = 0.0;
    double paymentBank = 0.0;
    double paymentCheque = 0.0;
    double paymentVoucher = 0.0;

    for (var transaction in transactions) {
      // Sum of cashPayment values
      final cashPaymentStr = transaction.cashPayment;
      final cashPaymentValue = double.tryParse(cashPaymentStr) ?? 0.0;
      cashPayment += cashPaymentValue;

      // Payment Summary calculations
      // Cash Payment
      paymentCash += cashPaymentValue;

      // Card Payment
      final cardPaymentStr = transaction.cardPayment;
      final cardPaymentValue = double.tryParse(cardPaymentStr) ?? 0.0;
      paymentCard += cardPaymentValue;

      // Bank Payment
      final bankPaymentStr = transaction.bankPayment;
      final bankPaymentValue = double.tryParse(bankPaymentStr) ?? 0.0;
      paymentBank += bankPaymentValue;

      // Cheque Payment
      final chequePaymentStr = transaction.chequePayment;
      final chequePaymentValue = double.tryParse(chequePaymentStr) ?? 0.0;
      paymentCheque += chequePaymentValue;

      // Voucher Payment
      final voucherPaymentStr = transaction.voucherPayment;
      final voucherPaymentValue = double.tryParse(voucherPaymentStr) ?? 0.0;
      paymentVoucher += voucherPaymentValue;

      // Sum of all positive balance values
      final balanceStr = transaction.balance;
      final balanceValue = double.tryParse(balanceStr) ?? 0.0;
      if (balanceValue > 0) {
        balanceReturned += balanceValue;
      }

      // Count transactions by balance status
      if (balanceValue < 0) {
        pendingCount++;
      } else {
        // balance is zero or positive
        completedCount++;
      }

      // Sales Summary calculations
      // Pre-discount Sales - sum of subTotal
      final subTotalStr = transaction.subTotal;
      final subTotalValue = double.tryParse(subTotalStr) ?? 0.0;
      preDiscountSales += subTotalValue;

      // Total Discounts - sum of discount
      final discountStr = transaction.discount;
      final discountValue = double.tryParse(discountStr) ?? 0.0;
      totalDiscounts += discountValue;

      // Total VAT - sum of vatAmount (if available)
      if (transaction.vatAmount != null) {
        final vatStr = transaction.vatAmount!;
        final vatValue = double.tryParse(vatStr) ?? 0.0;
        totalVat += vatValue;
      }

      // Total Sales - sum of total
      final totalStr = transaction.total;
      final totalValue = double.tryParse(totalStr) ?? 0.0;
      totalSales += totalValue;
    }

    // Calculate Payment Total - sum of all payment types
    final paymentTotal =
        paymentCash +
        paymentCard +
        paymentBank +
        paymentCheque +
        paymentVoucher;

    // Calculate Current Cash in Drawer
    // (Cash Payment + Opening Float if available) - (Balance Returned + Expenses if available)
    final openingFloatValue = _openingFloat != null && _openingFloat != '-'
        ? double.tryParse(_openingFloat!) ?? 0.0
        : 0.0;
    final currentCashInDrawer =
        (cashPayment + openingFloatValue) - (balanceReturned + _expenses);

    // ========== NEW: Calculate Item Sales Summary ==========
    final itemSalesSummary = _calculateItemSalesSummary(transactions);
    // ========== NEW: Calculate Category Sales Summary ==========
    final categorySalesSummary = _calculateCategorySalesSummary(transactions);
    // =======================================================

    setState(() {
      _pendingCount = pendingCount;
      _completedCount = completedCount;
      _totalTransactions = transactions.length;
      _preDiscountSales = preDiscountSales;
      _totalDiscounts = totalDiscounts;
      _totalVat = totalVat;
      _totalSales = totalSales;
      _paymentCash = paymentCash;
      _paymentCard = paymentCard;
      _paymentBank = paymentBank;
      _paymentCheque = paymentCheque;
      _paymentVoucher = paymentVoucher;
      _paymentTotal = paymentTotal;
      _cashPayment = cashPayment;
      _balanceReturned = balanceReturned;
      _currentCashInDrawer = currentCashInDrawer;
      // ========== NEW: Set Item Sales Summary ==========
      _itemSalesSummary = itemSalesSummary;
      // ========== NEW: Set Category Sales Summary ==========
      _categorySalesSummary = categorySalesSummary;
      // =================================================
      _isLoading = false;
    });

    print('Pending: $pendingCount');
    print('Completed: $completedCount');
    print('Total Transactions: ${transactions.length}');
    print('Pre-discount Sales: ${preDiscountSales.toStringAsFixed(2)}');
    print('Total Discounts: ${totalDiscounts.toStringAsFixed(2)}');
    print('Total VAT: ${totalVat.toStringAsFixed(2)}');
    print('Total Sales: ${totalSales.toStringAsFixed(2)}');
    print('Cash Payment: ${paymentCash.toStringAsFixed(2)}');
    print('Card Payment: ${paymentCard.toStringAsFixed(2)}');
    print('Bank Payment: ${paymentBank.toStringAsFixed(2)}');
    print('Cheque Payment: ${paymentCheque.toStringAsFixed(2)}');
    print('Voucher Payment: ${paymentVoucher.toStringAsFixed(2)}');
    print('Payment Total: ${paymentTotal.toStringAsFixed(2)}');
    print('Balance Returned: ${balanceReturned.toStringAsFixed(2)}');
    print('Current Cash in Drawer: ${currentCashInDrawer.toStringAsFixed(2)}');
  }

  // ========== NEW: Method to calculate item sales summary ==========
  // Groups line items by inventoryId (if not null) or itemId (if inventoryId is null)
  // Calculates sum of count and lineTotal for each group
  List<ItemSalesSummary> _calculateItemSalesSummary(
    List<Transaction> transactions,
  ) {
    // Map to store grouped data
    // Key: inventoryId or itemId, Value: ItemSalesSummary
    final Map<String, ItemSalesSummary> groupedItems = {};

    for (var transaction in transactions) {
      for (var lineItem in transaction.lineItems) {
        // Determine grouping key: use inventoryId if available, otherwise use itemId
        final groupKey =
            (lineItem.inventoryId != null && lineItem.inventoryId!.isNotEmpty)
            ? lineItem.inventoryId!
            : lineItem.itemId;

        // Parse count and lineTotal
        final count = double.tryParse(lineItem.count) ?? 0.0;
        final lineTotal = double.tryParse(lineItem.lineTotal) ?? 0.0;

        // Build item name with batch number if available
        String itemName = lineItem.itemName;
        if (lineItem.batchNumber != null && lineItem.batchNumber!.isNotEmpty) {
          itemName += ' (${lineItem.batchNumber})';
        }

        // If this group already exists, accumulate the values
        if (groupedItems.containsKey(groupKey)) {
          groupedItems[groupKey]!.soldAmount += count;
          groupedItems[groupKey]!.totalSales += lineTotal;
        } else {
          // Create new entry
          groupedItems[groupKey] = ItemSalesSummary(
            itemName: itemName,
            soldAmount: count,
            totalSales: lineTotal,
          );
        }
      }
    }

    // Convert map to list and sort by total sales (descending)
    final summaryList = groupedItems.values.toList();
    summaryList.sort((a, b) => b.totalSales.compareTo(a.totalSales));

    return summaryList;
  }

  // ========== NEW: Method to calculate category sales summary ==========
  // Groups line items by categoryName
  // Calculates sum of count and lineTotal for each category
  List<CategorySalesSummary> _calculateCategorySalesSummary(
    List<Transaction> transactions,
  ) {
    // Map to store grouped data
    // Key: categoryName, Value: CategorySalesSummary
    final Map<String, CategorySalesSummary> groupedCategories = {};

    for (var transaction in transactions) {
      for (var lineItem in transaction.lineItems) {
        // Use categoryName as grouping key
        final categoryName = lineItem.categoryName;

        // Parse count and lineTotal
        final count = double.tryParse(lineItem.count) ?? 0.0;
        final lineTotal = double.tryParse(lineItem.lineTotal) ?? 0.0;

        // If this category already exists, accumulate the values
        if (groupedCategories.containsKey(categoryName)) {
          groupedCategories[categoryName]!.soldAmount += count;
          groupedCategories[categoryName]!.totalSales += lineTotal;
        } else {
          // Create new entry
          groupedCategories[categoryName] = CategorySalesSummary(
            categoryName: categoryName,
            soldAmount: count,
            totalSales: lineTotal,
          );
        }
      }
    }

    // Convert map to list and sort by total sales (descending)
    final summaryList = groupedCategories.values.toList();
    summaryList.sort((a, b) => b.totalSales.compareTo(a.totalSales));

    return summaryList;
  }

  // =================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        backgroundColor: Color(0xffd41818),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SizedBox(
              //   width: double.infinity,
              //   child: ToggleButtons(
              //     isSelected: List.generate(
              //       _options.length,
              //       (index) => index == _selectedIndex,
              //     ),
              //     onPressed: _handleDateRangeSelection,
              //     children: _options
              //         .map(
              //           (option) => Padding(
              //             padding: const EdgeInsets.symmetric(
              //               horizontal: 8.0,
              //               vertical: 4.0,
              //             ),
              //             child: Text(
              //               option,
              //               style: const TextStyle(fontSize: 12),
              //             ),
              //           ),
              //         )
              //         .toList(),
              //     borderRadius: BorderRadius.circular(8.0),
              //     selectedColor: Colors.white,
              //     fillColor: Color(0xffd41818),
              //     color: Colors.black87,
              //     constraints: const BoxConstraints(minHeight: 32.0),
              //   ),
              // ),
              Center(
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  alignment: WrapAlignment.center,
                  children: List<Widget>.generate(_options.length, (int index) {
                    return ChoiceChip(
                      label: Text(
                        _options[index],
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedIndex == index ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: _selectedIndex == index,
                      selectedColor: const Color(0xffd41818),
                      backgroundColor: Colors.grey[200],
                      onSelected: (bool selected) {
                        if (selected) {
                          _handleDateRangeSelection(index);
                        }
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        side: BorderSide(
                          color: _selectedIndex == index ? Colors.transparent : Colors.grey[400]!,
                        ),
                      ),
                      showCheckmark: false,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 12.0),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 24.0),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Opening Float Summary',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(height: 14.0),
                                _buildSummaryRow(
                                  'Opening Float',
                                  _openingFloat ?? '-',
                                  Colors.black87,
                                ),
                                // const SizedBox(height: 12.0),
                                _buildSummaryRow(
                                  'Cash Payment',
                                  _cashPayment.toStringAsFixed(2),
                                  Colors.green,
                                ),
                                // const SizedBox(height: 12.0),
                                _buildSummaryRow(
                                  'Expenses',
                                  _expenses.toStringAsFixed(2),
                                  Colors.red,
                                ),
                                // const SizedBox(height: 12.0),
                                _buildSummaryRow(
                                  'Balance Returned',
                                  _balanceReturned.toStringAsFixed(2),
                                  Colors.red,
                                ),
                                // const SizedBox(height: 12.0),
                                _buildSummaryRow(
                                  'Current Cash in Drawer',
                                  _currentCashInDrawer.toStringAsFixed(2),
                                  Colors.black87,
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Transaction Summary',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(height: 14.0),
                                _buildSummaryRow(
                                  'Pending',
                                  '$_pendingCount',
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Completed',
                                  '$_completedCount',
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Total Transactions',
                                  '$_totalTransactions',
                                  Colors.black87,
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sales Summary',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(height: 14.0),
                                _buildSummaryRow(
                                  'Pre-discount Sales',
                                  _preDiscountSales.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Total Discounts',
                                  _totalDiscounts.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Total VAT',
                                  _totalVat.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Total Sales',
                                  _totalSales.toStringAsFixed(2),
                                  Colors.black87,
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Payment Summary',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(height: 14.0),
                                _buildSummaryRow(
                                  'Cash Payment',
                                  _paymentCash.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Card Payment',
                                  _paymentCard.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Bank Payment',
                                  _paymentBank.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Cheque Payment',
                                  _paymentCheque.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Voucher Payment',
                                  _paymentVoucher.toStringAsFixed(2),
                                  Colors.black87,
                                ),
                                _buildSummaryRow(
                                  'Total',
                                  _paymentTotal.toStringAsFixed(2),
                                  Colors.black87,
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ========== NEW: Item Sales Summary Card ==========
                        const SizedBox(height: 4.0),
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Item Sales Summary',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(height: 14.0),
                                // ========== NEW: Item/Category Toggle Buttons ==========
                                SizedBox(
                                  width: double.infinity,
                                  child: ToggleButtons(
                                    isSelected: [
                                      _itemCategorySelectedIndex == 0,
                                      _itemCategorySelectedIndex == 1,
                                    ],
                                    onPressed: (index) {
                                      setState(() {
                                        _itemCategorySelectedIndex = index;
                                      });
                                    },
                                    children: const [
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                          vertical: 4.0,
                                        ),
                                        child: Text(
                                          'Item',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                          vertical: 4.0,
                                        ),
                                        child: Text(
                                          'Category',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                    borderRadius: BorderRadius.circular(8.0),
                                    selectedColor: Colors.white,
                                    fillColor: Color(0xffd41818),
                                    color: Colors.black87,
                                    constraints: const BoxConstraints(
                                      minHeight: 32.0,
                                    ),
                                  ),
                                ),
                                // =======================================================
                                // ========== NEW: Conditional rendering based on selection ==========
                                if (_itemCategorySelectedIndex == 0)
                                  // Display Item Sales Summary
                                  _itemSalesSummary.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8.0,
                                          ),
                                          child: Text(
                                            'No items sold in this period',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        )
                                      // ========== UPDATED: Make DataTable use full width ==========
                                      : SizedBox(
                                          width: double.infinity,
                                          child: DataTable(
                                            headingRowHeight: 40,
                                            dataRowMinHeight: 40,
                                            dataRowMaxHeight: 40,
                                            columnSpacing: 16,
                                            columns: const [
                                              DataColumn(
                                                label: Expanded(
                                                  child: Text(
                                                    'Name',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Sold Amount',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                numeric: true,
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Total Sales',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                numeric: true,
                                              ),
                                            ],
                                            rows: _itemSalesSummary.map((item) {
                                              return DataRow(
                                                cells: [
                                                  DataCell(
                                                    Text(
                                                      item.itemName,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      item.soldAmount
                                                          .toStringAsFixed(0),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      item.totalSales
                                                          .toStringAsFixed(2),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }).toList(),
                                          ),
                                        )

                                // ===============================================================
                                else
                                  // Display Category Sales Summary
                                  _categorySalesSummary.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8.0,
                                          ),
                                          child: Text(
                                            'No categories sold in this period',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        )
                                      // ========== UPDATED: Make DataTable use full width ==========
                                      : SizedBox(
                                          width: double.infinity,
                                          child: DataTable(
                                            headingRowHeight: 40,
                                            dataRowMinHeight: 40,
                                            dataRowMaxHeight: 40,
                                            columnSpacing: 16,
                                            columns: const [
                                              DataColumn(
                                                label: Expanded(
                                                  child: Text(
                                                    'Category Name',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Sold Amount',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                numeric: true,
                                              ),
                                              DataColumn(
                                                label: Text(
                                                  'Total Sales',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                numeric: true,
                                              ),
                                            ],
                                            rows: _categorySalesSummary.map((
                                              category,
                                            ) {
                                              return DataRow(
                                                cells: [
                                                  DataCell(
                                                    Text(
                                                      category.categoryName,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      category.soldAmount
                                                          .toStringAsFixed(0),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      category.totalSales
                                                          .toStringAsFixed(2),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                // ===============================================================
                              ],
                            ),
                          ),
                        ),
                        // ==================================================
                      ],
                    ),
                  ),
                ),
              // Copyright at the bottom
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Text(
                    '©${DateTime.now().year} JPosLite. All rights reserved.',
                    style: TextStyle(fontSize: 12.0, color: Colors.grey[500]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========== NEW: Helper class to store item sales summary data ==========
class ItemSalesSummary {
  final String itemName;
  double soldAmount;
  double totalSales;

  ItemSalesSummary({
    required this.itemName,
    required this.soldAmount,
    required this.totalSales,
  });
}

// ========== NEW: Helper class to store category sales summary data ==========
class CategorySalesSummary {
  final String categoryName;
  double soldAmount;
  double totalSales;

  CategorySalesSummary({
    required this.categoryName,
    required this.soldAmount,
    required this.totalSales,
  });
}

// =========================================================================
