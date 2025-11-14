import 'package:flutter/material.dart';
import 'package:lite/utils/snackbar_manager.dart';

enum PaymentType { cash, card, other, split }

enum OtherPaymentMethod { bankTransfer, cheque, voucher }

enum SplitPaymentMethod { cash, card, bankTransfer, cheque, voucher }

class SplitPaymentData {
  final SplitPaymentMethod paymentMethod;
  final double paidAmount;
  final String? paymentReference;

  SplitPaymentData({
    required this.paymentMethod,
    required this.paidAmount,
    this.paymentReference,
  });
}

class SplitPaymentEntry {
  SplitPaymentMethod? paymentMethod;
  final TextEditingController paidAmountController;
  final TextEditingController paymentReferenceController;

  SplitPaymentEntry({
    this.paymentMethod,
    TextEditingController? paidAmountController,
    TextEditingController? paymentReferenceController,
  })  : paidAmountController = paidAmountController ?? TextEditingController(),
        paymentReferenceController = paymentReferenceController ?? TextEditingController();

  void dispose() {
    paidAmountController.dispose();
    paymentReferenceController.dispose();
  }
}

class CheckoutDialog extends StatefulWidget {
  final double totalAmount;
  final Function(
    double paidAmount,
    double balance,
    PaymentType paymentType,
    OtherPaymentMethod? otherPaymentMethod,
    String? paymentReference,
    List<SplitPaymentData>? splitPayments,
  )? onComplete;

  const CheckoutDialog({
    super.key,
    required this.totalAmount,
    this.onComplete,
  });

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  PaymentType _selectedPaymentType = PaymentType.cash;
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _paymentReferenceController = TextEditingController();
  OtherPaymentMethod? _selectedOtherPaymentMethod;
  bool _isPartialPayment = false;
  double _balance = 0.0;
  List<SplitPaymentEntry> _splitPaymentEntries = [];

  @override
  void initState() {
    super.initState();
    // Set initial paid amount to total
    _paidAmountController.text = widget.totalAmount.toStringAsFixed(2);
    _updateBalance();
    _paidAmountController.addListener(_updateBalance);
    // Initialize split payment entries with Cash and Card
    _splitPaymentEntries = [
      SplitPaymentEntry(paymentMethod: SplitPaymentMethod.cash),
      SplitPaymentEntry(paymentMethod: SplitPaymentMethod.card),
    ];
    // Add listeners for split payment entries
    for (var entry in _splitPaymentEntries) {
      entry.paidAmountController.addListener(_updateBalance);
    }
  }

