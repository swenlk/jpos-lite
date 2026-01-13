import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lite/model/transaction.dart';
import 'package:lite/model/cart_item.dart';
import 'package:lite/model/customer.dart';
import 'package:lite/widgets/print_dialog.dart';
import 'package:lite/utils/print_service.dart';
import 'package:lite/utils/snackbar_manager.dart';
import 'package:flutter/material.dart';

class BillPrinterService {
  static String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'pm' : 'am';
    return '$day-$month-$year $hour:$minute $period';
  }

  static String _formatDateOnly(String? dateStr) {
    // If dateStr is null or empty (after trimming), use current date
    if (dateStr == null || dateStr.trim().isEmpty) {
      final now = DateTime.now();
      return '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    }
    
    final trimmedDateStr = dateStr.trim();
    
    try {
      final dateParts = trimmedDateStr.split('-');
      if (dateParts.length == 3) {
        // Check if it's already in dd-MM-yyyy format (first part is 1-31)
        final firstPart = int.tryParse(dateParts[0]);
        final thirdPart = int.tryParse(dateParts[2]);
        
        // If first part is 1-31 and third part is 4 digits (year), it's likely dd-MM-yyyy
        if (firstPart != null && firstPart >= 1 && firstPart <= 31 && 
            thirdPart != null && thirdPart >= 1000 && thirdPart <= 9999) {
          // Already in dd-MM-yyyy format
          return trimmedDateStr;
        }
        
        // Check if third part is 1-31 (likely yyyy-MM-dd format)
        if (thirdPart != null && thirdPart >= 1 && thirdPart <= 31) {
          // Assume yyyy-MM-dd format and convert to dd-MM-yyyy
          return '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}';
        }
        
        // If first part is 4 digits, assume yyyy-MM-dd
        if (firstPart != null && firstPart >= 1000 && firstPart <= 9999) {
          return '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}';
        }
      }
      
      // Try to parse as DateTime and format
      final date = DateTime.parse(trimmedDateStr);
      return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
    } catch (e) {
      // If parsing fails, log and use current date
      print('⚠️ Failed to parse orderDate "$trimmedDateStr": $e');
      final now = DateTime.now();
      return '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    }
  }

  /// Format order date from transaction, returning null if it cannot be parsed
  /// This ensures we don't use the current date as a fallback for order dates
  static String? _formatOrderDateOnly(String? dateStr) {
    // If dateStr is null or empty, return null (don't print)
    if (dateStr == null || dateStr.trim().isEmpty) {
      return null;
    }
    
    final trimmedDateStr = dateStr.trim();
    
    try {
      // First, try to handle GMT format with month names (e.g., "Tue, 11 Nov 2025 00:00:00 GMT")
      if (trimmedDateStr.contains('GMT') || trimmedDateStr.contains(',')) {
        // Remove "GMT" and day name prefix (e.g., "Tue, ")
        String processedDateStr = trimmedDateStr.replaceAll(' GMT', '');
        
        // Remove day name if present (e.g., "Tue, " or "Tuesday, ")
        if (processedDateStr.contains(', ')) {
          processedDateStr = processedDateStr.split(', ').skip(1).join(', ');
        }
        
        // Parse the date string manually to handle month names
        // Format: "11 Nov 2025 00:00:00"
        final parts = processedDateStr.trim().split(' ');
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
          
          // Format to dd-MM-yyyy for printing
          return '${day.toString().padLeft(2, '0')}-${month.toString().padLeft(2, '0')}-${year}';
        }
      }
      
      // Try dash-separated formats (yyyy-MM-dd or dd-MM-yyyy)
      final dateParts = trimmedDateStr.split('-');
      if (dateParts.length == 3) {
        // Check if it's already in dd-MM-yyyy format (first part is 1-31)
        final firstPart = int.tryParse(dateParts[0]);
        final thirdPart = int.tryParse(dateParts[2]);
        
        // If first part is 1-31 and third part is 4 digits (year), it's likely dd-MM-yyyy
        if (firstPart != null && firstPart >= 1 && firstPart <= 31 && 
            thirdPart != null && thirdPart >= 1000 && thirdPart <= 9999) {
          // Already in dd-MM-yyyy format
          return trimmedDateStr;
        }
        
        // Check if third part is 1-31 (likely yyyy-MM-dd format)
        if (thirdPart != null && thirdPart >= 1 && thirdPart <= 31) {
          // Assume yyyy-MM-dd format and convert to dd-MM-yyyy
          return '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}';
        }
        
        // If first part is 4 digits, assume yyyy-MM-dd
        if (firstPart != null && firstPart >= 1000 && firstPart <= 9999) {
          return '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}';
        }
      }
      
      // Try to parse as DateTime and format
      final date = DateTime.parse(trimmedDateStr);
      return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
    } catch (e) {
      // If parsing fails, return null (don't print order date)
      print('⚠️ Failed to parse orderDate "$trimmedDateStr": $e');
      return null;
    }
  }

  /// Generate bill content from a Transaction object
  static String generateBillContentFromTransaction(Transaction transaction) {
    StringBuffer content = StringBuffer();
    int totalWidth = 32; // Total width for alignment

    content.writeln('-' * totalWidth);
    // Customer info
    String customerStr = transaction.customerName.isNotEmpty 
        ? transaction.customerName 
        : 'GUEST';
    int customerSpace = totalWidth - customerStr.length - ('Customer:').length;
    content.writeln('Customer:' + ' ' * customerSpace + customerStr);

    // Transaction ID
    String transactionIdLabel = 'Bill No:';
    int transactionIdSpace = totalWidth - transactionIdLabel.length - transaction.transactionId.length;
    content.writeln(transactionIdLabel + ' ' * transactionIdSpace + transaction.transactionId);

    // Order Date (if available and valid)
    String? orderDateStr = _formatOrderDateOnly(transaction.orderDate);
    if (orderDateStr != null) {
      String orderDateLabel = 'Order Date:';
      int orderDateSpace = totalWidth - orderDateLabel.length - orderDateStr.length;
      content.writeln(orderDateLabel + ' ' * orderDateSpace + orderDateStr);
    }

    // Time (current) in dd-MM-yyyy h:mm a
    final now = DateTime.now();
    final timeStr = _formatDateTime(now);
    String dateTimeTitle = 'Time:';
    int dateTimeTotalSpaces =
        (totalWidth - dateTimeTitle.length - timeStr.length);
    content.writeln(dateTimeTitle + ' ' * dateTimeTotalSpaces + timeStr);

    // Items
    content.writeln('-' * totalWidth);
    for (var item in transaction.lineItems) {
      String? batchNoStr = '';
      if (item.batchNumber != null && item.batchNumber!.isNotEmpty) {
        batchNoStr = '-${item.batchNumber}';
      }

      String displayNameStr = item.itemName + batchNoStr;
      String totalStr = item.lineTotal;
      int displayNameSpace = totalWidth - displayNameStr.length;
      content.writeln(displayNameStr + ' ' * displayNameSpace);

      // Quantity and price
      String qtyPriceStr = '(${item.count} x ${item.salesPrice})';
      int qtyPriceSpace = totalWidth - qtyPriceStr.length - totalStr.length;
      content.writeln(qtyPriceStr + ' ' * qtyPriceSpace + totalStr);
    }

    // Totals
    content.writeln('-' * totalWidth);
    String totalLabel = 'Total:';
    String totalStr = transaction.total;
    int totalSpace = totalWidth - totalLabel.length - totalStr.length;
    content.writeln(totalLabel + ' ' * totalSpace + totalStr);

    // Payment information
    final cashPayment = double.tryParse(transaction.cashPayment) ?? 0.0;
    if (cashPayment > 0) {
      String cashLabel = 'Cash Payment:';
      String cashStr = cashPayment.toStringAsFixed(2);
      int cashSpace = totalWidth - cashLabel.length - cashStr.length;
      content.writeln(cashLabel + ' ' * cashSpace + cashStr);
    }
    final cardPayment = double.tryParse(transaction.cardPayment) ?? 0.0;
    if (cardPayment > 0) {
      String cardLabel = 'Card Payment:';
      String cardStr = cardPayment.toStringAsFixed(2);
      int cardSpace = totalWidth - cardLabel.length - cardStr.length;
      content.writeln(cardLabel + ' ' * cardSpace + cardStr);
    }
    final bankPayment = double.tryParse(transaction.bankPayment) ?? 0.0;
    if (bankPayment > 0) {
      String bankLabel = 'Bank Payment:';
      String bankStr = bankPayment.toStringAsFixed(2);
      int bankSpace = totalWidth - bankLabel.length - bankStr.length;
      content.writeln(bankLabel + ' ' * bankSpace + bankStr);
    }
    final voucherPayment = double.tryParse(transaction.voucherPayment) ?? 0.0;
    if (voucherPayment > 0) {
      String voucherLabel = 'Voucher Payment:';
      String voucherStr = voucherPayment.toStringAsFixed(2);
      int voucherSpace = totalWidth - voucherLabel.length - voucherStr.length;
      content.writeln(voucherLabel + ' ' * voucherSpace + voucherStr);
    }
    final chequePayment = double.tryParse(transaction.chequePayment) ?? 0.0;
    if (chequePayment > 0) {
      String chequeLabel = 'Cheque Payment:';
      String chequeStr = chequePayment.toStringAsFixed(2);
      int chequeSpace = totalWidth - chequeLabel.length - chequeStr.length;
      content.writeln(chequeLabel + ' ' * chequeSpace + chequeStr);
    }

    // Balance (always display, default to 0.00 if null)
    final balance = double.tryParse(transaction.balance) ?? 0.0;
    String balanceLabel = 'Balance:';
    String balanceStr = balance.toStringAsFixed(2);
    int balanceSpace = totalWidth - balanceLabel.length - balanceStr.length;
    content.writeln(balanceLabel + ' ' * balanceSpace + balanceStr);
    content.writeln('-' * totalWidth);

    content.writeln('Thank you for your purchase!');
    content.writeln('Software by JSOFT.LK');

    return content.toString();
  }

  /// Generate bill content from cart items and payment data
  static String generateBillContent({
    required List<CartItem> cartItems,
    Customer? customer,
    required double total,
    double? cashPayment,
    double? cardPayment,
    double? bankPayment,
    double? voucherPayment,
    double? chequePayment,
    double? balance,
    String? transactionId,
    String? orderDate,
  }) {
    StringBuffer content = StringBuffer();
    int totalWidth = 32; // Total width for alignment

    content.writeln('-' * totalWidth);
    // Customer info
    String customerStr = customer != null ? customer.name : 'GUEST';
    int customerSpace = totalWidth - customerStr.length - ('Customer:').length;
    content.writeln('Customer:' + ' ' * customerSpace + customerStr);

    // Transaction ID
    final finalTransactionId = transactionId ?? DateTime.now().millisecondsSinceEpoch.toString();
    String transactionIdLabel = 'Bill No:';
    int transactionIdSpace = totalWidth - transactionIdLabel.length - finalTransactionId.length;
    content.writeln(transactionIdLabel + ' ' * transactionIdSpace + finalTransactionId);

    // Time (current) in dd-MM-yyyy h:mm a
    final now = DateTime.now();
    final timeStr = _formatDateTime(now);
    String dateTimeTitle = 'Time:';
    int dateTimeTotalSpaces =
        (totalWidth - dateTimeTitle.length - timeStr.length);
    content.writeln(dateTimeTitle + ' ' * dateTimeTotalSpaces + timeStr);

    // Items
    content.writeln('-' * totalWidth);
    for (var item in cartItems) {
      String? batchNoStr = '';
      if (item.batchNumber != null) {
        batchNoStr = '-${item.batchNumber}';
      }

      String displayNameStr = item.itemDisplayName + batchNoStr;
      String totalStr = item.totalPrice.toStringAsFixed(2);
      int displayNameSpace = totalWidth - displayNameStr.length;
      content.writeln(displayNameStr + ' ' * displayNameSpace);

      // Quantity and price
      String qtyPriceStr = '(${item.quantity} x ${item.salesPrice})';
      int qtyPriceSpace = totalWidth - qtyPriceStr.length - totalStr.length;
      content.writeln(qtyPriceStr + ' ' * qtyPriceSpace + totalStr);
    }

    // Totals
    content.writeln('-' * totalWidth);
    String totalLabel = 'Total:';
    String totalStr = total.toStringAsFixed(2);
    int totalSpace = totalWidth - totalLabel.length - totalStr.length;
    content.writeln(totalLabel + ' ' * totalSpace + totalStr);

    // Payment information
    if (cashPayment != null && cashPayment > 0) {
      String cashLabel = 'Cash Payment:';
      String cashStr = cashPayment.toStringAsFixed(2);
      int cashSpace = totalWidth - cashLabel.length - cashStr.length;
      content.writeln(cashLabel + ' ' * cashSpace + cashStr);
    }
    if (cardPayment != null && cardPayment > 0) {
      String cardLabel = 'Card Payment:';
      String cardStr = cardPayment.toStringAsFixed(2);
      int cardSpace = totalWidth - cardLabel.length - cardStr.length;
      content.writeln(cardLabel + ' ' * cardSpace + cardStr);
    }
    if (bankPayment != null && bankPayment > 0) {
      String bankLabel = 'Bank Payment:';
      String bankStr = bankPayment.toStringAsFixed(2);
      int bankSpace = totalWidth - bankLabel.length - bankStr.length;
      content.writeln(bankLabel + ' ' * bankSpace + bankStr);
    }
    if (voucherPayment != null && voucherPayment > 0) {
      String voucherLabel = 'Voucher Payment:';
      String voucherStr = voucherPayment.toStringAsFixed(2);
      int voucherSpace = totalWidth - voucherLabel.length - voucherStr.length;
      content.writeln(voucherLabel + ' ' * voucherSpace + voucherStr);
    }
    if (chequePayment != null && chequePayment > 0) {
      String chequeLabel = 'Cheque Payment:';
      String chequeStr = chequePayment.toStringAsFixed(2);
      int chequeSpace = totalWidth - chequeLabel.length - chequeStr.length;
      content.writeln(chequeLabel + ' ' * chequeSpace + chequeStr);
    }

    // Balance (always display, default to 0.00 if null)
    final balanceValue = balance ?? 0.0;
    String balanceLabel = 'Balance:';
    String balanceStr = balanceValue.toStringAsFixed(2);
    int balanceSpace = totalWidth - balanceLabel.length - balanceStr.length;
    content.writeln(balanceLabel + ' ' * balanceSpace + balanceStr);
    content.writeln('-' * totalWidth);

    content.writeln('Thank you for your purchase!');
    content.writeln('Software by JSOFT.LK');

    return content.toString();
  }

  /// Send data to printer in chunks
  static Future<void> sendDataInChunks(
    BluetoothCharacteristic characteristic,
    List<int> data,
  ) async {
    int chunkSize = 200;
    int totalChunks = (data.length / chunkSize).ceil();
    int chunkNumber = 0;

    for (int i = 0; i < data.length; i += chunkSize) {
      int end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      List<int> chunk = data.sublist(i, end);
      chunkNumber++;

      if (chunkNumber == 1 || chunkNumber % 10 == 0 || chunkNumber == totalChunks) {
        print('📤 Sending chunk $chunkNumber/$totalChunks: ${chunk.length} bytes');
      }

      try {
        if (characteristic.properties.writeWithoutResponse) {
          await characteristic.write(chunk, withoutResponse: true);
          if (i + chunkSize < data.length) {
            await Future.delayed(const Duration(milliseconds: 3));
          }
        } else {
          await characteristic.write(chunk);
          if (i + chunkSize < data.length) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
      } catch (e) {
        if (e.toString().contains('data longer than allowed') && chunkSize > 20) {
          print('⚠️ Chunk too large, retrying with smaller size...');
          chunkSize = (chunkSize * 0.5).round().clamp(20, 200);
          print('🔄 Reduced chunk size to: $chunkSize bytes');
          i -= (end - i);
          chunkNumber--;
          continue;
        }
        rethrow;
      }
    }
  }

  /// Find printer characteristic from connected device
  static Future<BluetoothCharacteristic?> findPrinterCharacteristic(
    BluetoothDevice device,
  ) async {
    List<BluetoothService> services = await device.discoverServices();
    BluetoothCharacteristic? printerCharacteristic;

    // Look for printer service (common UUIDs for thermal printers)
    for (BluetoothService service in services) {
      print('🔍 Found service: ${service.uuid}');

      // Check for common printer service UUIDs
      if (service.uuid.toString().toUpperCase().contains('FFE0') ||
          service.uuid.toString().toUpperCase().contains('FFE1') ||
          service.uuid.toString().toUpperCase().contains('00001800') ||
          service.uuid.toString().toUpperCase().contains('00001801')) {
        // Look for printer characteristic
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          print('🔍 Found characteristic: ${characteristic.uuid}');
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            printerCharacteristic = characteristic;
            break;
          }
        }
        if (printerCharacteristic != null) break;
      }
    }

    if (printerCharacteristic == null) {
      // If no specific printer service found, try the first writable characteristic
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            printerCharacteristic = characteristic;
            break;
          }
        }
        if (printerCharacteristic != null) break;
      }
    }

    if (printerCharacteristic != null) {
      print('✅ Found printer characteristic: ${printerCharacteristic.uuid}');
    }

    return printerCharacteristic;
  }

  /// Print a transaction
  static Future<void> printTransaction({
    required BuildContext context,
    required Transaction transaction,
    VoidCallback? onSuccess,
    VoidCallback? onError,
  }) async {
    // Check if device is connected
    BluetoothDevice? connectedDevice = PrintDialog.getConnectedDevice();

    // Check if device exists and is actually connected
    bool isConnected = false;
    if (connectedDevice != null) {
      try {
        BluetoothConnectionState connectionState =
            await connectedDevice.connectionState.first;
        isConnected = connectionState == BluetoothConnectionState.connected;
      } catch (e) {
        print('❌ Error checking connection state: $e');
        isConnected = false;
      }
    }

    if (!isConnected) {
      // Show print dialog if printer is not connected
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return const PrintDialog();
        },
      );
      if (onError != null) onError();
      return;
    }

    try {
      // Get business name, contact number, and address
      final prefs = await SharedPreferences.getInstance();
      final businessName = prefs.getString('businessName') ?? 'Business Name';
      final contactNumber = prefs.getString('contactNumber') ?? '';
      final address = prefs.getString('address') ?? '';

      // Generate print content
      String printContent = generateBillContentFromTransaction(transaction);

      // Generate print bytes with business name and logo using the print service
      List<int> printData = await PrintService.generatePrintBytesWithLogo(
        businessName: businessName,
        content: printContent,
        contactNumber: contactNumber.isNotEmpty ? contactNumber : null,
        address: address.isNotEmpty ? address : null,
      );

      // Verify device is still connected
      if (connectedDevice == null) {
        throw Exception('Printer device is null');
      }

      BluetoothConnectionState connectionState =
          await connectedDevice.connectionState.first;
      if (connectionState != BluetoothConnectionState.connected) {
        throw Exception('Printer is not connected');
      }

      // Find printer characteristic
      BluetoothCharacteristic? printerCharacteristic =
          await findPrinterCharacteristic(connectedDevice);

      if (printerCharacteristic == null) {
        throw Exception('No writable characteristic found for printing');
      }

      // Send data to printer
      await sendDataInChunks(printerCharacteristic, printData);

      if (context.mounted) {
        SnackbarManager.showSuccess(
          context,
          message: 'Transaction printed successfully!',
        );
      }

      print('✅ Print job completed successfully');
      if (onSuccess != null) onSuccess();
    } catch (e) {
      print('❌ ERROR: Failed to print: $e');
      if (context.mounted) {
        SnackbarManager.showError(
          context,
          message: 'Print failed: $e',
        );
      }
      if (onError != null) onError();
    }
  }

  /// Print bill from cart items and payment data
  static Future<void> printBill({
    required BuildContext context,
    required List<CartItem> cartItems,
    Customer? customer,
    required double total,
    double? cashPayment,
    double? cardPayment,
    double? bankPayment,
    double? voucherPayment,
    double? chequePayment,
    double? balance,
    String? transactionId,
    String? orderDate,
    String? address,
    String? businessName,
    String? contactNumber,
    VoidCallback? onSuccess,
    VoidCallback? onError,
  }) async {
    // Check if Bluetooth device is connected
    BluetoothDevice? connectedDevice = PrintDialog.getConnectedDevice();
    if (connectedDevice == null) {
      SnackbarManager.showError(
        context,
        message:
            'No Bluetooth printer connected. Please connect a printer first.',
      );
      if (onError != null) onError();
      return;
    }

    // Check if items are added to cart
    if (cartItems.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Please add items to cart before printing.',
      );
      if (onError != null) onError();
      return;
    }

    print('🖨️ Starting direct print process...');

    try {
      // Check if device is still connected
      BluetoothConnectionState connectionState =
          await connectedDevice.connectionState.first;
      if (connectionState != BluetoothConnectionState.connected) {
        SnackbarManager.showError(
          context,
          message: 'Bluetooth printer disconnected. Please reconnect.',
        );
        if (onError != null) onError();
        return;
      }

      // Get business name and contact number
      final prefs = await SharedPreferences.getInstance();
      final finalBusinessName = businessName ?? prefs.getString('businessName') ?? 'Business Name';
      final finalContactNumber = contactNumber ?? prefs.getString('contactNumber') ?? '';
      final finalAddress = address ?? prefs.getString('address') ?? '';

      // Generate print content
      String printContent = generateBillContent(
        cartItems: cartItems,
        customer: customer,
        total: total,
        cashPayment: cashPayment,
        cardPayment: cardPayment,
        bankPayment: bankPayment,
        voucherPayment: voucherPayment,
        chequePayment: chequePayment,
        balance: balance,
        transactionId: transactionId,
        orderDate: orderDate,
      );

      // Generate print bytes with business name and logo using the print service
      List<int> printData = await PrintService.generatePrintBytesWithLogo(
        businessName: finalBusinessName,
        content: printContent,
        contactNumber: finalContactNumber.isNotEmpty ? finalContactNumber : null,
        address: finalAddress.isNotEmpty ? finalAddress : null,
      );

      // Find printer characteristic
      BluetoothCharacteristic? printerCharacteristic =
          await findPrinterCharacteristic(connectedDevice);

      if (printerCharacteristic == null) {
        throw Exception('No writable characteristic found for printing');
      }

      // Send data to printer
      await sendDataInChunks(printerCharacteristic, printData);

      if (context.mounted) {
        SnackbarManager.showSuccess(
          context,
          message: 'Bill printed successfully!',
        );
      }

      print('✅ Print job completed successfully');
      if (onSuccess != null) onSuccess();
    } catch (e) {
      print('❌ ERROR: Failed to print: $e');
      if (context.mounted) {
        SnackbarManager.showError(context, message: 'Print failed: $e');
      }
      if (onError != null) onError();
    }
  }
}
