import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite/model/transaction.dart';
import 'package:lite/widgets/checkout_dialog.dart';
import 'package:lite/utils/app_configs.dart';
import 'package:lite/utils/snackbar_manager.dart';
import 'package:lite/utils/bill_printer_service.dart';
import 'package:lite/api/endpoints.dart';

class TransactionDetailsDialog extends StatefulWidget {
  final Transaction transaction;
  final String Function(String) formatOrderDate;
  final VoidCallback? onPaymentComplete;

  const TransactionDetailsDialog({
    super.key,
    required this.transaction,
    required this.formatOrderDate,
    this.onPaymentComplete,
  });

  @override
  State<TransactionDetailsDialog> createState() => _TransactionDetailsDialogState();

  static void show({
    required BuildContext context,
    required Transaction transaction,
    required String Function(String) formatOrderDate,
    VoidCallback? onPaymentComplete,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return TransactionDetailsDialog(
          transaction: transaction,
          formatOrderDate: formatOrderDate,
          onPaymentComplete: onPaymentComplete,
        );
      },
    );
  }
}

class _TransactionDetailsDialogState extends State<TransactionDetailsDialog> {
  bool _isLoading = false;
  String? _businessType;

  Transaction get transaction => widget.transaction;
  String Function(String) get formatOrderDate => widget.formatOrderDate;

  @override
  void initState() {
    super.initState();
    _loadBusinessType();
  }

