import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:lite/api/endpoints.dart';
import 'package:lite/model/cart_item.dart';
import 'package:lite/model/customer.dart';
import 'package:lite/model/item.dart';
import 'package:lite/screens/login_page.dart';
import 'package:lite/screens/overview_page.dart';
import 'package:lite/screens/transaction_page.dart';
import 'package:lite/screens/pending_transaction_page.dart';
import 'package:lite/utils/app_configs.dart';
import 'package:lite/utils/print_service.dart';
import 'package:lite/utils/snackbar_manager.dart';
import 'package:lite/utils/bill_printer_service.dart';
import 'package:lite/widgets/add_customer_dialog.dart';
import 'package:lite/widgets/clear_confirmation_dialog.dart';
import 'package:lite/widgets/logout_dialog.dart';
import 'package:lite/widgets/print_dialog.dart';
import 'package:lite/widgets/checkout_dialog.dart';
import 'package:lite/widgets/transaction_success_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class _TileCardData {
  final Item item;
  final Inventory? inventory;

  _TileCardData({required this.item, this.inventory});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? activeToken;
  String? businessName;
  String? businessType;
  String? contactNumber;
  String? address;
  bool _fingerprintEnabled = false;
  String? _fingerprintDeviceIp;

  bool _tileLayout = false;
  bool _quickInvoice = false;

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

  // Saved cart data for printing after transaction
  List<CartItem>? _savedCartItems;
  Customer? _savedCustomer;
  double? _savedTotal;
  double? _savedSubtotal;
  double? _savedDiscountPercentage;
  double? _savedDiscountAmount;
  bool? _savedIsPercentageMode;
  double? _savedCashPayment;
  double? _savedCardPayment;
  double? _savedBankPayment;
  double? _savedVoucherPayment;
  double? _savedChequePayment;
  double? _savedBalance;
  String? _savedOrderDate;

  // OTP verification
  String? _receivedOtp;
  late TextEditingController _otpController;

  // Discount
  bool _isPercentageMode = true; // true for %, false for $
  late TextEditingController _discountPercentageController;
  late TextEditingController _discountAmountController;

  // Tile layout search
  late TextEditingController _tileSearchController;

  String? _currentTransactionId;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _quantityController = TextEditingController(text: '$_selectedQuantity');
    _otpController = TextEditingController();
    _discountPercentageController = TextEditingController(text: '0');
    _discountAmountController = TextEditingController(text: '0');
    _tileSearchController = TextEditingController();
    loadUserData();
    _loadCustomersFromSharedPreferences();
    _loadItemsFromSharedPreferences();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _otpController.dispose();
    _discountPercentageController.dispose();
    _discountAmountController.dispose();
    _tileSearchController.dispose();
    // Clean up any resources or cancel ongoing operations here
    super.dispose();
  }

  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedToken = prefs.getString('activeToken');

    print(storedToken);

    if (storedToken != null && storedToken.isNotEmpty) {
      setState(() {
        activeToken = storedToken;
        businessName =
            prefs.getString('businessName') ?? 'No Business Name found';
        businessType = prefs.getString('businessType') ?? '';
        contactNumber = prefs.getString('contactNumber') ?? '';
        address = prefs.getString('address') ?? '';
        _fingerprintEnabled = prefs.getBool('fingerprint') ?? false;
        _fingerprintDeviceIp = prefs.getString('fingerprintDeviceIp');
        _tileLayout = prefs.getBool('tileLayout') ?? false;
        _quickInvoice = prefs.getBool('quickInvoice') ?? false;
      });
      // print(storedToken);
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
      _receivedOtp = null; // Reset OTP when customer changes
      _otpController.clear();
      print(customer?.id);
    });
  }

  Future<void> _showAddCustomerDialog() async {
    // Check if fingerprint is enabled but IP address is not configured
    if (_fingerprintEnabled &&
        (_fingerprintDeviceIp == null || _fingerprintDeviceIp!.isEmpty)) {
      SnackbarManager.showError(
        context,
        message:
            'Please enter the fingerprint IP address in Settings → Fingerprint Device.',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AddCustomerDialog(
          onSave: (String name, String contactNumber) {
            // Refresh the customers list after adding a new customer
            _syncData();
          },
          fingerprintEnabled: _fingerprintEnabled,
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

        // Update fingerprint value from configurations if present
        final configurations =
            jsonResponse['configurations'] as Map<String, dynamic>?;
        if (configurations != null && configurations['fingerprint'] != null) {
          final fingerprintValue = configurations['fingerprint'] == true;
          await prefs.setBool('fingerprint', fingerprintValue);
          setState(() {
            _fingerprintEnabled = fingerprintValue;
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

  void _addItemToCart(Item item, Inventory? inventory, int quantity) {
    if (item.inventoried) {
      // For inventoried items, we need an inventory
      if (inventory == null) {
        SnackbarManager.showError(
          context,
          message: 'Please select a batch first',
        );
        return;
      }

      final maxQuantity = double.parse(inventory.stock).toInt();

      // Check if this batch is already in cart
      final existingCartItem = _cartItems.firstWhere(
        (cartItem) =>
            cartItem.itemId == item.id &&
            cartItem.batchNumber == inventory.batchNumber,
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
        final newQuantity = existingCartItem.quantity + quantity;
        if (newQuantity > maxQuantity) {
          SnackbarManager.showError(
            context,
            message: 'Quantity cannot exceed available stock',
          );
          return;
        }

        final updatedCartItems = _cartItems.map((cartItem) {
          if (cartItem.itemId == item.id &&
              cartItem.batchNumber == inventory.batchNumber) {
            return cartItem.copyWith(quantity: newQuantity);
          }
          return cartItem;
        }).toList();

        setState(() {
          _cartItems = updatedCartItems;
        });
      } else {
        // Validate quantity before adding
        if (quantity > maxQuantity) {
          SnackbarManager.showError(
            context,
            message: 'Quantity cannot exceed available stock',
          );
          return;
        }

        // Add new item to cart
        final cartItem = CartItem(
          itemId: item.id,
          itemDisplayName: item.displayName,
          batchNumber: inventory.batchNumber,
          salesPrice: inventory.salesPrice,
          quantity: quantity,
          maxQuantity: maxQuantity,
        );

        setState(() {
          _cartItems = [..._cartItems, cartItem];
        });
      }
    } else {
      // For non-inventoried items, add directly to cart
      final existingCartItem = _cartItems.firstWhere(
        (cartItem) => cartItem.itemId == item.id,
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
        final newQuantity = existingCartItem.quantity + quantity;
        final updatedCartItems = _cartItems.map((cartItem) {
          if (cartItem.itemId == item.id) {
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
          itemId: item.id,
          itemDisplayName: item.displayName,
          salesPrice: item.salesPrice ?? '0.0',
          quantity: quantity,
          maxQuantity: 999, // No stock limit for non-inventoried items
        );

        setState(() {
          _cartItems = [..._cartItems, cartItem];
        });
      }
    }
    SnackbarManager.showSuccess(context, message: 'Item added to cart');
  }

  void _addToCart() {
    if (_selectedItem == null) return;
    _addItemToCart(_selectedItem!, _selectedInventory, _selectedQuantity);

    // Reset quantity to 1 after successfully adding to cart
    setState(() {
      _selectedQuantity = 1;
      _quantityController.text = '$_selectedQuantity';
    });
  }

  Widget _buildItemTileCard(Item item) {
    return GestureDetector(
      onTap: () {
        _addItemToCart(item, null, 1);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  item.displayName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_money, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Rs. ${item.salesPrice ?? '0.0'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildInventoryTileCard(Item item, Inventory inventory) {
    return GestureDetector(
      onTap: () {
        _addItemToCart(item, inventory, 1);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  item.displayName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Batch ${inventory.batchNumber}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_money, size: 12),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Rs. ${inventory.salesPrice}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2, size: 12),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Stock: ${inventory.stock}',
                      style: TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
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
    ClearConfirmationDialog.show(context: context, onClear: _performClear);
  }

  void _performClear() {
    setState(() {
      _selectedCustomer = null;
      _cartItems = [];
      _selectedItem = null;
      _selectedInventory = null;
      _selectedQuantity = 1;
      _quantityController.text = '$_selectedQuantity';
      _isPercentageMode = true;
      _discountPercentageController.text = '0';
      _discountAmountController.text = '0';
      _currentTransactionId = null;
    });
    SnackbarManager.showSuccess(context, message: 'All fields cleared');
  }

  double get _cartItemsTotal {
    return _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  double get _discountAmount {
    if (_isPercentageMode) {
      final percentage =
          double.tryParse(_discountPercentageController.text) ?? 0.0;
      return (_cartItemsTotal * percentage) / 100.0;
    } else {
      return double.tryParse(_discountAmountController.text) ?? 0.0;
    }
  }

  double get _finalTotal {
    return _cartItemsTotal - _discountAmount;
  }

  String generateTransactionID() {
    final now = DateTime.now();
    final formatted =
        "${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}"
        "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    return formatted; // Format: yyMMddHHmmss
  }

  String _getCurrentTransactionId() {
    if (_currentTransactionId == null) {
      _currentTransactionId = generateTransactionID();
    }
    return _currentTransactionId!;
  }

  Future<void> _resendOtp() async {
    if (_selectedCustomer == null) {
      SnackbarManager.showError(
        context,
        message: 'Please select a customer first.',
      );
      return;
    }

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

      print(
        '📡 Calling resend_otp API with customerId: ${_selectedCustomer!.id}',
      );

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.resendOtp,
        data: {'activeToken': activeToken, 'customerId': _selectedCustomer!.id},
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

      print('✅ Resend OTP response received: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (jsonResponse['status_code'] == 'S1000') {
          // Store the received OTP and show OTP field
          final receivedOtp = jsonResponse['otp']?.toString();
          setState(() {
            _receivedOtp = receivedOtp;
            _otpController.clear();
          });
          SnackbarManager.showSuccess(
            context,
            message:
                jsonResponse['status_description'] ?? 'OTP sent successfully!',
          );
        } else {
          final errorMessage =
              jsonResponse['status_description'] ?? 'Failed to send OTP';
          SnackbarManager.showError(context, message: errorMessage);
        }
      } else {
        final errorMessage =
            jsonResponse['status_description'] ??
            jsonResponse['message'] ??
            'Server returned status ${response.statusCode}';
        SnackbarManager.showError(context, message: errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during resend OTP: $e');
      String errorMessage = 'Error sending OTP';
      if (e.response != null) {
        final errorResponse = e.response!.data;
        errorMessage =
            errorResponse['status_description'] ??
            errorResponse['message'] ??
            'Server error';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Connection timeout. Please try again.';
      } else {
        errorMessage =
            'Connection error. Please check your internet connection.';
      }
      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ Unexpected error: $e');
      SnackbarManager.showError(
        context,
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  Future<void> _scanCustomerFingerprint() async {
    if (_selectedCustomer == null) {
      SnackbarManager.showError(
        context,
        message: 'Please select a customer first.',
      );
      return;
    }

    if (_selectedCustomer!.fingerprintId == null ||
        _selectedCustomer!.fingerprintId!.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'Customer does not have a fingerprint ID.',
      );
      return;
    }

    if (activeToken == null) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    // Check if IP address is configured
    if (_fingerprintDeviceIp == null || _fingerprintDeviceIp!.isEmpty) {
      SnackbarManager.showError(
        context,
        message:
            'Please configure the fingerprint device IP address in settings.',
      );
      return;
    }

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      print(
        '🔍 Sending fingerprint scan request for customer: ${_selectedCustomer!.id} with fingerprint ID: ${_selectedCustomer!.fingerprintId}',
      );

      final response = await dio.post(
        'http://$_fingerprintDeviceIp/ID_NUMBER',
        data: {
          "activeToken": activeToken,
          "ID": _selectedCustomer!.fingerprintId,
        },
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

      print('✅ Fingerprint scan response received: ${response.statusCode}');
      print('Response data: ${response.data}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.data;
        final status = responseData?['status']?.toString() ?? '';
        final message =
            responseData?['message']?.toString() ??
            'Fingerprint scan initiated';
        final step = responseData?['step']?.toString() ?? '';
        final id = responseData?['ID']?.toString() ?? '';

        print('Status: $status, Step: $step, Message: $message, ID: $id');

        // Show the message from the API response based on status
        final statusLower = status.toLowerCase();
        if (statusLower == 'success') {
          SnackbarManager.showSuccess(context, message: message);
          // Call _syncData on success
          _syncData();
        } else if (statusLower == 'progress') {
          SnackbarManager.showInfo(context, message: message);
        } else if (statusLower == 'error' || statusLower == 'failed') {
          SnackbarManager.showError(context, message: message);
        } else {
          // Default to info for unknown statuses
          SnackbarManager.showInfo(context, message: message);
        }
      } else {
        final errorMessage =
            response.data?['message'] ??
            response.data?['error'] ??
            'Server returned status ${response.statusCode}';
        SnackbarManager.showError(context, message: errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during fingerprint scan: $e');
      String errorMessage = 'Error scanning fingerprint';

      if (e.response != null) {
        print('Response status: ${e.response?.statusCode}');
        print('Response data: ${e.response?.data}');
        errorMessage =
            e.response?.data?['message'] ??
            e.response?.data?['error'] ??
            'Server error (${e.response?.statusCode})';
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage =
            'Connection timeout. Please check your connection to the fingerprint scanner.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Request timeout. Please try again.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage =
            'Connection error. Please check if the fingerprint scanner is connected.';
      } else {
        errorMessage = 'Network error: ${e.message}';
      }

      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ General error during fingerprint scan: $e');
      SnackbarManager.showError(context, message: 'Unexpected error: $e');
    }
  }

  Future<void> _verifyCustomerOtp() async {
    if (_selectedCustomer == null) {
      SnackbarManager.showError(
        context,
        message: 'Please select a customer first.',
      );
      return;
    }

    if (activeToken == null) {
      SnackbarManager.showError(
        context,
        message: 'Active token not found. Please login again.',
      );
      return;
    }

    final enteredOtp = _otpController.text.trim();
    if (enteredOtp.isEmpty) {
      SnackbarManager.showError(context, message: 'Please enter the OTP.');
      return;
    }

    if (_receivedOtp == null || _receivedOtp!.isEmpty) {
      SnackbarManager.showError(
        context,
        message: 'No OTP received. Please click "Verify Contact No" first.',
      );
      return;
    }

    // Check if entered OTP matches received OTP
    if (enteredOtp != _receivedOtp) {
      SnackbarManager.showError(
        context,
        message: 'Invalid OTP. Please try again.',
      );
      return;
    }

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      print(
        '📡 Calling verify_customer API with customerId: ${_selectedCustomer!.id}',
      );

      final response = await dio.post(
        AppConfigs.baseUrl + ApiEndpoints.verifyCustomer,
        data: {'activeToken': activeToken, 'customerId': _selectedCustomer!.id},
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

      print('✅ Verify customer response received: ${response.statusCode}');
      print('Response data: ${response.data}');

      final jsonResponse = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (jsonResponse['status_code'] == 'S1000') {
          SnackbarManager.showSuccess(
            context,
            message:
                jsonResponse['status_description'] ??
                'Customer verified successfully!',
          );

          // Update selected customer status to VERIFIED immediately
          if (_selectedCustomer != null) {
            setState(() {
              _selectedCustomer = Customer(
                id: _selectedCustomer!.id,
                name: _selectedCustomer!.name,
                contactNumber: _selectedCustomer!.contactNumber,
                status: 'VERIFIED',
                info: _selectedCustomer!.info,
                lastVisit: _selectedCustomer!.lastVisit,
                points: _selectedCustomer!.points,
                visits: _selectedCustomer!.visits,
              );
              _receivedOtp = null;
              _otpController.clear();
            });
          }

          // Refresh customers list to get updated status
          _syncData();
        } else {
          final errorMessage =
              jsonResponse['status_description'] ?? 'Failed to verify customer';
          SnackbarManager.showError(context, message: errorMessage);
        }
      } else {
        final errorMessage =
            jsonResponse['status_description'] ??
            jsonResponse['message'] ??
            'Server returned status ${response.statusCode}';
        SnackbarManager.showError(context, message: errorMessage);
      }
    } on DioException catch (e) {
      print('❌ DioException during verify customer: $e');
      String errorMessage = 'Error verifying customer';
      if (e.response != null) {
        final errorResponse = e.response!.data;
        errorMessage =
            errorResponse['status_description'] ??
            errorResponse['message'] ??
            'Server error';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Connection timeout. Please try again.';
      } else {
        errorMessage =
            'Connection error. Please check your internet connection.';
      }
      SnackbarManager.showError(context, message: errorMessage);
    } catch (e) {
      print('❌ Unexpected error: $e');
      SnackbarManager.showError(
        context,
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  Future<void> _showFingerprintDeviceDialog() async {
    final ipController = TextEditingController(
      text: _fingerprintDeviceIp ?? '',
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 8.0,
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Fingerprint Device IP Address',
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  TextField(
                    controller: ipController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'IP Address',
                      hintText: 'Enter device IP address (e.g., 192.168.1.9)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(
                          color: Colors.blue,
                          width: 2.0,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  // Action buttons
                  Row(
                    children: [
                      // Cancel button
                      Expanded(
                        child: Container(
                          height: 44.0,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 1.0,
                            ),
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
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      // Save button
                      Expanded(
                        child: Container(
                          height: 44.0,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: TextButton(
                            onPressed: () async {
                              final ipAddress = ipController.text.trim();
                              if (ipAddress.isEmpty) {
                                SnackbarManager.showError(
                                  context,
                                  message: 'Please enter an IP address',
                                );
                                return;
                              }

                              // Validate IP address format (basic validation)
                              final ipRegex = RegExp(
                                r'^(\d{1,3}\.){3}\d{1,3}$',
                              );
                              if (!ipRegex.hasMatch(ipAddress)) {
                                SnackbarManager.showError(
                                  context,
                                  message: 'Please enter a valid IP address',
                                );
                                return;
                              }

                              // Save IP address to SharedPreferences
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString(
                                'fingerprintDeviceIp',
                                ipAddress,
                              );

                              setState(() {
                                _fingerprintDeviceIp = ipAddress;
                              });

                              SnackbarManager.showSuccess(
                                context,
                                message:
                                    'Fingerprint device IP address saved successfully!',
                              );

                              Navigator.of(context).pop();
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w500,
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
      },
    );
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
    // if (_selectedCustomer == null) {
    //   SnackbarManager.showError(
    //     context,
    //     message: 'Please select a customer',
    //   );
    //   return;
    // }

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
          totalAmount: _finalTotal,
          onComplete:
              (
                paidAmount,
                balance,
                paymentType,
                otherPaymentMethod,
                paymentReference,
                splitPayments,
              ) {
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

  Future<void> _printBillImmediately() async {
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
      // If printer is not connected, show transaction success dialog and print dialog
      _showTransactionSuccessDialog();
      // Open print dialog after a short delay to allow transaction dialog to appear first
      Future.delayed(const Duration(milliseconds: 300), () {
        _showPrintDialog();
      });
      return;
    }

    // Print using saved cart data
    await BillPrinterService.printBill(
      context: context,
      cartItems: _savedCartItems!,
      customer: _savedCustomer,
      total: _savedTotal!,
      subtotal: _savedSubtotal,
      discountPercentage: _savedDiscountPercentage,
      discountAmount: _savedDiscountAmount,
      isPercentageMode: _savedIsPercentageMode,
      cashPayment: _savedCashPayment,
      cardPayment: _savedCardPayment,
      bankPayment: _savedBankPayment,
      voucherPayment: _savedVoucherPayment,
      chequePayment: _savedChequePayment,
      balance: _savedBalance ?? 0.0,
      orderDate: _savedOrderDate,
      businessName: businessName,
      contactNumber: contactNumber,
      address: address,
        transactionId:_getCurrentTransactionId(),
      onSuccess: () {
        // Clear cart after successful print
        setState(() {
          _selectedCustomer = null;
          _cartItems = [];
          _selectedItem = null;
          _selectedInventory = null;
          _selectedQuantity = 1;
          _quantityController.text = '$_selectedQuantity';
        });

        // Clear saved data
        _savedCartItems = null;
        _savedCustomer = null;
        _savedTotal = null;
        _savedSubtotal = null;
        _savedDiscountPercentage = null;
        _savedDiscountAmount = null;
        _savedIsPercentageMode = null;
        _savedCashPayment = null;
        _savedCardPayment = null;
        _savedBankPayment = null;
        _savedVoucherPayment = null;
        _savedChequePayment = null;
        _savedBalance = null;
        _savedOrderDate = null;
      },
      onError: () {
        // Clear cart even if printing fails
        setState(() {
          _selectedCustomer = null;
          _cartItems = [];
          _selectedItem = null;
          _selectedInventory = null;
          _selectedQuantity = 1;
          _quantityController.text = '$_selectedQuantity';
        });
      },
    );
  }

  Future<void> _showTransactionSuccessDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return TransactionSuccessDialog(
          onPrintReceipt: () async {
            await _handlePrintReceipt(dialogContext);
          },
          onNewInvoice: () {
            // Clear all fields using _performClear
            _performClear();
            // Clear saved data
            _savedCartItems = null;
            _savedCustomer = null;
            _savedTotal = null;
            _savedSubtotal = null;
            _savedDiscountPercentage = null;
            _savedDiscountAmount = null;
            _savedIsPercentageMode = null;
            _savedCashPayment = null;
            _savedCardPayment = null;
            _savedBankPayment = null;
            _savedVoucherPayment = null;
            _savedChequePayment = null;
            _savedBalance = null;
            _savedOrderDate = null;

            // Close dialog after clearing fields
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  Future<void> _handlePrintReceipt(BuildContext dialogContext) async {
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
      // Show print connection dialog (this will open on top of the transaction dialog)
      await _showPrintDialog();
      // After print dialog closes, the transaction dialog should still be open
      // Check again if device is connected
      connectedDevice = PrintDialog.getConnectedDevice();
      if (connectedDevice == null) {
        if (dialogContext.mounted) {
          SnackbarManager.showError(
            dialogContext,
            message: 'Please connect a printer to print the receipt.',
          );
        }
        return; // User didn't connect a device, dialog remains open
      }

      // Verify connection state again
      try {
        BluetoothConnectionState connectionState =
            await connectedDevice.connectionState.first;
        if (connectionState != BluetoothConnectionState.connected) {
          if (dialogContext.mounted) {
            SnackbarManager.showError(
              dialogContext,
              message:
                  'Printer is not connected. Please connect and try again.',
            );
          }
          return; // Dialog remains open
        }
      } catch (e) {
        print('❌ Error checking connection state: $e');
        if (dialogContext.mounted) {
          SnackbarManager.showError(
            dialogContext,
            message: 'Failed to verify printer connection.',
          );
        }
        return; // Dialog remains open
      }
    }

    // Print using saved cart data
    await BillPrinterService.printBill(
      context: dialogContext,
      cartItems: _savedCartItems!,
      customer: _savedCustomer,
      total: _savedTotal!,
      subtotal: _savedSubtotal,
      discountPercentage: _savedDiscountPercentage,
      discountAmount: _savedDiscountAmount,
      isPercentageMode: _savedIsPercentageMode,
      cashPayment: _savedCashPayment,
      cardPayment: _savedCardPayment,
      bankPayment: _savedBankPayment,
      voucherPayment: _savedVoucherPayment,
      chequePayment: _savedChequePayment,
      balance: _savedBalance ?? 0.0,
      orderDate: _savedOrderDate,
      businessName: businessName,
      contactNumber: contactNumber,
      address: address,
      transactionId: _getCurrentTransactionId(),
    );
    // Dialog remains open after printing
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
        "purchasePrice":
            inventory?.purchasePrice ?? item.purchasePrice ?? "0.0",
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

      final transactionId = _getCurrentTransactionId();
      final subTotal = _cartItemsTotal.toStringAsFixed(2);
      final total = _finalTotal.toStringAsFixed(2);
      final now = DateTime.now();
      final orderDate =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

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

      // Save payment data and cart data for printing
      _savedCartItems = List.from(_cartItems);
      _savedCustomer = _selectedCustomer;
      _savedTotal = _finalTotal;
      _savedSubtotal = _cartItemsTotal;
      _savedDiscountAmount = _discountAmount;
      _savedIsPercentageMode = _isPercentageMode;
      if (_isPercentageMode) {
        _savedDiscountPercentage =
            double.tryParse(_discountPercentageController.text) ?? 0.0;
      } else {
        _savedDiscountPercentage = null;
      }
      _savedCashPayment = cashPaymentAmount;
      _savedCardPayment = cardPaymentAmount;
      _savedBankPayment = bankPaymentAmount;
      _savedVoucherPayment = voucherPaymentAmount;
      _savedChequePayment = chequePaymentAmount;
      _savedBalance = balance;
      _savedOrderDate = orderDate;

      // Calculate discount values for request body
      String discountValue = "0.00";
      String? totalDiscountValue;
      String? totalDiscountPercentage;

      if (_isPercentageMode) {
        final percentage =
            double.tryParse(_discountPercentageController.text) ?? 0.0;
        if (percentage != 0) {
          final calculatedDiscount = _discountAmount;
          totalDiscountPercentage = percentage.toStringAsFixed(2);
          totalDiscountValue = calculatedDiscount.toStringAsFixed(2);
          discountValue = calculatedDiscount.toStringAsFixed(2);
        }
      } else {
        // Amount mode
        final discountAmount =
            double.tryParse(_discountAmountController.text) ?? 0.0;
        if (discountAmount != 0) {
          discountValue = discountAmount.toStringAsFixed(2);
        }
      }

      final requestBody = {
        "activeToken": activeToken,
        "transactionId": transactionId,
        "transactionType": _selectedCustomer != null ? "CUSTOMER" : "GUEST",
        "customerId": _selectedCustomer != null ? _selectedCustomer!.id : "",
        "subTotal": subTotal,
        "discount": discountValue,
        "totalDiscountValue": totalDiscountValue,
        "totalDiscountPercentage": totalDiscountPercentage,
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
        // Cart data is already saved before transaction submission

        print('✅ Transaction completed successfully');

        if (_quickInvoice) {
          // Print bill immediately if quick invoice is enabled
          _printBillImmediately();
        } else {
          // Show transaction success dialog if quick invoice is disabled
          _showTransactionSuccessDialog();
        }
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
            icon: const Icon(Icons.refresh),
            onPressed: _syncData,
            tooltip: 'Reload',
          ),
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
                  MaterialPageRoute(
                    builder: (context) => const TransactionPage(),
                  ),
                );
              } else if (value == 'pending_payment') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PendingTransactionPage(),
                  ),
                );
              } else if (value == 'overview') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OverviewPage()),
                );
              } else if (value == 'fingerprint_device') {
                _showFingerprintDeviceDialog();
              }
            },
            itemBuilder: (BuildContext context) {
              final items = <PopupMenuItem<String>>[
                const PopupMenuItem<String>(
                  value: 'transactions',
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Transactions'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'pending_payment',
                  child: Row(
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 20,
                        color: Colors.orange,
                      ),
                      SizedBox(width: 8),
                      Text('Pending Payments'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'overview',
                  child: Row(
                    children: [
                      Icon(Icons.bar_chart, size: 20, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Overview'),
                    ],
                  ),
                ),
              ];

              // Add Fingerprint Device menu item if fingerprint is enabled
              if (_fingerprintEnabled) {
                items.add(
                  const PopupMenuItem<String>(
                    value: 'fingerprint_device',
                    child: Row(
                      children: [
                        Icon(Icons.fingerprint, size: 20, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Fingerprint Device'),
                      ],
                    ),
                  ),
                );
              }

              return items;
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              LogoutDialog.show(context: context, onLogout: onLogoutPressed);
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 32.0,
                    horizontal: 16.0,
                  ),
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
                                    items: (filter, infiniteScrollProps) =>
                                        _customers
                                            .where(
                                              (customer) => customer.name
                                                  .toLowerCase()
                                                  .contains(
                                                    filter.toLowerCase(),
                                                  ),
                                            )
                                            .toList(),
                                    onChanged: (Customer? newValue) {
                                      _onCustomerSelected(newValue);
                                    },
                                    itemAsString: (Customer customer) =>
                                        customer.name,
                                    compareFn:
                                        (Customer item1, Customer item2) =>
                                            item1.id == item2.id,
                                    decoratorProps: DropDownDecoratorProps(
                                      decoration: InputDecoration(
                                        hintText: _customers.isEmpty
                                            ? 'GUEST Customer'
                                            : 'GUEST Customer',
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

                      // Verify Contact No and Scan Fingerprint buttons
                      if (_selectedCustomer != null) ...[
                        Builder(
                          builder: (context) {
                            final showVerifyContact =
                                _selectedCustomer!.status != 'VERIFIED';
                            final showScanFingerprint =
                                _selectedCustomer!.fingerprintId != null &&
                                _selectedCustomer!.fingerprintStatus != null &&
                                _selectedCustomer!.fingerprintStatus !=
                                    'VERIFIED';

                            // If both are VERIFIED, show nothing
                            if (!showVerifyContact && !showScanFingerprint) {
                              return const SizedBox.shrink();
                            }

                            // If both buttons should be shown, display them in a Row
                            if (showVerifyContact && showScanFingerprint) {
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _resendOtp,
                                          icon: const Icon(Icons.verified_user),
                                          label: const Text(
                                            'Verify Contact No',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _scanCustomerFingerprint,
                                          icon: const Icon(Icons.fingerprint),
                                          label: const Text('Scan Fingerprint'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xffd41818,
                                            ),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              );
                            }

                            // If only one button should be shown, display it full width
                            return Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: showVerifyContact
                                        ? _resendOtp
                                        : _scanCustomerFingerprint,
                                    icon: Icon(
                                      showVerifyContact
                                          ? Icons.verified_user
                                          : Icons.fingerprint,
                                    ),
                                    label: Text(
                                      showVerifyContact
                                          ? 'Verify Contact No'
                                          : 'Scan Fingerprint',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: showVerifyContact
                                          ? Colors.orange
                                          : const Color(0xffd41818),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          },
                        ),

                        // OTP TextField and Verify button (shown when OTP is received)
                        if (_receivedOtp != null &&
                            _receivedOtp!.isNotEmpty) ...[
                          TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Enter OTP',
                              hintText: 'Enter the OTP received',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _verifyCustomerOtp,
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Verify'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],

                      // Scan Fingerprint button (shown when fingerprint is enabled)
                      // if (_fingerprintEnabled) ...[
                      //   SizedBox(
                      //     width: double.infinity,
                      //     child: ElevatedButton.icon(
                      //       onPressed: _scanFingerprint,
                      //       icon: Icon(Icons.fingerprint),
                      //       label: Text('Scan Fingerprint'),
                      //       style: ElevatedButton.styleFrom(
                      //         backgroundColor: Color(0xffd41818),
                      //         foregroundColor: Colors.white,
                      //         padding: EdgeInsets.symmetric(vertical: 12),
                      //       ),
                      //     ),
                      //   ),
                      //   const SizedBox(height: 16),
                      // ],
                      if (!_isLoadingItems) ...[
                        if (!_tileLayout) ...[
                          // Standard mode: Show dropdown, quantity controls, and Add to Cart button
                          Row(
                            children: [
                              Expanded(
                                child: DropdownSearch<Item>(
                                  selectedItem: _selectedItem,
                                  items: (filter, infiniteScrollProps) => _items.where((
                                    item,
                                  ) {
                                    // Filter by search text
                                    if (!item.displayName
                                        .toLowerCase()
                                        .contains(filter.toLowerCase())) {
                                      return false;
                                    }

                                    // For inventoried items, check if any inventory has stock > 0
                                    if (item.inventoried) {
                                      if (item.inventory.isEmpty) {
                                        return false; // Skip if no inventory
                                      }
                                      // Check if at least one inventory has stock > 0
                                      final hasStock = item.inventory.any((
                                        inventory,
                                      ) {
                                        final stock =
                                            double.tryParse(inventory.stock) ??
                                            0.0;
                                        return stock > 0;
                                      });
                                      return hasStock;
                                    }

                                    // For non-inventoried items, include them
                                    return true;
                                  }).toList(),
                                  onChanged: (Item? newValue) {
                                    _onItemSelected(newValue);
                                  },
                                  itemAsString: (Item item) => item.displayName,
                                  compareFn: (Item item1, Item item2) =>
                                      item1.id == item2.id,
                                  decoratorProps: DropDownDecoratorProps(
                                    decoration: InputDecoration(
                                      hintText: _items.isEmpty
                                          ? 'No items available'
                                          : 'Select an item',
                                      // hintStyle: TextStyle(
                                      //   fontSize: 14.0,
                                      // ),
                                      border: OutlineInputBorder(),
                                      // prefixIcon: Icon(Icons.inventory_2),
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
                          // Inventory cards for inventoried items
                          if (_selectedItem != null &&
                              _selectedItem!.inventoried) ...[
                            Text(
                              'Select Batch:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _selectedItem!.inventory
                                    .where((inventory) {
                                      final stock =
                                          double.tryParse(inventory.stock) ??
                                          0.0;
                                      return stock > 0;
                                    })
                                    .map((inventory) {
                                      final isSelected =
                                          _selectedInventory?.batchNumber ==
                                          inventory.batchNumber;
                                      return GestureDetector(
                                        onTap: () {
                                          _onInventorySelected(inventory);
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            right: 2,
                                          ),
                                          child: Card(
                                            elevation: isSelected ? 4 : 1,
                                            // color: isSelected ? Color(0xffd41818).withOpacity(0.1) : Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        'Batch ${inventory.batchNumber}',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                          // color: isSelected ? Color(0xffd41818) : Colors.black87,
                                                        ),
                                                      ),
                                                      if (isSelected) ...[
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Icon(
                                                          Icons.check_circle,
                                                          color: Color(
                                                            0xffd41818,
                                                          ),
                                                          size: 20,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  // const SizedBox(height: 6),
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
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
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          // color: Colors.green.shade700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  // const SizedBox(height: 8),
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
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
                                    })
                                    .toList(),
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
                        ] else ...[
                          // Tile mode: Show items as cards
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Search input field
                              SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: _tileSearchController,
                                  style: TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Search items...',
                                    hintStyle: TextStyle(fontSize: 14),
                                    prefixIcon: Icon(Icons.search, size: 20),
                                    suffixIcon:
                                        _tileSearchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(Icons.close, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _tileSearchController.clear();
                                              });
                                            },
                                          )
                                        : null,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      // Trigger rebuild to filter items and update clear icon
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Items grid
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  if (_items.isEmpty) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(32.0),
                                        child: Text(
                                          'No items available',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                      ),
                                    );
                                  }

                                  final searchText = _tileSearchController.text
                                      .toLowerCase();

                                  // Build a list of card data for efficient access
                                  List<_TileCardData> cardData = [];
                                  for (var item in _items) {
                                    // Filter by displayName if search text is provided
                                    if (searchText.isNotEmpty &&
                                        !item.displayName
                                            .toLowerCase()
                                            .contains(searchText)) {
                                      continue; // Skip items that don't match search
                                    }

                                    if (item.inventoried) {
                                      // For inventoried items, only load if inventory array has objects
                                      if (item.inventory.isNotEmpty) {
                                        // Create a card for each inventory entry, but skip if stock is 0
                                        for (var inventory in item.inventory) {
                                          final stock =
                                              double.tryParse(
                                                inventory.stock,
                                              ) ??
                                              0.0;
                                          if (stock > 0) {
                                            cardData.add(
                                              _TileCardData(
                                                item: item,
                                                inventory: inventory,
                                              ),
                                            );
                                          }
                                        }
                                      }
                                      // If inventory is empty, skip this item (don't add to cardData)
                                    } else {
                                      // For non-inventoried items, create a single card with displayName and salesPrice
                                      cardData.add(
                                        _TileCardData(
                                          item: item,
                                          inventory: null,
                                        ),
                                      );
                                    }
                                  }

                                  // Check if no items match the search
                                  if (cardData.isEmpty) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(32.0),
                                        child: Text(
                                          searchText.isNotEmpty
                                              ? 'No items found matching "$searchText"'
                                              : 'No items available',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                      ),
                                    );
                                  }

                                  // Calculate card width to ensure at least 3 cards per row
                                  const spacing = 6.0;
                                  const minCardsPerRow = 3;
                                  final availableWidth = constraints.maxWidth;
                                  // Calculate width for exactly 3 cards: (availableWidth - (spacing * 2)) / 3
                                  // This ensures at least 3 cards per row
                                  final cardWidth =
                                      (availableWidth -
                                          (spacing * (minCardsPerRow - 1))) /
                                      minCardsPerRow;

                                  // Use MediaQuery to get available height and constrain the scroll view
                                  final screenHeight = MediaQuery.of(
                                    context,
                                  ).size.height;
                                  final maxHeight =
                                      screenHeight *
                                      0.5; // Use 50% of screen height

                                  return ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: maxHeight,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Wrap(
                                        spacing: spacing,
                                        runSpacing: spacing,
                                        children: cardData.map((data) {
                                          return SizedBox(
                                            width: cardWidth,
                                            child: data.inventory != null
                                                ? _buildInventoryTileCard(
                                                    data.item,
                                                    data.inventory!,
                                                  )
                                                : _buildItemTileCard(data.item),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],

                      // Cart table
                      if (_cartItems.isNotEmpty) ...[
                        Text(
                          'Cart',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Quantity',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Total',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  if (cartItem.batchNumber !=
                                                      null) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Batch: ${cartItem.batchNumber}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                  SizedBox(height: 2),
                                                  Text(
                                                    'Rs. ${cartItem.salesPrice}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                              icon: Icon(
                                                Icons.remove,
                                                size: 16,
                                              ),
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Subtotal Amount:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Rs. ${_cartItemsTotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xffd41818),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Discount:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Toggle button and input fields
                                Row(
                                  children: [
                                    // Toggle button
                                    Material(
                                      color: _isPercentageMode
                                          ? Colors.blue[100]
                                          : Colors.green[100],
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        onTap: () {
                                          setState(() {
                                            _isPercentageMode =
                                                !_isPercentageMode;
                                            if (_isPercentageMode) {
                                              _discountAmountController.text =
                                                  '0';
                                            } else {
                                              _discountPercentageController
                                                      .text =
                                                  '0';
                                            }
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: _isPercentageMode
                                                  ? Colors.blue[300]!
                                                  : Colors.green[300]!,
                                              width: 2,
                                            ),
                                          ),
                                          child: Icon(
                                            _isPercentageMode
                                                ? Icons.percent
                                                : Icons.attach_money,
                                            color: _isPercentageMode
                                                ? Colors.blue[700]
                                                : Colors.green[700],
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Input fields based on mode
                                    if (_isPercentageMode) ...[
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller:
                                              _discountPercentageController,
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText:
                                                'Discount Percentage (%)',
                                            hintText: '0',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                          ),
                                          onChanged: (value) {
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.grey,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Rs. ${_discountAmount.toStringAsFixed(2)}',
                                            style: TextStyle(fontSize: 14),
                                            textAlign: TextAlign.end,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      Expanded(
                                        child: TextField(
                                          controller: _discountAmountController,
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: 'Discount Amount (Rs.)',
                                            hintText: '0',
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                          ),
                                          onChanged: (value) {
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total Amount:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Rs. ${_finalTotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
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
                        // Discount section
                        // Card(
                        //   color: Colors.grey[100],
                        //   child: Padding(
                        //     padding: EdgeInsets.all(16),
                        //     child: Column(
                        //       crossAxisAlignment: CrossAxisAlignment.start,
                        //       children: [
                        //         Text(
                        //           'Discount:',
                        //           style: TextStyle(
                        //             fontSize: 16,
                        //             fontWeight: FontWeight.bold,
                        //           ),
                        //         ),
                        //         // Radio buttons
                        //         Row(
                        //           children: [
                        //             Radio<String>(
                        //               value: 'None',
                        //               groupValue: _discountType,
                        //               onChanged: (value) {
                        //                 setState(() {
                        //                   _discountType = value!;
                        //                   _discountPercentageController.clear();
                        //                   _discountAmountController.clear();
                        //                 });
                        //               },
                        //             ),
                        //             Text('None'),
                        //             const SizedBox(width: 20),
                        //             Radio<String>(
                        //               value: 'Percentage',
                        //               groupValue: _discountType,
                        //               onChanged: (value) {
                        //                 setState(() {
                        //                   _discountType = value!;
                        //                   _discountAmountController.clear();
                        //                 });
                        //               },
                        //             ),
                        //             Text('Percentage'),
                        //             const SizedBox(width: 20),
                        //             Radio<String>(
                        //               value: 'Amount',
                        //               groupValue: _discountType,
                        //               onChanged: (value) {
                        //                 setState(() {
                        //                   _discountType = value!;
                        //                   _discountPercentageController.clear();
                        //                 });
                        //               },
                        //             ),
                        //             Text('Amount'),
                        //           ],
                        //         ),
                        //         // Conditional input fields
                        //         if (_discountType == 'Percentage') ...[
                        //           const SizedBox(height: 12),
                        //           Row(
                        //             children: [
                        //               Expanded(
                        //                 flex: 2,
                        //                 child: TextField(
                        //                   controller: _discountPercentageController,
                        //                   keyboardType: TextInputType.numberWithOptions(decimal: true),
                        //                   decoration: InputDecoration(
                        //                     labelText: 'Discount Percentage (%)',
                        //                     border: OutlineInputBorder(),
                        //                     contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        //                   ),
                        //                   onChanged: (value) {
                        //                     setState(() {});
                        //                   },
                        //                 ),
                        //               ),
                        //               const SizedBox(width: 12),
                        //               Expanded(
                        //                 flex: 2,
                        //                 child: Container(
                        //                   padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        //                   decoration: BoxDecoration(
                        //                     border: Border.all(color: Colors.grey),
                        //                     borderRadius: BorderRadius.circular(4),
                        //                   ),
                        //                   child: Text(
                        //                     'Discount: Rs. ${_discountAmount.toStringAsFixed(2)}',
                        //                     style: TextStyle(
                        //                       fontSize: 14,
                        //                       fontWeight: FontWeight.w500,
                        //                     ),
                        //                   ),
                        //                 ),
                        //               ),
                        //             ],
                        //           ),
                        //         ],
                        //         if (_discountType == 'Amount') ...[
                        //           const SizedBox(height: 12),
                        //           TextField(
                        //             controller: _discountAmountController,
                        //             keyboardType: TextInputType.numberWithOptions(decimal: true),
                        //             decoration: InputDecoration(
                        //               labelText: 'Discount Amount (Rs.)',
                        //               border: OutlineInputBorder(),
                        //               contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        //             ),
                        //             onChanged: (value) {
                        //               setState(() {});
                        //             },
                        //           ),
                        //         ],
                        //       ],
                        //     ),
                        //   ),
                        // ),
                        // const SizedBox(height: 16),
                        // Final total display
                        // Card(
                        //   color: Colors.green[50],
                        //   child: Padding(
                        //     padding: EdgeInsets.all(16),
                        //     child: Row(
                        //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //       children: [
                        //         Text(
                        //           'Total Amount:',
                        //           style: TextStyle(
                        //             fontSize: 18,
                        //             fontWeight: FontWeight.bold,
                        //           ),
                        //         ),
                        //         Text(
                        //           'Rs. ${_finalTotal.toStringAsFixed(2)}',
                        //           style: TextStyle(
                        //             fontSize: 18,
                        //             fontWeight: FontWeight.bold,
                        //             color: Color(0xffd41818),
                        //           ),
                        //         ),
                        //       ],
                        //     ),
                        //   ),
                        // ),
                        // const SizedBox(height: 16),

                        // Submit button
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showClearConfirmationDialog,
                              icon: Icon(Icons.delete_forever),
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
                          if (businessType == 'RESTAURANT')
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  await BillPrinterService.printKOTBill(
                                    context: context,
                                    transactionId:_getCurrentTransactionId(),
                                    cartItems: _cartItems,
                                    customer: _selectedCustomer,
                                  );
                                },
                                icon: Icon(Icons.print),
                                label: Text('KOT'),
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
                  style: TextStyle(fontSize: 12.0, color: Colors.grey[500]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
