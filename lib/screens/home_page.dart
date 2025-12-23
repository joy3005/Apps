import 'dart:async';
import 'dart:convert'; // For utf8 decoding
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // NEW BLE PACKAGE
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:jeyam_dairy/theme.dart';
import '../database_helper.dart';
import '../services/sync_service.dart';
import 'add_cow_page.dart';
import 'report_page.dart';
import 'update_cow_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // --- LOGIC VARIABLES ---
  final FocusNode _keyboardFocusNode = FocusNode();
  String _inputBuffer = "";
  Map<String, dynamic>? _currentCowData;

  // Stabilization Logic
  double? _lastWeightReading;
  int _stableReadingsCount = 0;
  static const int _requiredStableReadings =
      5; // Needs 5 consistent packets to save

  // --- BLE VARIABLES ---
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _valueSubscription;
  bool _isScanning = false;
  String _bleStatus = "Initializing...";

  // --- UI TIMER ANIMATION ---
  late AnimationController _timerController;

  // The exact name you provided
  final String _targetDeviceName = "RS232\\485";

  @override
  void initState() {
    super.initState();

    // 60 Second Countdown Controller
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _handleTimeout();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
      _initBLE();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _timerController.dispose();
    _scanSubscription?.cancel();
    _valueSubscription?.cancel();
    // We disconnect to be clean, though for industrial apps keeping it open is okay
    _connectedDevice?.disconnect();
    super.dispose();
  }

  // --- 1. BLE AUTO-CONNECT LOGIC ---
  Future<void> _initBLE() async {
    // 1. Request Permissions
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // 2. Listener for connection state changes
    // CHANGED: Use 'FlutterBluePlus.adapterState' directly for V2.x
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _startScan();
      } else {
        if (mounted) {
          setState(() => _bleStatus = "Bluetooth OFF");
        }
      }
    });
  }

  void _startScan() async {
    // If already connected or scanning, skip
    if (_connectedDevice != null || _isScanning) return;

    if (mounted) {
      setState(() {
        _isScanning = true;
        _bleStatus = "Scanning for Scale...";
      });
    }

    try {
      // Start scanning (15s timeout)
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          // 1. EXACT RAW STRING MATCH (Verified Working)
          // The 'r' prefix tells Dart to ignore the backslash escape
          bool nameMatch = (r.device.platformName == r'RS232\485');

          // 2. FALLBACK (Check Local Name if Platform Name is empty)
          if (!nameMatch) {
            nameMatch = (r.advertisementData.localName == r'RS232\485');
          }

          if (nameMatch) {
            print(">>> FOUND SCALE: ${r.device.platformName} <<<");

            // CRITICAL STEP: Stop scanning before connecting
            await FlutterBluePlus.stopScan();

            _connectToDevice(r.device);
            break; // Stop loop immediately
          }
        }
      });
    } catch (e) {
      print("Scan Error: $e");
      if (mounted) setState(() => _bleStatus = "Scan Error: Check Permissions");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      if (mounted) setState(() => _bleStatus = "Connecting...");

      // CRITICAL: Use License.free for v2.0+
      // Using autoConnect: false is usually faster for direct connections
      await device.connect(autoConnect: false, license: License.free);

      if (!mounted) return;

      setState(() {
        _connectedDevice = device;
        _bleStatus = "Connected to Scale";
        _isScanning = false;
      });

      // Discover Services
      List<BluetoothService> services = await device.discoverServices();

      BluetoothCharacteristic? targetChar;

      // PRIORITY SEARCH: Look for standard Serial Service (FFE0/FFE1)
      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase().contains("ffe0")) {
          for (BluetoothCharacteristic c in service.characteristics) {
            if (c.uuid.toString().toLowerCase().contains("ffe1")) {
              targetChar = c;
              break;
            }
          }
        }
      }

      // FALLBACK SEARCH: If FFE1 not found, grab the first Notify/Indicate char
      if (targetChar == null) {
        for (BluetoothService service in services) {
          for (BluetoothCharacteristic c in service.characteristics) {
            if (c.properties.notify || c.properties.indicate) {
              targetChar = c;
              break;
            }
          }
          if (targetChar != null) break;
        }
      }

      if (targetChar != null) {
        _notifyCharacteristic = targetChar;
        await targetChar.setNotifyValue(true);
        _valueSubscription = targetChar.lastValueStream.listen(
          _onBleDataReceived,
        );
        print(">>> DATA STREAM ACTIVE <<<");
      } else {
        print("Error: No Data Characteristic Found");
      }
    } catch (e) {
      print("Connection Failed: $e");
      if (!mounted) return;
      setState(() => _bleStatus = "Connection Failed. Retrying...");
      _connectedDevice = null;
      _isScanning = false;

      // Retry Scan after 2 seconds
      Future.delayed(const Duration(seconds: 2), _startScan);
    }
  }

  // --- 2. DATA PROCESSING & STABILIZATION LOGIC ---
  void _onBleDataReceived(List<int> rawData) {
    // 1. LOGIC GATE: If no cow is scanned, ignore everything immediately.
    // This prevents recording random weights or wasting battery.
    if (_currentCowData == null) return;

    // 2. DECODE DATA
    // We clean the string to remove "ST,GS,+" or "kg" characters
    String ascii = utf8.decode(rawData).trim();
    String clean = ascii.replaceAll(RegExp(r'[^\d.]'), '');

    // Safety check for empty strings or bad packets
    if (clean.isEmpty) return;

    double? currentWeight = double.tryParse(clean);

    // 3. STABILIZATION LOGIC
    if (currentWeight != null && currentWeight > 0.0) {
      // If we have a previous reading to compare against
      if (_lastWeightReading != null) {
        // Calculate the difference between this reading and the last one
        double difference = (currentWeight - _lastWeightReading!).abs();

        // CHECK TOLERANCE (0.1 kg)
        // If the weight is effectively the same as the last packet...
        if (difference <= 0.1) {
          _stableReadingsCount++;

          // Debug log to verify it's working in the console
          print(
            "Stable Count: $_stableReadingsCount / $_requiredStableReadings (Weight: $currentWeight)",
          );

          // SUCCESS CONDITION: We reached your target (5)
          if (_stableReadingsCount >= _requiredStableReadings) {
            _saveMilkEntry(currentWeight);
          }
        } else {
          // UNSTABLE: Weight changed significantly! Reset the counter.
          // This happens when milk is being poured or the cow is moving.
          print(
            "Unstable! Resetting count. (Old: $_lastWeightReading, New: $currentWeight)",
          );
          _stableReadingsCount = 0;
          _lastWeightReading = currentWeight;
        }
      } else {
        // This is the very first reading of the session
        _lastWeightReading = currentWeight;
        _stableReadingsCount = 0;
      }
    }
  }

  void _checkStability(double weight) {
    // If this is the first reading, or different from last reading
    if (_lastWeightReading == null ||
        (weight - _lastWeightReading!).abs() > 0.05) {
      _lastWeightReading = weight;
      _stableReadingsCount = 0; // Reset counter, weight is changing
    } else {
      // Weight is consistent!
      _stableReadingsCount++;
    }

    // If we have N stable readings in a row, we accept it
    if (_stableReadingsCount >= _requiredStableReadings) {
      _saveMilkEntry(_lastWeightReading!);
    }
  }

  // --- 3. COW SCAN LOGIC ---
  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final String? char = event.character;
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_inputBuffer.isNotEmpty) {
          _processCowScan(_inputBuffer);
          _inputBuffer = "";
        }
      } else if (char != null) {
        if (RegExp(r'[0-9]').hasMatch(char)) {
          _inputBuffer += char;
        }
      }
    }
  }

  Future<void> _processCowScan(String rfid) async {
    _resetLogic(fullReset: false); // Clear previous cow data

    final cowData = await DatabaseHelper.instance.getCowByRFID(rfid);

    if (cowData != null) {
      setState(() {
        _currentCowData = cowData;
      });
      // START THE 60s TIMER
      _timerController.forward(from: 0.0);
    } else {
      _showError("Unknown Tag: $rfid");
    }
  }

  void _handleTimeout() {
    _resetLogic(fullReset: true);
    _showError("Time's up! No milk weighed.");
  }

  Future<void> _saveMilkEntry(double weight) async {
    // 1. PREVENT DOUBLE SAVES
    // If the gate is already closed (null), stop immediately.
    if (_currentCowData == null) return;

    // 2. STOP UI TIMER
    _timerController.stop();

    // 3. CAPTURE DATA LOCALLY
    // We grab the ID and Cycle NOW, because we are about to wipe _currentCowData
    int cowId = _currentCowData!['CowID'];
    int cycle = _currentCowData!['CurrentMilkingCycle'];

    // 4. CLOSE THE GATE IMMEDIATELY (The Critical Change)
    // By setting _currentCowData to null NOW, we ensure that any
    // new data coming from the scale in the next few milliseconds is IGNORED.
    setState(() {
      _currentCowData = null;
      _timerController.reset();
      _stableReadingsCount = 0;
      _lastWeightReading = null;
    });

    // 5. DATABASE OPERATIONS
    final now = DateTime.now();
    final hour = now.hour;
    String session = (hour < 12) ? "Morning" : "Evening";

    Map<String, dynamic> milkRow = {
      'CowID': cowId, // Use the local variable we captured
      'Date': DateFormat('yyyy-MM-dd').format(now),
      'Time': session,
      'CycleNumber': cycle, // Use the local variable
      'MorningMilk': (session == "Morning") ? weight : 0,
      'EveningMilk': (session == "Evening") ? weight : 0,
      'TotalMilk': weight,
      'IsSynced': 0,
    };

    await DatabaseHelper.instance.insertMilkRecord(milkRow);

    // 6. UI FEEDBACK
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("SAVED: $weight Liters"),
          backgroundColor: AppTheme.emeraldGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // 7. READY FOR NEXT COW
    // Ensure keyboard is focused so you can scan the next RFID immediately
    _keyboardFocusNode.requestFocus();
  }

  void _resetLogic({required bool fullReset}) {
    _timerController.stop();
    _timerController.reset();

    _lastWeightReading = null;
    _stableReadingsCount = 0;

    if (fullReset) {
      setState(() {
        _currentCowData = null;
      });
    }
    _keyboardFocusNode.requestFocus();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    bool isCowActive = _currentCowData != null;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Jeyam Dairy Farms"),
          centerTitle: true,
          // Removed Actions (No Bluetooth/Keyboard buttons)
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildTopButtons(),
              const SizedBox(height: 15),

              // EXPANDED SECTION WITH ANIMATED BACKGROUND
              Expanded(
                child: Stack(
                  children: [
                    // 1. The Background Timer Fill
                    if (isCowActive)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _timerController,
                          builder: (context, child) {
                            return FractionallySizedBox(
                              alignment: Alignment.bottomCenter,
                              heightFactor:
                                  1.0 - _timerController.value, // Drains down
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.emeraldGreen.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // 2. The Card Content
                    _buildLiveStatusCard(isCowActive),
                  ],
                ),
              ),

              const SizedBox(height: 15),
              _buildReportButtons(),
              const SizedBox(height: 10),
              _buildSyncButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveStatusCard(bool isCowActive) {
    return Card(
      elevation: 6,
      color: Colors.white.withOpacity(0.9), // Slightly transparent for effect
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // DYNAMIC ICON
            Icon(
              isCowActive ? Icons.scale : Icons.sensors,
              size: 80,
              color: isCowActive ? AppTheme.emeraldGreen : Colors.grey,
            ),
            const SizedBox(height: 20),

            // MAIN STATUS TEXT
            Text(
              isCowActive
                  ? "Cow #${_currentCowData!['RFID']}"
                  : "Ready to Scan",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isCowActive ? AppTheme.darkText : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            // SUB STATUS / TIMER
            if (isCowActive) ...[
              Text(
                "Waiting for Weigh Machine...",
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // Digital Timer Countdown
              AnimatedBuilder(
                animation: _timerController,
                builder: (context, child) {
                  int remaining = 60 - (_timerController.value * 60).toInt();
                  return Text(
                    "$remaining s",
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  );
                },
              ),
            ] else ...[
              Text(
                _bleStatus, // "Searching..." or "Connected"
                style: TextStyle(
                  fontSize: 16,
                  color: _bleStatus.contains("Connected")
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- UNCHANGED WIDGETS ---
  Widget _buildTopButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddCowPage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text("Add New Cow"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UpdateCowScanPage(),
              ),
            ),
            icon: const Icon(Icons.edit, color: AppTheme.emeraldGreen),
            label: const Text(
              "Update Cow",
              style: TextStyle(color: AppTheme.emeraldGreen),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppTheme.emeraldGreen, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ReportPage(isWeekly: true),
              ),
            ),
            icon: const Icon(Icons.calendar_view_week),
            label: const Text("Weekly Report"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.darkText,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ReportPage(isWeekly: false),
              ),
            ),
            icon: const Icon(Icons.calendar_month),
            label: const Text("Monthly Report"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.darkText,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const Center(child: CircularProgressIndicator()),
          );
          String result = await SyncService.syncToCloud();
          if (mounted) {
            Navigator.pop(context);
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(
                  result == "Success" ? "Sync Complete" : "Sync Failed",
                ),
                content: Text(result),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK"),
                  ),
                ],
              ),
            );
          }
        },
        icon: const Icon(Icons.cloud_upload),
        label: const Text("Sync Data to Cloud"),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.goldenOrange,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
