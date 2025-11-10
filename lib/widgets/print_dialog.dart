import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class PrintDialog extends StatefulWidget {
  const PrintDialog({super.key});

  @override
  State<PrintDialog> createState() => _PrintDialogState();
  
  // Static method to get connected device
  static BluetoothDevice? getConnectedDevice() {
    return _PrintDialogState.getConnectedDevice();
  }
}

class _PrintDialogState extends State<PrintDialog> {
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  bool _isLoading = false;
  String _statusMessage = '';
  BluetoothAdapterState _bluetoothState = BluetoothAdapterState.unknown;
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  
  // Static variable to track connected device globally
  static BluetoothDevice? _globalConnectedDevice;
  
  // Static method to get connected device
  static BluetoothDevice? getConnectedDevice() {
    return _globalConnectedDevice;
  }

  @override
  void initState() {
    super.initState();
    print('🚀 Print Dialog initialized');
    _checkBluetoothState();
    _loadPairedDevices();
  }

  @override
  void dispose() {
    print('🔚 Print Dialog disposed');
    super.dispose();
  }

  Future<void> _loadPairedDevices() async {
    print('📱 Loading paired devices...');
    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluePlus.bondedDevices;
      print('✅ Found ${bondedDevices.length} paired devices');
      
      setState(() {
        _devices.addAll(bondedDevices);
        if (_devices.isNotEmpty) {
          _statusMessage = 'Found ${_devices.length} paired device(s). Tap "Scan" to find more devices.';
        }
      });

      // Check for already connected devices
      await _checkConnectedDevices();
    } catch (e) {
      print('❌ ERROR: Failed to load paired devices: $e');
    }
  }

  Future<void> _checkConnectedDevices() async {
    print('🔍 Checking for already connected devices...');
    try {
      for (BluetoothDevice device in _devices) {
        BluetoothConnectionState connectionState = await device.connectionState.first;
        print('📡 Device ${device.platformName} connection state: $connectionState');
        
        if (connectionState == BluetoothConnectionState.connected) {
          print('✅ Found connected device: ${device.platformName}');
          setState(() {
            _connectedDevice = device;
            _globalConnectedDevice = device; // Set global connected device
            _statusMessage = 'Connected to ${device.platformName.isNotEmpty ? device.platformName : 'device'}';
          });
          break; // Only one device can be connected at a time
        }
      }
    } catch (e) {
      print('❌ ERROR: Failed to check connected devices: $e');
    }
  }

  Future<void> _checkBluetoothState() async {
    print('🔍 Checking Bluetooth state...');
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking Bluetooth state...';
    });

    try {
      // Check if Bluetooth is available on this device
      bool isAvailable = await FlutterBluePlus.isAvailable;
      print('📱 Bluetooth available: $isAvailable');
      
      if (!isAvailable) {
        print('❌ ERROR: Bluetooth is not available on this device');
        setState(() {
          _statusMessage = 'Bluetooth is not available on this device.';
          _isLoading = false;
        });
        return;
      }

      _bluetoothState = await FlutterBluePlus.adapterState.first;
      print('📱 Bluetooth state: $_bluetoothState');
      
      if (_bluetoothState != BluetoothAdapterState.on) {
        print('⚠️ WARNING: Bluetooth is turned off');
        setState(() {
          _statusMessage = 'Bluetooth is turned off. Please turn on Bluetooth.';
          _isLoading = false;
        });
        return;
      }

      print('✅ SUCCESS: Bluetooth is ready');
      setState(() {
        _statusMessage = 'Bluetooth is ready. Tap "Scan" to find devices.';
        _isLoading = false;
      });
    } catch (e) {
      print('❌ ERROR: Failed to check Bluetooth state: $e');
      setState(() {
        _statusMessage = 'Error checking Bluetooth: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    print('🔐 Requesting Bluetooth permissions...');
    setState(() {
      _isLoading = true;
      _statusMessage = 'Requesting permissions...';
    });

    try {
      // Request Bluetooth permissions
      Map<Permission, PermissionStatus> permissions = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      print('📋 Permission results:');
      List<String> deniedPermissions = [];
      List<String> permanentlyDeniedPermissions = [];
      
      permissions.forEach((permission, status) {
        print('  - ${permission.toString()}: $status');
        if (status == PermissionStatus.denied) {
          deniedPermissions.add(_getPermissionName(permission));
        } else if (status == PermissionStatus.permanentlyDenied) {
          permanentlyDeniedPermissions.add(_getPermissionName(permission));
        }
      });

      bool allGranted = permissions.values.every(
        (status) => status == PermissionStatus.granted,
      );

      if (allGranted) {
        print('✅ SUCCESS: All permissions granted');
        setState(() {
          _statusMessage = 'Permissions granted. Ready to scan.';
          _isLoading = false;
        });
      } else {
        print('⚠️ WARNING: Some permissions were denied');
        String message = '';
        
        if (permanentlyDeniedPermissions.isNotEmpty) {
          message = 'Some permissions are permanently denied: ${permanentlyDeniedPermissions.join(', ')}. Please enable them in app settings.';
        } else if (deniedPermissions.isNotEmpty) {
          message = 'Some permissions were denied: ${deniedPermissions.join(', ')}. Please grant all permissions to use Bluetooth printing.';
        } else {
          message = 'Some permissions were denied. Please grant all permissions.';
        }
        
        setState(() {
          _statusMessage = message;
          _isLoading = false;
        });
        
        // Show snackbar with option to open settings if permanently denied
        if (permanentlyDeniedPermissions.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please enable permissions in app settings'),
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () async {
                  await openAppSettings();
                },
              ),
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ ERROR: Failed to request permissions: $e');
      setState(() {
        _statusMessage = 'Error requesting permissions: $e';
        _isLoading = false;
      });
    }
  }

  String _getPermissionName(Permission permission) {
    if (permission == Permission.bluetooth) return 'Bluetooth';
    if (permission == Permission.bluetoothScan) return 'Bluetooth Scan';
    if (permission == Permission.bluetoothConnect) return 'Bluetooth Connect';
    if (permission == Permission.location) return 'Location';
    return permission.toString();
  }

  Future<void> _scanForDevices() async {
    print('🔍 Starting Bluetooth device scan...');
    setState(() {
      _isScanning = true;
      _devices.clear();
      _statusMessage = 'Scanning for Bluetooth devices...';
    });

    try {
      // Check if Bluetooth is available and on before scanning
      bool isAvailable = await FlutterBluePlus.isAvailable;
      if (!isAvailable) {
        print('❌ ERROR: Bluetooth is not available');
        setState(() {
          _isScanning = false;
          _statusMessage = 'Bluetooth is not available on this device.';
        });
        return;
      }

      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        print('❌ ERROR: Bluetooth is not turned on');
        setState(() {
          _isScanning = false;
          _statusMessage = 'Please turn on Bluetooth before scanning.';
        });
        return;
      }

      // First, get already paired/bonded devices
      print('📱 Getting paired/bonded devices...');
      List<BluetoothDevice> bondedDevices = await FlutterBluePlus.bondedDevices;
      print('✅ Found ${bondedDevices.length} paired devices');
      
      setState(() {
        _devices.addAll(bondedDevices);
        _statusMessage = 'Found ${_devices.length} paired device(s). Scanning for new devices...';
      });

      // Start scanning for new devices
      print('🔍 Starting device discovery for new devices...');
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      
      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          print('📡 Discovered device: ${result.device.platformName.isNotEmpty ? result.device.platformName : 'Unknown'} (${result.device.remoteId})');
          setState(() {
            if (!_devices.any((device) => device.remoteId == result.device.remoteId)) {
              _devices.add(result.device);
              print('✅ Added new device to list. Total devices: ${_devices.length}');
            } else {
              print('ℹ️ Device already in list, skipping');
            }
            _statusMessage = 'Found ${_devices.length} device(s)';
          });
        }
      });

      // Wait for scan to complete
      print('⏱️ Waiting 10 seconds for device discovery...');
      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
      print('🛑 Device discovery stopped');

      // Check for connected devices after scanning
      await _checkConnectedDevices();

      setState(() {
        _isScanning = false;
        if (_devices.isEmpty) {
          print('⚠️ WARNING: No Bluetooth devices found (including paired devices)');
          _statusMessage = 'No Bluetooth devices found. Make sure your printer is in pairing mode.';
        } else {
          print('✅ SUCCESS: Scan completed. Found ${_devices.length} device(s) (${bondedDevices.length} paired + ${_devices.length - bondedDevices.length} new)');
          if (_connectedDevice == null) {
            _statusMessage = 'Scan completed. Found ${_devices.length} device(s).';
          }
        }
      });
    } catch (e) {
      print('❌ ERROR: Failed to scan for devices: $e');
      setState(() {
        _isScanning = false;
        _statusMessage = 'Error scanning for devices: Please grant permission';
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    print('🔗 Attempting to connect to device: ${device.platformName.isNotEmpty ? device.platformName : 'Unknown'} (${device.remoteId})');
    
    if (_isConnecting) {
      print('⚠️ WARNING: Already connecting to a device');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already connecting to a device. Please wait.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_connectedDevice != null && _connectedDevice!.remoteId == device.remoteId) {
      print('ℹ️ Device is already connected');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device is already connected'),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to ${device.platformName.isNotEmpty ? device.platformName : 'device'}...';
    });

    try {
      // Disconnect from current device if any
      if (_connectedDevice != null) {
        print('🔌 Disconnecting from current device...');
        await _disconnectFromDevice();
      }

      print('🔗 Connecting to device...');
      await device.connect();
      
      // Wait for connection to be established
      await device.connectionState.firstWhere((state) => state == BluetoothConnectionState.connected);
      
      print('✅ SUCCESS: Connected to device successfully');
      setState(() {
        _connectedDevice = device;
        _globalConnectedDevice = device; // Set global connected device
        _isConnecting = false;
        _statusMessage = 'Connected to ${device.platformName.isNotEmpty ? device.platformName : 'device'}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${device.platformName.isNotEmpty ? device.platformName : 'device'} successfully!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('❌ ERROR: Failed to connect to device: $e');
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Failed to connect to device';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnectFromDevice() async {
    if (_connectedDevice == null) {
      print('ℹ️ No device connected to disconnect');
      return;
    }

    print('🔌 Disconnecting from device: ${_connectedDevice!.platformName.isNotEmpty ? _connectedDevice!.platformName : 'Unknown'}');
    
    try {
      await _connectedDevice!.disconnect();
      print('✅ SUCCESS: Disconnected from device');
      
      setState(() {
        _connectedDevice = null;
        _globalConnectedDevice = null; // Clear global connected device
        _statusMessage = 'Disconnected from device';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from device'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      print('❌ ERROR: Failed to disconnect from device: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to disconnect: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Print Options',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Connection status
            if (_connectedDevice != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bluetooth_connected,
                      color: Colors.green[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connected to: ${_connectedDevice!.platformName.isNotEmpty ? _connectedDevice!.platformName : 'Device'}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isConnecting ? null : _disconnectFromDevice,
                      icon: Icon(
                        Icons.close,
                        color: Colors.red[700],
                        size: 20,
                      ),
                      tooltip: 'Disconnect',
                    ),
                  ],
                ),
              ),
            
            // Status message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _requestPermissions,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.security),
                    label: const Text('Request Permissions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isScanning || _isLoading) ? null : _scanForDevices,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth_searching),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            // Open Settings button (shown when permissions are permanently denied)
            if (_statusMessage.contains('permanently denied') || _statusMessage.contains('app settings'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await openAppSettings();
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Open App Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            
            const SizedBox(height: 20),

            // Device list header
            const Text(
              'Available Devices',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // Device list
            Expanded(
              child: _devices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_disabled,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No devices found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Make sure your printer is turned on and in pairing mode',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              _connectedDevice?.remoteId == device.remoteId 
                                  ? Icons.bluetooth_connected 
                                  : Icons.bluetooth,
                              color: _connectedDevice?.remoteId == device.remoteId 
                                  ? Colors.green 
                                  : Colors.blue,
                            ),
                            title: Text(
                              device.platformName.isNotEmpty ? device.platformName : 'Unknown Device',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.remoteId.toString(),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                if (_connectedDevice?.remoteId == device.remoteId)
                                  Text(
                                    'Connected',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                else
                                  Text(
                                    'Available',
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: _connectedDevice?.remoteId == device.remoteId
                                ? ElevatedButton(
                                    onPressed: _isConnecting ? null : _disconnectFromDevice,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                    ),
                                    child: const Text('Disconnect'),
                                  )
                                : ElevatedButton(
                                    onPressed: _isConnecting ? null : () => _connectToDevice(device),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isConnecting ? Colors.grey : Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                    ),
                                    child: _isConnecting 
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : const Text('Connect'),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

