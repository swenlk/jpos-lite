import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite/api/endpoints.dart';
import 'package:lite/utils/app_configs.dart';
import 'package:lite/utils/snackbar_manager.dart';
import 'package:lite/model/transaction.dart';
import 'package:lite/widgets/transaction_details_dialog.dart';

class PendingTransactionPage extends StatefulWidget {
  const PendingTransactionPage({super.key});

  @override
  State<PendingTransactionPage> createState() => _PendingTransactionPageState();
}

class _PendingTransactionPageState extends State<PendingTransactionPage> {
  String? activeToken;
  List<Transaction> _transactions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadActiveToken();
  }

  Future<void> _loadActiveToken() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      activeToken = prefs.getString('activeToken');
    });
    // Load transactions after token is loaded
    if (activeToken != null) {
      _loadPendingTransactions();
    }
  }

  String _formatOrderDate(String orderDate) {
    try {
      // Handle format: "Tue, 11 Nov 2025 00:00:00 GMT"
      // Remove "GMT" and day name prefix (e.g., "Tue, ")
      String dateStr = orderDate.replaceAll(' GMT', '');
      
      // Remove day name if present (e.g., "Tue, " or "Tuesday, ")
      if (dateStr.contains(', ')) {
        dateStr = dateStr.split(', ').skip(1).join(', ');
      }
      
      // Parse the date string manually to handle month names
      // Format: "11 Nov 2025 00:00:00"
      final parts = dateStr.trim().split(' ');
      if (parts.length >= 3) {
        final day = int.parse(parts[0]);
        final monthName = parts[1];
        final year = int.parse(parts[2]);
        
        // Map month names to numbers
        final monthMap = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
        };
        
        final month = monthMap[monthName] ?? 1;
        
        // Format to yyyy-MM-dd
        return '${year.toString()}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      } else {
        // Fallback: try DateTime.parse
        final dateTime = DateTime.parse(dateStr);
        return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      // If parsing fails, return the original string
      print('Error parsing order date: $e');
      return orderDate;
    }
  }

  Future<void> _loadPendingTransactions() async {
    if (activeToken == null) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _transactions = [];
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final requestBody = {
        'activeToken': activeToken,
      };

      print('📡 Calling get_pending_transactions API with: $requestBody');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.getPendingTransactions,
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

      print('✅ Get pending transactions response: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (jsonResponse['status_code'] == 'S1000') {
          final List<dynamic>? transactionsList = jsonResponse['transactions'];
          setState(() {
            _transactions = transactionsList
                    ?.map((transaction) => Transaction.fromJson(transaction))
                    .toList() ??
                [];
            _isLoading = false;
          });

          if (_transactions.isEmpty) {
            SnackbarManager.showSuccess(
              context,
              message: 'No pending transactions found.',
            );
          } else {
            SnackbarManager.showSuccess(
              context,
              message: 'Found ${_transactions.length} pending transaction(s)',
            );
          }
        } else {
          final errorMessage = jsonResponse['status_description'] ??
              'Failed to fetch pending transactions';
          throw Exception(errorMessage);
        }
      } else {
        final errorMessage = jsonResponse['status_description'] ??
            'Server returned status ${response.statusCode}';
        throw Exception(errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during get pending transactions: $e');
      String errorMessage = 'Error fetching pending transactions';

      if (e.response != null) {
        print('Response status: ${e.response?.statusCode}');
        print('Response data: ${e.response?.data}');

        if (e.response?.statusCode == 403) {
          errorMessage =
              'Access denied. Please check your permissions or try logging in again.';
        } else if (e.response?.statusCode == 401) {
          errorMessage = 'Authentication failed. Please login again.';
        } else {
          errorMessage = e.response?.data?['status_description'] ??
              e.response?.data?['message'] ??
              'Server error (${e.response?.statusCode})';
        }
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Connection timeout. Please check your internet connection.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Request timeout. Please try again.';
      } else {
        errorMessage = 'Network error: ${e.message}';
      }

      setState(() {
        _isLoading = false;
      });

      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ General error during get pending transactions: $e');
      setState(() {
        _isLoading = false;
      });
      SnackbarManager.showError(context, message: 'Unexpected error: $e');
    }
  }

  String? _getBalance(Transaction transaction) {
    // Handle balance: only show if negative, and convert to positive
    if (transaction.balance.isNotEmpty && transaction.balance != '0.00') {
      try {
        final balanceValue = double.parse(transaction.balance);
        if (balanceValue < 0) {
          // Convert negative to positive
          final positiveBalance = balanceValue.abs();
          return positiveBalance.toStringAsFixed(2);
        }
        // If balance is positive, don't show it
      } catch (e) {
        // If parsing fails, skip balance
        print('Error parsing balance: $e');
      }
    }
    return null;
  }

  List<String> _getPaymentMethods(Transaction transaction) {
    List<String> paymentMethods = [];
    if (transaction.bankPayment.isNotEmpty && transaction.bankPayment != '0.00') {
      String bankInfo = 'Bank Transfer: ${transaction.bankPayment}';
      if (transaction.paymentReferenceBank != null &&
          transaction.paymentReferenceBank!.isNotEmpty) {
        bankInfo += ' (Ref: ${transaction.paymentReferenceBank})';
      }
      paymentMethods.add(bankInfo);
    }
    if (transaction.cardPayment.isNotEmpty && transaction.cardPayment != '0.00') {
      paymentMethods.add('Card: ${transaction.cardPayment}');
    }
    if (transaction.cashPayment.isNotEmpty && transaction.cashPayment != '0.00') {
      paymentMethods.add('Cash: ${transaction.cashPayment}');
    }
    if (transaction.chequePayment.isNotEmpty && transaction.chequePayment != '0.00') {
      String chequeInfo = 'Cheque: ${transaction.chequePayment}';
      if (transaction.paymentReferenceCheque != null &&
          transaction.paymentReferenceCheque!.isNotEmpty) {
        chequeInfo += ' (Ref: ${transaction.paymentReferenceCheque})';
      }
      paymentMethods.add(chequeInfo);
    }
    if (transaction.voucherPayment.isNotEmpty && transaction.voucherPayment != '0.00') {
      String voucherInfo = 'Voucher: ${transaction.voucherPayment}';
      if (transaction.paymentReferenceVoucher != null &&
          transaction.paymentReferenceVoucher!.isNotEmpty) {
        voucherInfo += ' (Ref: ${transaction.paymentReferenceVoucher})';
      }
      paymentMethods.add(voucherInfo);
    }
    if (transaction.vatAmount != null &&
        transaction.vatAmount!.isNotEmpty &&
        transaction.vatAmount != '0.00') {
      paymentMethods.add('VAT: ${transaction.vatAmount}');
    }

    return paymentMethods;
  }

  Widget _buildCompactInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xffd41818),
        foregroundColor: Colors.white,
        title: const Text('Pending Payments'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _transactions.isEmpty
                ? const Center(
                    child: Text(
                      'No pending transactions found',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = _transactions[index];
                      final paymentMethods = _getPaymentMethods(transaction);
                      final balance = _getBalance(transaction);

                      return InkWell(
                        onTap: () {
                          TransactionDetailsDialog.show(
                            context: context,
                            transaction: transaction,
                            formatOrderDate: _formatOrderDate,
                            onPaymentComplete: _loadPendingTransactions,
                          );
                        },
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // First row: Order Date and Transaction ID
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildCompactInfo(
                                        'Order Date',
                                        _formatOrderDate(
                                          transaction.orderDate.isNotEmpty
                                              ? transaction.orderDate
                                              : transaction.createdDate,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildCompactInfo('Bill Number', transaction.transactionId),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Second row: Customer Name and Total
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildCompactInfo(
                                        'Customer Name',
                                        transaction.customerName.isNotEmpty
                                            ? transaction.customerName
                                            : 'GUEST',
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildCompactInfo('Bill Amount', 'Rs. ${transaction.total}'),
                                    ),
                                  ],
                                ),
                                if (paymentMethods.isNotEmpty || balance != null) ...[
                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 6),
                                  // Paid By header with Balance on the right
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Paid By:',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (balance != null)
                                        Row(
                                          children: [
                                            const Text(
                                              'Balance: ',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              balance,
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  ...paymentMethods.map((method) => Padding(
                                        padding: const EdgeInsets.only(
                                          top: 2,
                                          left: 4,
                                        ),
                                        child: Text(
                                          method,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      )),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