  @override
  void dispose() {
    _paidAmountController.dispose();
    _paymentReferenceController.dispose();
    for (var entry in _splitPaymentEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _updateBalance() {
    if (_selectedPaymentType == PaymentType.split) {
      // Calculate total from all split payment entries
      double totalPaid = 0.0;
      for (var entry in _splitPaymentEntries) {
        final amount = double.tryParse(entry.paidAmountController.text) ?? 0.0;
        totalPaid += amount;
      }
      setState(() {
        _balance = totalPaid - widget.totalAmount;
      });
    } else {
      final paidAmount = double.tryParse(_paidAmountController.text) ?? 0.0;
      setState(() {
        // Balance is always calculated as Paid Amount - Total Amount
        _balance = paidAmount - widget.totalAmount;
      });
    }
  }

  String? _getValidationMessage() {
    final paidAmount = double.tryParse(_paidAmountController.text) ?? 0.0;
    
    if (_isPartialPayment && paidAmount >= widget.totalAmount) {
      return 'Partial Payment must be less than total.';
    }
    
    if (!_isPartialPayment && paidAmount < widget.totalAmount) {
      return 'Amount is not enough';
    }
    
    return null;
  }

  void _setPaidAmount(double amount) {
    setState(() {
      _paidAmountController.text = amount.toStringAsFixed(2);
    });
  }

  List<double> _getSuggestedAmounts() {
    final List<int> roundToValues = [20, 50, 100, 200, 500, 1000, 5000];
    final Set<double> amounts = {};
    amounts.add(widget.totalAmount);
    
    for (final roundTo in roundToValues) {
      final roundedAmount = (widget.totalAmount / roundTo).ceil() * roundTo;
      // Only add if it's different from total and not already in the set
      if (roundedAmount != widget.totalAmount) {
        amounts.add(roundedAmount.toDouble());
      }
    }
    
    // Convert to list and sort
    final sortedAmounts = amounts.toList()..sort();
    return sortedAmounts;
  }

  void _handleComplete() {
    // Validate Split payment type
    if (_selectedPaymentType == PaymentType.split) {
      double totalPaid = 0.0;
      List<SplitPaymentData> splitPayments = [];

      for (var entry in _splitPaymentEntries) {
        // Check if payment method is selected
        if (entry.paymentMethod == null) {
          SnackbarManager.showError(
            context,
            message: 'Please select a payment method for all entries',
          );
          return;
        }

        // Check if paid amount is entered
        final paidAmount = double.tryParse(entry.paidAmountController.text) ?? 0.0;
        if (entry.paidAmountController.text.trim().isEmpty || paidAmount == 0.0) {
          SnackbarManager.showError(
            context,
            message: 'Please enter the paid amount for all entries',
          );
          return;
        }

        // For non-Cash/Card methods, payment reference is required
        if (entry.paymentMethod != SplitPaymentMethod.cash &&
            entry.paymentMethod != SplitPaymentMethod.card) {
          if (entry.paymentReferenceController.text.trim().isEmpty) {
            SnackbarManager.showError(
              context,
              message: 'Please enter the payment reference for ${_getSplitMethodName(entry.paymentMethod!)}',
            );
            return;
          }
        }

        totalPaid += paidAmount;
        splitPayments.add(SplitPaymentData(
          paymentMethod: entry.paymentMethod!,
          paidAmount: paidAmount,
          paymentReference: entry.paymentReferenceController.text.trim().isNotEmpty
              ? entry.paymentReferenceController.text.trim()
              : null,
        ));
      }

      // Validate total based on Partial Payment toggle
      if (!_isPartialPayment) {
        // Partial Payment is Off: Total Paid Amount must be >= Total Amount
        if (totalPaid < widget.totalAmount) {
          SnackbarManager.showError(
            context,
            message: 'Amount is not enough. Total paid amount must be equal to or greater than total amount.',
          );
          return;
        }
      } else {
        // Partial Payment is On: Total Paid Amount must be < Total Amount
        if (totalPaid >= widget.totalAmount) {
          SnackbarManager.showError(
            context,
            message: 'Partial Payment must be less than total amount.',
          );
          return;
        }
      }

      // Calculate balance
      final balance = totalPaid - widget.totalAmount;

      // Close dialog and call callback
      Navigator.of(context).pop();
      if (widget.onComplete != null) {
        widget.onComplete!(
          totalPaid,
          balance,
          _selectedPaymentType,
          null,
          null,
          splitPayments,
        );
      }
      return;
    }

    // Validation for non-split payment types
    final paidAmount = double.tryParse(_paidAmountController.text) ?? 0.0;
    
    // Check if Paid Amount has been entered
    if (_paidAmountController.text.trim().isEmpty || paidAmount == 0.0) {
      SnackbarManager.showError(
        context,
        message: 'Please enter the paid amount',
      );
      return;
    }

    // Validate Other payment type - both Paid Amount and Payment Reference must be filled
    if (_selectedPaymentType == PaymentType.other) {
      if (_paymentReferenceController.text.trim().isEmpty) {
        SnackbarManager.showError(
          context,
          message: 'Please enter the payment reference',
        );
        return;
      }
    }

    // Validate based on Partial Payment toggle
    if (!_isPartialPayment) {
      // Partial Payment is Off: Paid Amount must be >= Total Amount
      if (paidAmount < widget.totalAmount) {
        SnackbarManager.showError(
          context,
          message: 'Amount is not enough. Paid amount must be equal to or greater than total amount.',
        );
        return;
      }
    } else {
      // Partial Payment is On: Paid Amount must be < Total Amount
      if (paidAmount >= widget.totalAmount) {
        SnackbarManager.showError(
          context,
          message: 'Partial Payment must be less than total amount.',
        );
        return;
      }
    }

    // Calculate balance
    final balance = paidAmount - widget.totalAmount;

    // Close dialog and call callback
    Navigator.of(context).pop();
    if (widget.onComplete != null) {
      widget.onComplete!(
        paidAmount,
        balance,
        _selectedPaymentType,
        _selectedOtherPaymentMethod,
        _paymentReferenceController.text.trim().isNotEmpty
            ? _paymentReferenceController.text.trim()
            : null,
        null,
      );
    }
  }

  String _getSplitMethodName(SplitPaymentMethod method) {
    switch (method) {
      case SplitPaymentMethod.cash:
        return 'Cash';
      case SplitPaymentMethod.card:
        return 'Card';
      case SplitPaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case SplitPaymentMethod.cheque:
        return 'Cheque';
      case SplitPaymentMethod.voucher:
        return 'Voucher';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      elevation: 8.0,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Center(
                child: Text(
                  'CHECKOUT',
                  style: TextStyle(
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16.0),

              // Order Summary Section
              const Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 14.0,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    widget.totalAmount.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),

              // Payment Type Section
              const Text(
                'Payment Type',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4.0),
              Row(
                children: [
                  _buildPaymentTypeButton(
                    PaymentType.cash,
                    'Cash',
                    Icons.money,
                  ),
                  _buildPaymentTypeButton(
                    PaymentType.card,
                    'Card',
                    Icons.credit_card,
                  ),
                  _buildPaymentTypeButton(
                    PaymentType.other,
                    'Other',
                    Icons.receipt,
                  ),
                  _buildPaymentTypeButton(
                    PaymentType.split,
                    'Split',
                    Icons.account_balance_wallet,
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              // Paid Amount Section
              if (_selectedPaymentType == PaymentType.split) ...[
                // Paid Amount Details for Split payment type
                const Text(
                  'Paid Amount Details',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4.0),
                ..._splitPaymentEntries.asMap().entries.map((entry) {
                  final index = entry.key;
                  final splitEntry = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Payment method dropdown on the left
                        Expanded(
                          flex: 1,
                          child: _buildSplitPaymentMethodDropdown(splitEntry, index),
                        ),
                        const SizedBox(width: 8.0),
                        // Paid amount and payment reference fields on the right
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Paid amount field
                              TextField(
                                controller: splitEntry.paidAmountController,
                                style: const TextStyle(fontSize: 16.0),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  hintText: 'Paid amount',
                                  hintStyle: const TextStyle(fontSize: 14.0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12.0,
                                    vertical: 12.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              // Payment reference field below paid amount
                              TextField(
                                controller: splitEntry.paymentReferenceController,
                                enabled: splitEntry.paymentMethod != SplitPaymentMethod.cash &&
                                    splitEntry.paymentMethod != SplitPaymentMethod.card,
                                style: TextStyle(
                                  fontSize: 16.0,
                                  color: splitEntry.paymentMethod == SplitPaymentMethod.cash ||
                                          splitEntry.paymentMethod == SplitPaymentMethod.card
                                      ? Colors.grey[400]
                                      : Colors.black87,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Payment reference',
                                  hintStyle: TextStyle(
                                    fontSize: 12.0,
                                    color: splitEntry.paymentMethod == SplitPaymentMethod.cash ||
                                            splitEntry.paymentMethod == SplitPaymentMethod.card
                                        ? Colors.grey[400]
                                        : Colors.black87,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: BorderSide(color: Colors.grey[600]!),
                                  ),
                                  disabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12.0,
                                    vertical: 12.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ] else if (_selectedPaymentType == PaymentType.other) ...[
                // Paid Amount Details for Other payment type
                const Text(
                  'Paid Amount Details',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4.0),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dropdown for payment method on the left
                    Expanded(
                      flex: 1,
                      child: _buildOtherPaymentMethodDropdown(),
                    ),
                    const SizedBox(width: 8.0),
                    // Paid amount and payment reference fields on the right
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Paid amount field
                          TextField(
                            controller: _paidAmountController,
                            style: const TextStyle(
                              fontSize: 16.0,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: 'Paid amount',
                              hintStyle: const TextStyle(fontSize: 14.0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 12.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          // Payment reference field below paid amount
                          TextField(
                            controller: _paymentReferenceController,
                            style: const TextStyle(
                              fontSize: 16.0,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Payment reference',
                              hintStyle: const TextStyle(fontSize: 12.0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 12.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Validation message
                if (_getValidationMessage() != null) ...[
                  const SizedBox(height: 8.0),
                  Text(
                    _getValidationMessage()!,
                    style: TextStyle(
                      fontSize: 12.0,
                      color: Colors.red[700],
                    ),
                  ),
                ],
              ] else ...[
                // Regular Paid Amount section for Cash, Card, Split
                const Text(
                  'Paid Amount',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4.0),
                TextField(
                  controller: _paidAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'Enter paid amount',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 16.0,
                    ),
                  ),
                ),
                // Validation message
                if (_getValidationMessage() != null) ...[
                  const SizedBox(height: 8.0),
                  Text(
                    _getValidationMessage()!,
                    style: TextStyle(
                      fontSize: 12.0,
                      color: Colors.red[700],
                    ),
                  ),
                ],
                const SizedBox(height: 12.0),
                // Suggested amounts (only show for Cash payment type)
                if (_selectedPaymentType == PaymentType.cash) ...[
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: _getSuggestedAmounts()
                        .map((amount) => _buildSuggestedAmountButton(amount))
                        .toList(),
                  ),
                  // const SizedBox(height: 8.0),
                ],
              ],
              // const SizedBox(height: 24.0),
              // Partial Payment Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Partial Payment',
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Switch(
                    value: _isPartialPayment,
                    onChanged: (value) {
                      setState(() {
                        _isPartialPayment = value;
                        _updateBalance();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8.0),

              // Balance Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'BALANCE',
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    _balance.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: _balance < 0 ? Colors.red[700] : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24.0),

              // Action Buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: Container(
                      height: 50.0,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  // Complete button
                  Expanded(
                    child: Container(
                      height: 50.0,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: TextButton(
                        onPressed: () {
                          _handleComplete();
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: Text(
                          _isPartialPayment ? 'Create' : 'Complete',
                          style: const TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentTypeButton(
    PaymentType type,
    String label,
    IconData icon,
  ) {
    final isSelected = _selectedPaymentType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedPaymentType = type;
            // Set default to Bank Transfer when switching to Other
            if (type == PaymentType.other) {
              _selectedOtherPaymentMethod = OtherPaymentMethod.bankTransfer;
            } else if (type == PaymentType.split) {
              // Initialize split payment entries if empty
              if (_splitPaymentEntries.isEmpty) {
                _splitPaymentEntries = [
                  SplitPaymentEntry(paymentMethod: SplitPaymentMethod.cash),
                  SplitPaymentEntry(paymentMethod: SplitPaymentMethod.card),
                ];
                for (var entry in _splitPaymentEntries) {
                  entry.paidAmountController.addListener(_updateBalance);
                }
              }
            } else {
              // Reset other payment method when switching away from Other
              _selectedOtherPaymentMethod = null;
            }
          });
        },
        child: Container(
          margin: const EdgeInsets.only(right: 4.0),
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.circular(8.0),
            border: isSelected
                ? Border.all(color: Colors.blue.shade700, width: 2.0)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[700],
                size: 28.0,
              ),
              const SizedBox(height: 6.0),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedAmountButton(double amount) {
    // Format amount to remove decimal if it's a whole number
    final formattedAmount = amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toStringAsFixed(2);
    
    return GestureDetector(
      onTap: () => _setPaidAmount(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Text(
          'Rs. $formattedAmount',
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w500,
            color: Colors.grey[800],
          ),
        ),
      ),
    );
  }

  Widget _buildOtherPaymentMethodDropdown() {
    String getMethodName(OtherPaymentMethod? method) {
      if (method == null) return 'Select payment method';
      switch (method) {
        case OtherPaymentMethod.bankTransfer:
          return 'Bank Transfer';
        case OtherPaymentMethod.cheque:
          return 'Cheque';
        case OtherPaymentMethod.voucher:
          return 'Voucher';
      }
    }

    IconData getMethodIcon(OtherPaymentMethod? method) {
      if (method == null) return Icons.account_balance;
      switch (method) {
        case OtherPaymentMethod.bankTransfer:
          return Icons.account_balance;
        case OtherPaymentMethod.cheque:
          return Icons.edit;
        case OtherPaymentMethod.voucher:
          return Icons.confirmation_number;
      }
    }

    return Container(
      // height: 50.0,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue, width: 2.0),
        borderRadius: BorderRadius.circular(8.0),
        color: Colors.blue[50],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<OtherPaymentMethod>(
          value: _selectedOtherPaymentMethod,
          isExpanded: true,
          // contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0),
          // iconSize: 20.0,
          selectedItemBuilder: (BuildContext context) {
            return [
              OtherPaymentMethod.bankTransfer,
              OtherPaymentMethod.cheque,
              OtherPaymentMethod.voucher,
            ].map<Widget>((OtherPaymentMethod method) {
              return Row(
                children: [
                  // Icon(getMethodIcon(method), color: Colors.blue[700]),
                  const SizedBox(width: 8.0),
                  Text(
                    getMethodName(method),
                    style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500,fontSize: 14),
                  ),
                ],
              );
            }).toList();
          },
          hint: Row(
            children: [
              // Icon(getMethodIcon(null), color: Colors.blue[700]),
              const SizedBox(width: 8.0),
              Text(
                getMethodName(null),
                style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500, fontSize: 12),
              ),
            ],
          ),
          items: [
            DropdownMenuItem(
              value: OtherPaymentMethod.bankTransfer,
              child: Row(
                children: [
                  Icon(Icons.account_balance, color: Colors.blue[700]),
                  const SizedBox(width: 8.0),
                  const Text('Bank Transfer'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: OtherPaymentMethod.cheque,
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue[700]),
                  const SizedBox(width: 8.0),
                  const Text('Cheque'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: OtherPaymentMethod.voucher,
              child: Row(
                children: [
                  Icon(Icons.confirmation_number, color: Colors.blue[700]),
                  const SizedBox(width: 8.0),
                  const Text('Voucher'),
                ],
              ),
            ),
          ],
          onChanged: (OtherPaymentMethod? value) {
            setState(() {
              _selectedOtherPaymentMethod = value;
            });
          },
          // padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0),
        ),
      ),
    );
  }

  Widget _buildSplitPaymentMethodDropdown(SplitPaymentEntry entry, int index) {
    // Get all payment methods selected in other entries (excluding current entry)
    final selectedMethodsInOtherEntries = <SplitPaymentMethod>{};
    for (int i = 0; i < _splitPaymentEntries.length; i++) {
      if (i != index && _splitPaymentEntries[i].paymentMethod != null) {
        selectedMethodsInOtherEntries.add(_splitPaymentEntries[i].paymentMethod!);
      }
    }

    String getMethodName(SplitPaymentMethod? method) {
      if (method == null) return 'Select method';
      switch (method) {
        case SplitPaymentMethod.cash:
          return 'Cash';
        case SplitPaymentMethod.card:
          return 'Card';
        case SplitPaymentMethod.bankTransfer:
          return 'Bank Transfer';
        case SplitPaymentMethod.cheque:
          return 'Cheque';
        case SplitPaymentMethod.voucher:
          return 'Voucher';
      }
    }

    IconData getMethodIcon(SplitPaymentMethod? method) {
      if (method == null) return Icons.payment;
      switch (method) {
        case SplitPaymentMethod.cash:
          return Icons.money;
        case SplitPaymentMethod.card:
          return Icons.credit_card;
        case SplitPaymentMethod.bankTransfer:
          return Icons.account_balance;
        case SplitPaymentMethod.cheque:
          return Icons.edit;
        case SplitPaymentMethod.voucher:
          return Icons.confirmation_number;
      }
    }

    final isSelected = entry.paymentMethod != null;
    final color = isSelected ? Colors.blue : Colors.grey[300]!;
    final textColor = isSelected ? Colors.white : Colors.grey[700]!;
    final iconColor = isSelected ? Colors.white : Colors.grey[700]!;

    return Container(
      height: 48.0,
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey[400]!,
          width: 2.0,
        ),
        borderRadius: BorderRadius.circular(8.0),
        color: color,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SplitPaymentMethod>(
          value: entry.paymentMethod,
          isExpanded: true,
          // contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0),
          hint: Row(
            children: [
              Icon(getMethodIcon(entry.paymentMethod), color: iconColor, size: 20.0),
              const SizedBox(width: 8.0),
              Text(
                getMethodName(entry.paymentMethod),
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          items: [
            DropdownMenuItem(
              value: SplitPaymentMethod.cash,
              enabled: !selectedMethodsInOtherEntries.contains(SplitPaymentMethod.cash) ||
                  entry.paymentMethod == SplitPaymentMethod.cash,
              child: Row(
                children: [
                  Icon(
                    Icons.money,
                    color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.cash) &&
                            entry.paymentMethod != SplitPaymentMethod.cash
                        ? Colors.grey[400]
                        : Colors.blue[700],
                    size: 20.0,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Cash',
                    style: TextStyle(
                      color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.cash) &&
                              entry.paymentMethod != SplitPaymentMethod.cash
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            DropdownMenuItem(
              value: SplitPaymentMethod.card,
              enabled: !selectedMethodsInOtherEntries.contains(SplitPaymentMethod.card) ||
                  entry.paymentMethod == SplitPaymentMethod.card,
              child: Row(
                children: [
                  Icon(
                    Icons.credit_card,
                    color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.card) &&
                            entry.paymentMethod != SplitPaymentMethod.card
                        ? Colors.grey[400]
                        : Colors.blue[700],
                    size: 20.0,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Card',
                    style: TextStyle(
                      color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.card) &&
                              entry.paymentMethod != SplitPaymentMethod.card
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            DropdownMenuItem(
              value: SplitPaymentMethod.bankTransfer,
              enabled: !selectedMethodsInOtherEntries.contains(SplitPaymentMethod.bankTransfer) ||
                  entry.paymentMethod == SplitPaymentMethod.bankTransfer,
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance,
                    color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.bankTransfer) &&
                            entry.paymentMethod != SplitPaymentMethod.bankTransfer
                        ? Colors.grey[400]
                        : Colors.blue[700],
                    size: 20.0,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Bank Transfer',
                    style: TextStyle(
                      color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.bankTransfer) &&
                              entry.paymentMethod != SplitPaymentMethod.bankTransfer
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            DropdownMenuItem(
              value: SplitPaymentMethod.cheque,
              enabled: !selectedMethodsInOtherEntries.contains(SplitPaymentMethod.cheque) ||
                  entry.paymentMethod == SplitPaymentMethod.cheque,
              child: Row(
                children: [
                  Icon(
                    Icons.edit,
                    color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.cheque) &&
                            entry.paymentMethod != SplitPaymentMethod.cheque
                        ? Colors.grey[400]
                        : Colors.blue[700],
                    size: 20.0,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Cheque',
                    style: TextStyle(
                      color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.cheque) &&
                              entry.paymentMethod != SplitPaymentMethod.cheque
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            DropdownMenuItem(
              value: SplitPaymentMethod.voucher,
              enabled: !selectedMethodsInOtherEntries.contains(SplitPaymentMethod.voucher) ||
                  entry.paymentMethod == SplitPaymentMethod.voucher,
              child: Row(
                children: [
                  Icon(
                    Icons.confirmation_number,
                    color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.voucher) &&
                            entry.paymentMethod != SplitPaymentMethod.voucher
                        ? Colors.grey[400]
                        : Colors.blue[700],
                    size: 20.0,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Voucher',
                    style: TextStyle(
                      color: selectedMethodsInOtherEntries.contains(SplitPaymentMethod.voucher) &&
                              entry.paymentMethod != SplitPaymentMethod.voucher
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
          onChanged: (SplitPaymentMethod? value) {
            setState(() {
              entry.paymentMethod = value;
            });
          },
          selectedItemBuilder: (BuildContext context) {
            return [
              SplitPaymentMethod.cash,
              SplitPaymentMethod.card,
              SplitPaymentMethod.bankTransfer,
              SplitPaymentMethod.cheque,
              SplitPaymentMethod.voucher,
            ].map<Widget>((SplitPaymentMethod method) {
              return Row(
                children: [
                  // Icon(getMethodIcon(method), color: iconColor, size: 20.0),
                  const SizedBox(width: 8.0),
                  Text(
                    getMethodName(method),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              );
            }).toList();
          },
          icon: Icon(Icons.arrow_drop_down, color: iconColor),
        ),
      ),
    );
  }
}

