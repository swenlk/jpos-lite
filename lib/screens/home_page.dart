import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:lite/api/endpoints.dart';
import 'package:lite/model/cart_item.dart';
import 'package:lite/model/customer.dart';
import 'package:lite/model/item.dart';
import 'package:lite/screens/login_page.dart';
import 'package:lite/screens/transaction_page.dart';
import 'package:lite/utils/app_configs.dart';
import 'package:lite/utils/print_service.dart';
import 'package:lite/utils/snackbar_manager.dart';
import 'package:lite/widgets/add_customer_dialog.dart';
import 'package:lite/widgets/clear_confirmation_dialog.dart';
import 'package:lite/widgets/logout_dialog.dart';
import 'package:lite/widgets/print_dialog.dart';
import 'package:lite/widgets/checkout_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? activeToken;
  String? businessName;

  List<Customer> _customers = [];
  Customer? _selectedCustomer;
  bool _isLoadingCustomers = true;

  // Items data
  List<Item> _items = [];
  Item? _selectedItem;
  Inventory? _selectedInventory;
  bool _isLoadingItems = true;
  int _selectedQuantity = 1;
  late TextEditingController _quantityController;

  // Cart data
  List<CartItem> _cartItems = [];

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _quantityController = TextEditingController(text: '$_selectedQuantity');
    loadUserData();
    _loadCustomersFromSharedPreferences();
    _loadItemsFromSharedPreferences();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    // Clean up any resources or cancel ongoing operations here
    super.dispose();
  }

  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedToken = prefs.getString('activeToken');

    if (storedToken != null && storedToken.isNotEmpty) {
      setState(() {
        activeToken = storedToken;
        businessName =
            prefs.getString('businessName') ?? 'No Business Name found';
      });
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
      );
    }
  }

  Future<void> onLogoutPressed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeToken');
    await prefs.remove('businessName');
    await prefs.remove('customers');
    await prefs.remove('customers');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()),
    );
  }

  Future<void> _loadCustomersFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customersJson = prefs.getString('customers');

      if (customersJson != null) {
        final List<dynamic> customersList = json.decode(customersJson);
        setState(() {
          _customers = customersList
              .map((customer) => Customer.fromJson(customer))
              .toList();
          _isLoadingCustomers = false;
        });
      } else {
        setState(() {
          _isLoadingCustomers = false;
        });
      }
    } catch (e) {
      print('Error loading customers: $e');
      setState(() {
        _isLoadingCustomers = false;
      });
    }
  }

  void _onCustomerSelected(Customer? customer) {
    setState(() {
      _selectedCustomer = customer;
    });
  }

  Future<void> _showAddCustomerDialog() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AddCustomerDialog(
          onSave: (String name, String contactNumber) {
            // Refresh the customers list after adding a new customer
            _syncData();
          },
        );
      },
    );
  }

  Future<void> _syncData() async {
    print('🔄 Starting data sync...');

    if (activeToken == null) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    try {
      final dio = Dio();

      // Add timeout and better error handling
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      print('📡 Calling sync API with token: $activeToken');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.sync,
        data: {'activeToken': activeToken},
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

      print('✅ Sync response received: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Extract data from response (same structure as login)
        final String? newActiveToken = jsonResponse['authentication_token'];
        final String? businessName = jsonResponse['businessName'];
        final List<dynamic>? rooms = jsonResponse['rooms'];
        final List<dynamic>? customers = jsonResponse['customers'];
        final List<dynamic>? items = jsonResponse['items'];

        // Update SharedPreferences with new data
        final prefs = await SharedPreferences.getInstance();

        if (newActiveToken != null) {
          await prefs.setString('activeToken', newActiveToken);
          activeToken = newActiveToken; // Update local token
        }

        if (businessName != null) {
          await prefs.setString('businessName', businessName);
        }

        if (customers != null) {
          await prefs.setString('customers', json.encode(customers));
          // Update local customers data
          setState(() {
            _customers = customers
                .map((customer) => Customer.fromJson(customer))
                .toList();
          });
        }

        // Sync items
        if (items != null) {
          await prefs.setString('items', json.encode(items));
          // Update local items data
          setState(() {
            _items = items.map((item) => Item.fromJson(item)).toList();
          });
        }

        SnackbarManager.showSuccess(
          context,
          message: 'Data synced successfully!',
        );

        print('✅ Data sync completed successfully');
      } else {
        final errorMessage =
            jsonResponse?['status_description'] ??
                jsonResponse?['message'] ??
                'Server returned status ${response.statusCode}';
        throw Exception(errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during sync: $e');
      String errorMessage = 'Error syncing data';

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
        errorMessage = 'Request timeout. Please try again.';
      } else {
        errorMessage = 'Network error: ${e.message}';
      }

      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ General error during sync: $e');
      SnackbarManager.showError(context, message: 'Unexpected error: $e');
    }
  }

  Future<void> _loadItemsFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final itemsJson = prefs.getString('items');

      if (itemsJson != null) {
        final List<dynamic> itemsList = json.decode(itemsJson);
        setState(() {
          _items = itemsList.map((item) => Item.fromJson(item)).toList();
          _isLoadingItems = false;
        });
      } else {
        setState(() {
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      print('Error loading items: $e');
      setState(() {
        _isLoadingItems = false;
      });
    }
  }

  void _onItemSelected(Item? item) {
    setState(() {
      _selectedItem = item;
      _selectedInventory = null; // Reset selected inventory when item changes
      _selectedQuantity = 1; // Reset quantity to 1 when item changes
      _quantityController.text = '$_selectedQuantity';
    });
  }

  int _getMaxQuantity() {
    if (_selectedItem == null) return 999;
    
    if (_selectedItem!.inventoried) {
      if (_selectedInventory == null) return 0;
      return double.parse(_selectedInventory!.stock).toInt();
    } else {
      return 999; // No stock limit for non-inventoried items
    }
  }

  void _decreaseQuantity() {
    if (_selectedQuantity > 1) {
      setState(() {
        _selectedQuantity--;
        _quantityController.text = '$_selectedQuantity';
      });
    }
  }

  void _increaseQuantity() {
    final maxQuantity = _getMaxQuantity();
    if (maxQuantity == 0) {
      SnackbarManager.showError(
        context,
        message: 'Please select a batch first',
      );
      return;
    }
    
    if (_selectedQuantity < maxQuantity) {
      setState(() {
        _selectedQuantity++;
        _quantityController.text = '$_selectedQuantity';
      });
    } else {
      SnackbarManager.showError(
        context,
        message: 'Quantity cannot exceed available stock',
      );
    }
  }

  void _onQuantityChanged(String value) {
    final quantity = int.tryParse(value);
    if (quantity == null || quantity < 1) {
      setState(() {
        _selectedQuantity = 1;
        _quantityController.text = '$_selectedQuantity';
      });
      return;
    }
    
    final maxQuantity = _getMaxQuantity();
    if (maxQuantity == 0) {
      setState(() {
        _selectedQuantity = 1;
        _quantityController.text = '$_selectedQuantity';
      });
      return;
    }
    
    if (quantity > maxQuantity) {
      SnackbarManager.showError(
        context,
        message: 'Quantity cannot exceed available stock',
      );
      setState(() {
        _selectedQuantity = maxQuantity;
        _quantityController.text = '$_selectedQuantity';
      });
    } else {
      setState(() {
        _selectedQuantity = quantity;
        _quantityController.text = '$_selectedQuantity';
      });
    }
  }

  void _onInventorySelected(Inventory? inventory) {
    setState(() {
      _selectedInventory = inventory;
      // Validate quantity against new inventory stock
      if (inventory != null) {
        final maxQuantity = double.parse(inventory.stock).toInt();
        if (_selectedQuantity > maxQuantity) {
          _selectedQuantity = maxQuantity;
          _quantityController.text = '$_selectedQuantity';
        }
      }
    });
  }

  void _addToCart() {
    if (_selectedItem == null) return;

    if (_selectedItem!.inventoried) {
      // For inventoried items, we need a selected inventory
      if (_selectedInventory == null) {
        SnackbarManager.showError(
          context,
          message: 'Please select a batch first',
        );
        return;
      }

      final maxQuantity = double.parse(_selectedInventory!.stock).toInt();
      
      // Check if this batch is already in cart
      final existingCartItem = _cartItems.firstWhere(
            (cartItem) =>
        cartItem.itemId == _selectedItem!.id &&
            cartItem.batchNumber == _selectedInventory!.batchNumber,
        orElse: () => CartItem(
          itemId: '',
          itemDisplayName: '',
          salesPrice: '0',
          quantity: 0,
          maxQuantity: 0,
        ),
      );

      if (existingCartItem.itemId.isNotEmpty) {
        // Update quantity if already in cart
        final newQuantity = existingCartItem.quantity + _selectedQuantity;
        if (newQuantity > maxQuantity) {
          SnackbarManager.showError(
            context,
            message: 'Quantity cannot exceed available stock',
          );
          return;
        }
        
        final updatedCartItems = _cartItems.map((cartItem) {
          if (cartItem.itemId == _selectedItem!.id &&
              cartItem.batchNumber == _selectedInventory!.batchNumber) {
            return cartItem.copyWith(quantity: newQuantity);
          }
          return cartItem;
        }).toList();

        setState(() {
          _cartItems = updatedCartItems;
        });
      } else {
        // Validate quantity before adding
        if (_selectedQuantity > maxQuantity) {
          SnackbarManager.showError(
            context,
            message: 'Quantity cannot exceed available stock',
          );
          return;
        }
        
        // Add new item to cart
        final cartItem = CartItem(
          itemId: _selectedItem!.id,
          itemDisplayName: _selectedItem!.displayName,
          batchNumber: _selectedInventory!.batchNumber,
          salesPrice: _selectedInventory!.salesPrice,
          quantity: _selectedQuantity,
          maxQuantity: maxQuantity,
        );

        setState(() {
          _cartItems = [..._cartItems, cartItem];
        });
      }
    } else {
      // For non-inventoried items, add directly to cart
      final existingCartItem = _cartItems.firstWhere(
            (cartItem) => cartItem.itemId == _selectedItem!.id,
        orElse: () => CartItem(
          itemId: '',
          itemDisplayName: '',
          salesPrice: '0',
          quantity: 0,
          maxQuantity: 0,
        ),
      );

      if (existingCartItem.itemId.isNotEmpty) {
        // Update quantity if already in cart (no limit for non-inventoried items)
        final newQuantity = existingCartItem.quantity + _selectedQuantity;
        final updatedCartItems = _cartItems.map((cartItem) {
          if (cartItem.itemId == _selectedItem!.id) {
            return cartItem.copyWith(quantity: newQuantity);
          }
          return cartItem;
        }).toList();

        setState(() {
          _cartItems = updatedCartItems;
        });
      } else {
        // Add new item to cart
        final cartItem = CartItem(
          itemId: _selectedItem!.id,
          itemDisplayName: _selectedItem!.displayName,
          salesPrice: _selectedItem!.salesPrice ?? '0.0',
          quantity: _selectedQuantity,
          maxQuantity: 999, // No stock limit for non-inventoried items
        );

        setState(() {
          _cartItems = [..._cartItems, cartItem];
        });
      }
    }
    SnackbarManager.showSuccess(context, message: 'Item added to cart');
    
    // Reset quantity to 1 after successfully adding to cart
    setState(() {
      _selectedQuantity = 1;
      _quantityController.text = '$_selectedQuantity';
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cartItems.removeAt(index);
    });
  }

  void _updateQuantity(int index, int newQuantity) {
    if (newQuantity <= 0) {
      _removeFromCart(index);
      return;
    }

    final cartItem = _cartItems[index];
    if (newQuantity > cartItem.maxQuantity) {
      SnackbarManager.showError(
        context,
        message: 'Quantity cannot exceed available stock',
      );
      return;
    }

    setState(() {
      _cartItems[index] = cartItem.copyWith(quantity: newQuantity);
    });
  }

  void _showClearConfirmationDialog() {
    ClearConfirmationDialog.show(
      context: context,
      onClear: _performClear,
    );
  }

  void _performClear() {
    setState(() {
      _selectedCustomer = null;
      _cartItems = [];
      _selectedItem = null;
      _selectedInventory = null;
      _selectedQuantity = 1;
      _quantityController.text = '$_selectedQuantity';
    });
    SnackbarManager.showSuccess(
      context,
      message: 'All fields cleared',
    );
  }

  double get _cartItemsTotal {
    return _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  String generateTransactionID() {
    final now = DateTime.now();
    final formatted = "${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}"
        "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    return formatted; // Format: yyMMddHHmmss
  }

  Future<void> _showPrintDialog() async {
    print('🖨️ Opening Print Dialog...');
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        print('✅ Print Dialog opened successfully');
        return const PrintDialog();
      },
    );
  }

  Future<void> _showCheckoutDialog() async {
    // Validate customer selection
    if (_selectedCustomer == null) {
      SnackbarManager.showError(
        context,
        message: 'Please select a customer',
      );
      return;
    }

    // Validate cart is not empty
    if (_cartItems.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Cart is empty. Please add items to cart',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return CheckoutDialog(
          totalAmount: _cartItemsTotal,
          onComplete: (paidAmount, balance, paymentType, otherPaymentMethod, paymentReference, splitPayments) {
            _submitTransaction(
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

  Future<void> _printBill() async {
    // Check if Bluetooth device is connected
    BluetoothDevice? connectedDevice = PrintDialog.getConnectedDevice();
    if (connectedDevice == null) {
      SnackbarManager.showError(
        context,
        message:
            'No Bluetooth printer connected. Please connect a printer first.',
      );
      return;
    }

    // Check if customer is selected
    if (_selectedCustomer == null) {
      SnackbarManager.showError(
        context,
        message: 'Please select a customer before printing.',
      );
      return;
    }

    // Check if items are added to cart
    if (_cartItems.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Please add items to cart before printing.',
      );
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
        return;
      }

      // Discover services
      List<BluetoothService> services = await connectedDevice
          .discoverServices();
      BluetoothService? printerService;
      BluetoothCharacteristic? printerCharacteristic;

      // Look for printer service (common UUIDs for thermal printers)
      for (BluetoothService service in services) {
        print('🔍 Found service: ${service.uuid}');

        // Check for common printer service UUIDs
        if (service.uuid.toString().toUpperCase().contains('FFE0') ||
            service.uuid.toString().toUpperCase().contains('FFE1') ||
            service.uuid.toString().toUpperCase().contains('00001800') ||
            service.uuid.toString().toUpperCase().contains('00001801')) {
          printerService = service;

          // Look for printer characteristic
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            print('🔍 Found characteristic: ${characteristic.uuid}');
            if (characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse) {
              printerCharacteristic = characteristic;
              break;
            }
          }
          break;
        }
      }

      if (printerCharacteristic == null) {
        // If no specific printer service found, try the first writable characteristic
        for (BluetoothService service in services) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse) {
              printerCharacteristic = characteristic;
              printerService = service;
              break;
            }
          }
          if (printerCharacteristic != null) break;
        }
      }

      if (printerCharacteristic == null) {
        throw Exception('No writable characteristic found for printing');
      }

      print('✅ Found printer characteristic: ${printerCharacteristic.uuid}');

      // Generate print content (without business name, as it will be handled by print service)
      String printContent = _generateBillContent();
      
      // Generate print bytes with business name and logo using the print service
      List<int> printData = await PrintService.generatePrintBytesWithLogo(
        businessName: businessName ?? 'Business Name',
        content: printContent,
      );

      // Send data to printer
      await _sendDataInChunks(printerCharacteristic, printData);

      SnackbarManager.showSuccess(
        context,
        message: 'Bill printed successfully!',
      );

      print('✅ Print job completed successfully');
    } catch (e) {
      print('❌ ERROR: Failed to print: $e');
      SnackbarManager.showError(context, message: 'Print failed: $e');
    }
  }

  String _generateBillContent() {
    StringBuffer content = StringBuffer();
    int totalWidth = 32; // Total width for alignment
    
    // Note: Business name is now handled by PrintService, so we skip it here

    // Customer info
    String customerStr = _selectedCustomer!.name;
    int customerSpace = totalWidth - customerStr.length - ('Customer:').length;
    content.writeln('Customer:' + ' ' * customerSpace + customerStr);

    // Transaction ID
    final transactionId = generateTransactionID();
    String transactionIdLabel = 'Transaction ID:';
    int transactionIdSpace = totalWidth - transactionIdLabel.length - transactionId.length;
    content.writeln(transactionIdLabel + ' ' * transactionIdSpace + transactionId);

    // Date and time
    String dateTimeTitle = 'Printed at:';
    String date = DateTime.now().toString().split(' ')[0];
    String time = DateTime.now().toString().split(' ')[1].split('.')[0];
    int dateTimeTotalSpaces =
        (totalWidth - 1 - dateTimeTitle.length - date.length - time.length);
    content.writeln(
      dateTimeTitle + ' ' * dateTimeTotalSpaces + date + ' ' + time,
    );
    // content.writeln();

    // Items
    content.writeln('-' * totalWidth);
    for (var item in _cartItems) {
      // Item name (left-aligned)
      String? batchNoStr = '';
      if (item.batchNumber != null) {
        batchNoStr = '-${item.batchNumber}';
      }

      String displayNameStr = item.itemDisplayName + batchNoStr;
      String totalStr = item.totalPrice.toStringAsFixed(2);
      int displayNameSpace =
          totalWidth - displayNameStr.length ;
      content.writeln(displayNameStr + ' ' * displayNameSpace );

      // Quantity and price (left-aligned)
      String qtyPriceStr = '(${item.quantity} x ${item.salesPrice})';
      int qtyPriceSpace = totalWidth - qtyPriceStr.length - totalStr.length;
      content.writeln(qtyPriceStr + ' ' * qtyPriceSpace + totalStr);
    }

    // Totals
    content.writeln('-' * totalWidth);
    String totalLabel = 'Total:';
    String total = _cartItemsTotal.toStringAsFixed(2);
    int totalSpace = totalWidth - totalLabel.length - total.length;
    content.writeln(totalLabel + ' ' * totalSpace + total);
    content.writeln();

    content.writeln('Thank you for your purchase!');
    content.writeln('Software by JSoft');

    return content.toString();
  }

  List<int> _convertToPrintData(String content) {
    // Split content into sections
    List<String> lines = content.split('\n');
    
    // Add ESC/POS commands for thermal printer
    List<int> printData = [];

    // Initialize printer
    printData.addAll([0x1B, 0x40]); // ESC @ - Initialize printer

    // Find business name line and thank you section
    int businessNameIndex = -1;
    int thankYouIndex = -1;
    String businessNameText = businessName ?? 'Business Name';
    
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      // Business name is typically after the first empty line
      if (businessNameIndex == -1 && line.isNotEmpty && 
          (line == businessNameText || line.contains(businessNameText))) {
        businessNameIndex = i;
      }
      // Thank you section
      if (line.contains('Thank you for your purchase!')) {
        thankYouIndex = i;
      }
    }

    // Process each line with appropriate alignment
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      
      // Center business name
      if (i == businessNameIndex) {
        printData.addAll([0x1B, 0x61, 0x01]); // ESC a 1 - Center alignment
        printData.addAll((line + '\n').codeUnits);
        printData.addAll([0x1B, 0x61, 0x00]); // ESC a 0 - Left alignment
      }
      // Center thank you section (both "Thank you" and "Software by" lines)
      else if (thankYouIndex != -1 && i >= thankYouIndex && 
               (line.trim().contains('Thank you') || line.trim().contains('Software by'))) {
        if (i == thankYouIndex) {
          printData.addAll([0x1B, 0x61, 0x01]); // ESC a 1 - Center alignment
        }
        printData.addAll((line + '\n').codeUnits);
        // Switch back to left alignment after "Software by" line
        if (line.trim().contains('Software by')) {
          printData.addAll([0x1B, 0x61, 0x00]); // ESC a 0 - Left alignment
        }
      }
      // Left align everything else
      else {
        printData.addAll((line + '\n').codeUnits);
      }
    }

    // Add line feeds and cut
    printData.addAll([0x0A, 0x0A, 0x0A]); // Line feeds
    printData.addAll([0x1D, 0x56, 0x00]); // GS V 0 - Full cut

    return printData;
  }

  Future<void> _sendDataInChunks(
    BluetoothCharacteristic characteristic,
    List<int> data,
  ) async {
    // Use a safe chunk size that works with most Bluetooth thermal printers
    // The error shows max: 237 bytes, so we use 200 bytes as a safe default
    // This leaves room for any protocol overhead
    int chunkSize = 200;

    int totalChunks = (data.length / chunkSize).ceil();
    int chunkNumber = 0;

    for (int i = 0; i < data.length; i += chunkSize) {
      int end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      List<int> chunk = data.sublist(i, end);
      chunkNumber++;

      // Log progress every 10 chunks or for the first/last chunk
      if (chunkNumber == 1 || chunkNumber % 10 == 0 || chunkNumber == totalChunks) {
        print('📤 Sending chunk $chunkNumber/$totalChunks: ${chunk.length} bytes');
      }

      try {
        if (characteristic.properties.writeWithoutResponse) {
          await characteristic.write(chunk, withoutResponse: true);
          // Minimal delay for writeWithoutResponse to prevent buffer overflow
          if (i + chunkSize < data.length) {
            await Future.delayed(const Duration(milliseconds: 3));
          }
        } else {
          await characteristic.write(chunk);
          // Slightly longer delay when waiting for response
          if (i + chunkSize < data.length) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
      } catch (e) {
        // If write fails due to size, try with smaller chunks
        if (e.toString().contains('data longer than allowed') && chunkSize > 20) {
          print('⚠️ Chunk too large, retrying with smaller size...');
          // Reduce chunk size and retry
          chunkSize = (chunkSize * 0.5).round().clamp(20, 200);
          print('🔄 Reduced chunk size to: $chunkSize bytes');
          // Retry from current position with new chunk size
          i -= (end - i); // Go back to start of failed chunk
          chunkNumber--; // Decrement to retry this chunk
          continue;
        }
        print('❌ ERROR: Failed to send chunk: $e');
        throw Exception('Failed to send data chunk: $e');
      }
    }

    print('✅ All data chunks sent successfully');
  }

  List<Map<String, dynamic>> _buildLineItems() {
    final List<Map<String, dynamic>> lineItems = [];

    for (final cartItem in _cartItems) {
      // Find the full item details from _items list
      final item = _items.firstWhere(
        (item) => item.id == cartItem.itemId,
        orElse: () => Item(
          id: cartItem.itemId,
          category: '',
          code: '',
          displayName: cartItem.itemDisplayName,
          inventoried: cartItem.batchNumber != null,
          inventory: [],
          name: cartItem.itemDisplayName,
          purchasePrice: '0.0',
          salesPrice: cartItem.salesPrice,
        ),
      );

      // Find inventory details if inventoried
      Inventory? inventory;
      if (cartItem.batchNumber != null) {
        inventory = item.inventory.firstWhere(
          (inv) => inv.batchNumber == cartItem.batchNumber,
          orElse: () => Inventory(
            id: '',
            batchNumber: cartItem.batchNumber!,
            createdDate: '',
            purchasePrice: '0.0',
            salesPrice: cartItem.salesPrice,
            stock: '0',
          ),
        );
      }

      final qty = cartItem.quantity;
      final itemPrice = double.parse(cartItem.salesPrice);
      final lineTotal = (itemPrice * qty);

      lineItems.add({
        "count": qty.toString(),
        "discount": "0.00",
        "discountType": "0.00",
        "discountPercentage": "0.00",
        "itemId": cartItem.itemId,
        "lineTotal": lineTotal.toStringAsFixed(2),
        "salesPrice": cartItem.salesPrice,
        "purchasePrice": inventory?.purchasePrice ?? item.purchasePrice ?? "0.0",
        "inventoryId": inventory?.id,
        "itemCode": item.code,
        "itemName": item.name,
        "displayName": item.displayName,
        "categoryName": item.category,
        "inventoried": cartItem.batchNumber != null,
        "batchNumber": cartItem.batchNumber,
        "staffId": null,
        "staffName": null,
      });
    }

    return lineItems;
  }

  Future<void> _submitTransaction({
    required double paidAmount,
    required double balance,
    required PaymentType paymentType,
    OtherPaymentMethod? otherPaymentMethod,
    String? paymentReference,
    List<SplitPaymentData>? splitPayments,
  }) async {
    // Validate customer selection
    if (_selectedCustomer == null) {
      SnackbarManager.showError(
        context,
        message: 'Please select a customer',
      );
      return;
    }

    // Validate cart is not empty
    if (_cartItems.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Cart is empty. Please add items to cart',
      );
      return;
    }

    // Validate active token
    if (activeToken == null) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final transactionId = generateTransactionID();
      final subTotal = _cartItemsTotal.toStringAsFixed(2);
      final total = _cartItemsTotal.toStringAsFixed(2);
      final now = DateTime.now();
      final orderDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final lineItems = _buildLineItems();

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

      final cashPayment = cashPaymentAmount.toStringAsFixed(2);
      final cardPayment = cardPaymentAmount.toStringAsFixed(2);
      final bankPayment = bankPaymentAmount.toStringAsFixed(2);
      final chequePayment = chequePaymentAmount.toStringAsFixed(2);
      final voucherPayment = voucherPaymentAmount.toStringAsFixed(2);

      final requestBody = {
        "activeToken": activeToken,
        "transactionId": transactionId,
        "transactionType": "CUSTOMER",
        "customerId": _selectedCustomer!.id,
        "subTotal": subTotal,
        "discount": "0.00",
        "totalDiscountValue": null,
        "totalDiscountPercentage": null,
        "total": total,
        "balance": balance.toStringAsFixed(2),
        "cardPayment": cardPayment,
        "cashPayment": cashPayment,
        "bankPayment": bankPayment,
        "chequePayment": chequePayment,
        "voucherPayment": voucherPayment,
        "paymentReferenceBank": paymentReferenceBank,
        "paymentReferenceCheque": paymentReferenceCheque,
        "paymentReferenceVoucher": paymentReferenceVoucher,
        "lineItems": lineItems,
        "tableId": null,
        "tableName": null,
        "staffId": null,
        "staffName": null,
        "info": null,
        "staffOverride": false,
        "orderType": null,
        "serviceCharge": null,
        "vatAmount": null,
        "vatValue": null,
        "note": null,
        "returns": null,
        "quotation": false,
        "orderDate": orderDate,
      };

      print('📤 Submitting transaction: $transactionId');
      print('Request body: ${json.encode(requestBody)}');

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.completeTransaction,
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

      print('✅ Transaction response received: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Clear cart after successful submission
        setState(() {
          _selectedCustomer = null;
          _cartItems = [];
          _selectedItem = null;
          _selectedInventory = null;
          _selectedQuantity = 1;
          _quantityController.text = '$_selectedQuantity';
        });

        SnackbarManager.showSuccess(
          context,
          message: 'Transaction completed successfully!',
        );

        print('✅ Transaction completed successfully');
      } else {
        final errorMessage =
            jsonResponse?['status_description'] ??
                jsonResponse?['message'] ??
                'Server returned status ${response.statusCode}';
        throw Exception(errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during transaction: $e');
      String errorMessage = 'Error submitting transaction';

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
        errorMessage = 'Request timeout. Please try again.';
      } else {
        errorMessage = 'Network error: ${e.message}';
      }

      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ General error during transaction: $e');
      SnackbarManager.showError(context, message: 'Unexpected error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xffd41818),
        foregroundColor: Colors.white,
        title: Text(businessName ?? 'Business Name'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _showPrintDialog,
            tooltip: 'Print',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) {
              if (value == 'transactions') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TransactionPage()),
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'transactions',
                child: Row(
                  children: [
                    Icon(Icons.receipt_long, size: 20,color: Colors.red),
                    SizedBox(width: 8),
                    Text('Transactions'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              LogoutDialog.show(
                context: context,
                onLogout: onLogoutPressed,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Main content area
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0,horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _isLoadingCustomers
                          ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: DropdownSearch<Customer>(
                              selectedItem: _selectedCustomer,
                              items: (filter, infiniteScrollProps) => _customers
                                  .where(
                                    (customer) => customer.name
                                    .toLowerCase()
                                    .contains(filter.toLowerCase()),
                              )
                                  .toList(),
                              onChanged: (Customer? newValue) {
                                _onCustomerSelected(newValue);
                              },
                              itemAsString: (Customer customer) => customer.name,
                              compareFn: (Customer item1, Customer item2) =>
                              item1.id == item2.id,
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  hintText: _customers.isEmpty
                                      ? 'No customers available'
                                      : 'Select a customer',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person),
                                ),
                              ),
                              popupProps: PopupProps.menu(
                                showSearchBox: true,
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: 'Search customers...',
                                    prefixIcon: Icon(Icons.search),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // ElevatedButton(
                          //   onPressed: _selectedCustomer != null ? _showCustomerDetails : null,
                          //   style: ElevatedButton.styleFrom(
                          //     backgroundColor: _selectedCustomer != null ? Colors.blue : Colors.grey,
                          //     foregroundColor: Colors.white,
                          //     padding: const EdgeInsets.all(8),
                          //     shape: const CircleBorder(),
                          //   ),
                          //   child: const Icon(
                          //     Icons.visibility,
                          //     size: 30.0,
                          //   ),
                          // ),
                          // const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _showAddCustomerDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(8),
                              shape: const CircleBorder(),
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 30.0, // Adjust the size as needed
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (!_isLoadingItems) ...[
                        Row(
                          children: [
                            Expanded(
                              child: DropdownSearch<Item>(
                                selectedItem: _selectedItem,
                                items: (filter, infiniteScrollProps) => _items
                                    .where(
                                      (item) => item.displayName.toLowerCase().contains(
                                    filter.toLowerCase(),
                                  ),
                                )
                                    .toList(),
                                onChanged: (Item? newValue) {
                                  _onItemSelected(newValue);
                                },
                                itemAsString: (Item item) => item.displayName,
                                compareFn: (Item item1, Item item2) => item1.id == item2.id,
                                decoratorProps: DropDownDecoratorProps(
                                  decoration: InputDecoration(
                                    hintText: _items.isEmpty
                                        ? 'No items available'
                                        : 'Select an item',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.inventory_2),
                                  ),
                                ),
                                popupProps: PopupProps.menu(
                                  showSearchBox: true,
                                  searchFieldProps: TextFieldProps(
                                    decoration: InputDecoration(
                                      hintText: 'Search items...',
                                      prefixIcon: Icon(Icons.search),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Quantity controls
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.remove),
                                  onPressed: _decreaseQuantity,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    padding: EdgeInsets.all(8),
                                  ),
                                  constraints: BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                ),
                                SizedBox(
                                  width: 60,
                                  child: TextField(
                                    controller: _quantityController,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    onChanged: _onQuantityChanged,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.add),
                                  onPressed: _increaseQuantity,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    padding: EdgeInsets.all(8),
                                  ),
                                  constraints: BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Inventory cards for inventoried items
                      if (_selectedItem != null && _selectedItem!.inventoried) ...[
                        Text(
                          'Select Batch:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _selectedItem!.inventory.map((inventory) {
                              final isSelected =
                                  _selectedInventory?.batchNumber ==
                                      inventory.batchNumber;
                              return GestureDetector(
                                onTap: () {
                                  _onInventorySelected(inventory);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 2),
                                  child: Card(
                                  elevation: isSelected ? 4 : 1,
                                  // color: isSelected ? Color(0xffd41818).withOpacity(0.1) : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected
                                          ? Color(0xffd41818)
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [

                                            Text(
                                              'Batch ${inventory.batchNumber}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                // color: isSelected ? Color(0xffd41818) : Colors.black87,
                                              ),
                                            ),
                                            if (isSelected) ...[
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.check_circle,
                                                color: Color(0xffd41818),
                                                size: 20,
                                              ),
                                            ],
                                          ],
                                        ),
                                        // const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.attach_money,
                                              // color: Colors.green.shade600,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Rs. ${inventory.salesPrice}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                // color: Colors.green.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // const SizedBox(height: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.inventory_2,
                                              // color: Colors.blue.shade600,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Stock: ${inventory.stock}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                // color: Colors.blue.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Add to Cart button
                      if (_selectedItem != null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _addToCart,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xffd41818),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: Text('Add to Cart'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Cart table
                      if (_cartItems.isNotEmpty) ...[
                        Text(
                          'Cart',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Column(
                            children: [
                              // Table header
                              Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Item',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Quantity',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Total',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Table rows
                              ...(_cartItems.asMap().entries.map((entry) {
                                final index = entry.key;
                                final cartItem = entry.value;
                                return Container(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey[200]!,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        onPressed: () => _removeFromCart(index),
                                        constraints: BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                      // Item column
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    cartItem.itemDisplayName,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (cartItem.batchNumber != null) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Batch: ${cartItem.batchNumber}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                  SizedBox(height: 2),
                                                  Text(
                                                    'Rs. ${cartItem.salesPrice}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Quantity column
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.remove, size: 16),
                                              onPressed: () => _updateQuantity(
                                                index,
                                                cartItem.quantity - 1,
                                              ),
                                              constraints: BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                            Text(
                                              '${cartItem.quantity}',
                                              style: TextStyle(fontSize: 14),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.add, size: 16),
                                              onPressed: () => _updateQuantity(
                                                index,
                                                cartItem.quantity + 1,
                                              ),
                                              constraints: BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Total column
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          '${cartItem.totalPrice.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Net total with breakdown
                        Card(
                          color: Colors.grey[100],
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Final total
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total Amount:',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Rs. ${_cartItemsTotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xffd41818),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Submit button
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showClearConfirmationDialog,
                              icon: Icon(Icons.print),
                              label: Text('Clear'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[600],
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _printBill,
                              icon: Icon(Icons.print),
                              label: Text('Print'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          // const SizedBox(width: 12),
                          // Expanded(
                          //   child: ElevatedButton.icon(
                          //     onPressed: _submitTransaction,
                          //     icon: Icon(Icons.money),
                          //     label: Text('submit'),
                          //     style: ElevatedButton.styleFrom(
                          //       backgroundColor: Colors.green,
                          //       foregroundColor: Colors.white,
                          //       padding: EdgeInsets.symmetric(vertical: 14),
                          //       shape: RoundedRectangleBorder(
                          //         borderRadius: BorderRadius.circular(8),
                          //       ),
                          //     ),
                          //   ),
                          // ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showCheckoutDialog,
                              icon: Icon(Icons.money),
                              label: Text('Pay'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 72),

                    ],
                  ),
                ),
              ),
            ),
            
            // Copyright at the bottom
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text(
                  '©${DateTime.now().year} JPosLite. All rights reserved.',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