  Future<void> _loadBusinessType() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _businessType = prefs.getString('businessType');
    });
  }

  bool _shouldDisplayValue(dynamic value) {
    if (value == null) return false;
    if (value is String) {
      if (value.isEmpty) return false;
      // Check if it's a numeric string equal to 0 or 0.00
      final numValue = double.tryParse(value);
      if (numValue != null && numValue == 0) return false;
      return true;
    }
    if (value is num) {
      return value != 0;
    }
    return true;
  }

  String _formatFieldName(String fieldName) {
    // Convert camelCase to Title Case
    String formatted = fieldName.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(0)}',
    );
    formatted = formatted.trim();
    // Capitalize first letter of each word
    return formatted.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
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

  String _getDiscountLabel(Transaction transaction) {
    // Add percentage if available and greater than 0
    if (transaction.totalDiscountPercentage != null && 
        transaction.totalDiscountPercentage!.isNotEmpty) {
      final percentage = double.tryParse(transaction.totalDiscountPercentage!) ?? 0.0;
      if (percentage > 0) {
        return 'Discount ${percentage.toStringAsFixed(0)}%';
      }
    }
    return 'Discount';
  }

  Future<void> _completePartialTransaction({
    required double paidAmount,
    required double balance,
    required PaymentType paymentType,
    OtherPaymentMethod? otherPaymentMethod,
    String? paymentReference,
    List<SplitPaymentData>? splitPayments,
  }) async {
    // Get active token
    final prefs = await SharedPreferences.getInstance();
    final activeToken = prefs.getString('activeToken');

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

      // Set payment amounts based on payment type
      double cashPaymentAmount = 0.0;
      double cardPaymentAmount = 0.0;
      double bankPaymentAmount = 0.0;
      double chequePaymentAmount = 0.0;
      double voucherPaymentAmount = 0.0;
      String? paymentReferenceBank;
      String? paymentReferenceCheque;
      String? paymentReferenceVoucher;

      if (paymentType == PaymentType.split && splitPayments != null) {
        // Calculate split payment amounts
        for (var splitPayment in splitPayments) {
          switch (splitPayment.paymentMethod) {
            case SplitPaymentMethod.cash:
              cashPaymentAmount += splitPayment.paidAmount;
              break;
            case SplitPaymentMethod.card:
              cardPaymentAmount += splitPayment.paidAmount;
              break;
            case SplitPaymentMethod.bankTransfer:
              bankPaymentAmount += splitPayment.paidAmount;
              paymentReferenceBank = splitPayment.paymentReference;
              break;
            case SplitPaymentMethod.cheque:
              chequePaymentAmount += splitPayment.paidAmount;
              paymentReferenceCheque = splitPayment.paymentReference;
              break;
            case SplitPaymentMethod.voucher:
              voucherPaymentAmount += splitPayment.paidAmount;
              paymentReferenceVoucher = splitPayment.paymentReference;
              break;
          }
        }
      } else {
        // Non-split payment types
        cashPaymentAmount = paymentType == PaymentType.cash ? paidAmount : 0.0;
        cardPaymentAmount = paymentType == PaymentType.card ? paidAmount : 0.0;

        // Set other payment type amounts and references
        if (paymentType == PaymentType.other) {
          if (otherPaymentMethod == OtherPaymentMethod.bankTransfer) {
            bankPaymentAmount = paidAmount;
            paymentReferenceBank = paymentReference;
          } else if (otherPaymentMethod == OtherPaymentMethod.cheque) {
            chequePaymentAmount = paidAmount;
            paymentReferenceCheque = paymentReference;
          } else if (otherPaymentMethod == OtherPaymentMethod.voucher) {
            voucherPaymentAmount = paidAmount;
            paymentReferenceVoucher = paymentReference;
          }
        }
      }

      final requestBody = {
        "activeToken": activeToken,
        "id": transaction.id,
        "balance": balance.toStringAsFixed(2),
        "cardPayment": cardPaymentAmount > 0 ? cardPaymentAmount.toStringAsFixed(2) : "0.0",
        "cashPayment": cashPaymentAmount > 0 ? cashPaymentAmount.toStringAsFixed(2) : "0.0",
        "bankPayment": bankPaymentAmount > 0 ? bankPaymentAmount.toStringAsFixed(2) : "0.0",
        "chequePayment": chequePaymentAmount > 0 ? chequePaymentAmount.toStringAsFixed(2) : "0.0",
        "voucherPayment": voucherPaymentAmount > 0 ? voucherPaymentAmount.toStringAsFixed(2) : "0.0",
        "paymentReferenceBank": paymentReferenceBank?.isNotEmpty == true ? paymentReferenceBank : null,
        "paymentReferenceCheque": paymentReferenceCheque?.isNotEmpty == true ? paymentReferenceCheque : null,
        "paymentReferenceVoucher": paymentReferenceVoucher?.isNotEmpty == true ? paymentReferenceVoucher : null,
      };

      print('📤 Calling complete_partial_transaction API');
      print('Request body: $requestBody');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.completePartialTransaction,
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

      print('✅ Complete partial transaction response: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          // Store callback before closing dialog
          final callback = widget.onPaymentComplete;
          
          // Show success message before closing dialog
          SnackbarManager.showSuccess(
            context,
            message: 'Payment completed successfully!',
          );
          
          // Close the transaction dialog
          Navigator.of(context).pop();
          
          // Call the callback to refresh the transaction list after dialog is closed
          Future.delayed(const Duration(milliseconds: 100), () {
            if (callback != null) {
              callback();
            }
          });
        }
      } else {
        final errorMessage =
            jsonResponse?['status_description'] ??
                jsonResponse?['message'] ??
                'Server returned status ${response.statusCode}';
        throw Exception(errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during partial transaction: $e');
      String errorMessage = 'Error completing payment';

      if (e.response != null) {
        print('Response status: ${e.response?.statusCode}');
        print('Response data: ${e.response?.data}');

        if (e.response?.statusCode == 403) {
          errorMessage =
              'Access denied. Please check your permissions or try logging in again.';
        } else if (e.response?.statusCode == 401) {
          errorMessage = 'Unauthorized. Please login again.';
        } else {
          final responseData = e.response?.data;
          errorMessage = responseData?['status_description'] ??
              responseData?['message'] ??
              'Error completing payment';
        }
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Connection timeout. Please check your internet connection.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = 'Connection error. Please check your internet connection.';
      }

      if (mounted) {
        SnackbarManager.showError(
          context,
          message: errorMessage,
        );
      }
    } catch (e) {
      print('❌ Unexpected error: $e');
      if (mounted) {
        SnackbarManager.showError(
          context,
          message: 'An unexpected error occurred: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePrint() async {
    setState(() {
      _isLoading = true;
    });

    await BillPrinterService.printTransaction(
      context: context,
      transaction: transaction,
      onSuccess: () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
      onError: () {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.0),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modern Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xffd41818),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.receipt_long,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Transaction',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print, color: Colors.white, size: 24),
                        onPressed: _isLoading ? null : _handlePrint,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Print',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Invoice Header Card
                    _buildSectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#${transaction.transactionId}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xffd41818),
                                    ),
                                  ),
                                ],
                              ),
                              if (_shouldDisplayValue(transaction.status) && _businessType == 'ONLINE_FOOD')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: transaction.status == 'PENDING'
                                        ? Colors.orange.withOpacity(0.1)
                                        : Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: transaction.status == 'PENDING'
                                          ? Colors.orange
                                          : Colors.green,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    transaction.status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: transaction.status == 'PENDING'
                                          ? Colors.orange.shade700
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_shouldDisplayValue(transaction.orderDate)) ...[
                            // const SizedBox(height: 12),
                            // const Divider(height: 1),
                            // const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                                const SizedBox(width: 8),
                                Text(
                                  formatOrderDate(transaction.orderDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Customer Section
                    _buildSectionCard(
                      title: 'Customer Information',
                      icon: Icons.person,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildModernDetailRow(
                                  'Name',
                                  _shouldDisplayValue(transaction.customerName)
                                      ? transaction.customerName
                                      : 'GUEST',
                                  icon: Icons.badge,
                                ),
                              ),
                              if (_shouldDisplayValue(transaction.contactNumber)) ...[
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildModernDetailRow(
                                    'Contact',
                                    transaction.contactNumber,
                                    icon: Icons.phone,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_shouldDisplayValue(transaction.note))
                            _buildModernDetailRow(
                              'Note',
                              transaction.note.toString(),
                              icon: Icons.note,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Order Summary Section
                    _buildSectionCard(
                      title: 'Order Summary',
                      icon: Icons.shopping_cart,
                      child: Column(
                        children: [
                          if (_shouldDisplayValue(transaction.subTotal))
                            _buildSummaryRow('Subtotal', 'Rs. ${transaction.subTotal}'),
                          if (_shouldDisplayValue(transaction.discount))
                            _buildSummaryRow(
                              _getDiscountLabel(transaction),
                              'Rs. ${transaction.discount}',
                            ),
                          if (_shouldDisplayValue(transaction.vatAmount))
                            _buildSummaryRow('VAT', 'Rs. ${transaction.vatAmount}'),
                          if (_shouldDisplayValue(transaction.total)) ...[
                            const Divider(height: 8),
                            _buildSummaryRow(
                              'Total',
                              'Rs. ${transaction.total}',
                              isTotal: true,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Payment Details Section
                    _buildSectionCard(
                      title: 'Payment Details',
                      icon: Icons.payment,
                      child: Column(
                        children: [
                          if (_shouldDisplayValue(transaction.cashPayment))
                            _buildPaymentRow('Cash', transaction.cashPayment, Icons.money),
                          if (_shouldDisplayValue(transaction.cardPayment))
                            _buildPaymentRow('Card', transaction.cardPayment, Icons.credit_card),
                          if (_shouldDisplayValue(transaction.bankPayment))
                            _buildPaymentRow(
                              'Bank Transfer',
                              transaction.bankPayment,
                              Icons.account_balance,
                              reference: transaction.paymentReferenceBank,
                            ),
                          if (_shouldDisplayValue(transaction.chequePayment))
                            _buildPaymentRow(
                              'Cheque',
                              transaction.chequePayment,
                              Icons.description,
                              reference: transaction.paymentReferenceCheque,
                            ),
                          if (_shouldDisplayValue(transaction.voucherPayment))
                            _buildPaymentRow(
                              'Voucher',
                              transaction.voucherPayment,
                              Icons.card_giftcard,
                              reference: transaction.paymentReferenceVoucher,
                            ),
                          if (_shouldDisplayValue(transaction.balance)) ...[
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Balance',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red,
                                  ),
                                ),
                                Text(
                                  'Rs. ${transaction.balance}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            // Only show Pay button if balance is negative
                            if (_getBalance(transaction) != null) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : () {
                                    final positiveBalance = _getBalance(transaction);
                                    if (positiveBalance != null) {
                                      final balanceAmount = double.tryParse(positiveBalance) ?? 0.0;
                                      if (balanceAmount > 0) {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: true,
                                          builder: (BuildContext context) {
                                            return CheckoutDialog(
                                              totalAmount: balanceAmount,
                                              onComplete: (paidAmount, balance, paymentType, otherPaymentMethod, paymentReference, splitPayments) {
                                                // Note: CheckoutDialog already closes itself before calling onComplete
                                                // So we don't need to pop here - just call the API
                                                _completePartialTransaction(
                                                  paidAmount: paidAmount,
                                                  balance: balance,
                                                  paymentType: paymentType,
                                                  otherPaymentMethod: otherPaymentMethod,
                                                  paymentReference: paymentReference,
                                                  splitPayments: splitPayments,
                                                );
                                              },
                                            );
                                          },
                                        );
                                      }
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Text(
                                          'Pay',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Line Items Section
                    _buildSectionCard(
                      title: 'Items (${transaction.lineItems.length})',
                      icon: Icons.list,
                      child: transaction.lineItems.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  'No items found',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: transaction.lineItems.length,
                              itemBuilder: (context, index) {
                                final item = transaction.lineItems[index];
                                return _buildLineItemCard(item, index);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    String? title,
    IconData? icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8,horizontal: 16),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: const Color(0xffd41818)),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey[300]),
          ],
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8,horizontal: 8),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildModernDetailRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                // const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: isTotal ? Colors.green : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(String method, String amount, IconData icon, {String? reference}) {
    String displayMethod = method;
    if (reference != null && reference.isNotEmpty) {
      displayMethod = '$method (Ref - $reference)';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xffd41818).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: const Color(0xffd41818)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayMethod,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            'Rs. $amount',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 30),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItemCard(LineItem item, int index) {
    return Container(
      margin: EdgeInsets.only(bottom: index < transaction.lineItems.length - 1 ? 12 : 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_shouldDisplayValue(item.itemName))
                      Text(
                        item.itemName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (_shouldDisplayValue(item.categoryName)) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.categoryName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_shouldDisplayValue(item.lineTotal))
                Text(
                  'Rs. ${item.lineTotal}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_shouldDisplayValue(item.count))
                _buildItemChip('Qty: ${item.count}'),
              if (_shouldDisplayValue(item.salesPrice))
                _buildItemChip('Price: Rs. ${item.salesPrice}'),
              if (item.batchNumber != null && item.batchNumber!.isNotEmpty)
                _buildItemChip('Batch: ${item.batchNumber}'),
            ],
          ),
          if (_shouldDisplayValue(item.discount) ||
              _shouldDisplayValue(item.discountPercentage)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_shouldDisplayValue(item.discount))
                  _buildItemChip('Discount: Rs. ${item.discount}', isDiscount: true),
                if (_shouldDisplayValue(item.discountPercentage))
                  _buildItemChip('${item.discountPercentage}%', isDiscount: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemChip(String label, {bool isDiscount = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDiscount ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isDiscount ? Colors.orange.shade700 : Colors.blue.shade700,
        ),
      ),
    );
  }
}

