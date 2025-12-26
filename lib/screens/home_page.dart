import 'dart:async';
import 'dart:convert'; // For utf8 decoding
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:jeyam_dairy/theme.dart';
import '../database_helper.dart';
import '../services/sync_service.dart';
import 'add_cow_page.dart';
import 'report_page.dart';
import 'update_cow_page.dart';
import 'cow_metrics_page.dart';

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
  static const int _requiredStableReadings = 5;

  // --- BLE VARIABLES ---
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _valueSubscription;
  bool _isScanning = false;
  String _bleStatus = "Initializing...";

  // --- UI ANIMATION CONTROLLERS ---
  late AnimationController _timerController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _handleTimeout();
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // Slower, deeper breath
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
      _initBLE();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _timerController.dispose();
    _pulseController.dispose();
    _scanSubscription?.cancel();
    _valueSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  // --- BLE & LOGIC METHODS ---
  Future<void> _initBLE() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _startScan();
      } else {
        if (mounted) setState(() => _bleStatus = "Bluetooth OFF");
      }
    });
  }

  void _startScan() async {
    if (_connectedDevice != null || _isScanning) return;
    if (mounted) {
      setState(() {
        _isScanning = true;
        _bleStatus = "Scanning for Scale...";
      });
    }
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          bool nameMatch = (r.device.platformName == r'RS232\485');
          if (!nameMatch) {
            nameMatch = (r.advertisementData.localName == r'RS232\485');
          }
          if (nameMatch) {
            await FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            break;
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _bleStatus = "Scan Error");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      if (mounted) setState(() => _bleStatus = "Connecting...");
      await device.connect(autoConnect: false, license: License.free);
      if (!mounted) return;
      setState(() {
        _connectedDevice = device;
        _bleStatus = "Connected to Scale";
        _isScanning = false;
      });
      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? targetChar;
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
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _bleStatus = "Retrying Connection...");
      _connectedDevice = null;
      _isScanning = false;
      Future.delayed(const Duration(seconds: 2), _startScan);
    }
  }

  void _onBleDataReceived(List<int> rawData) {
    if (_currentCowData == null) return;
    String ascii = utf8.decode(rawData).trim();
    String clean = ascii.replaceAll(RegExp(r'[^\d.]'), '');
    if (clean.isEmpty) return;
    double? currentWeight = double.tryParse(clean);

    if (currentWeight != null && currentWeight > 0.0) {
      if (_lastWeightReading != null) {
        double difference = (currentWeight - _lastWeightReading!).abs();
        if (difference <= 0.1) {
          _stableReadingsCount++;
          setState(() {});
          if (_stableReadingsCount >= _requiredStableReadings) {
            _saveMilkEntry(currentWeight);
          }
        } else {
          _stableReadingsCount = 0;
          _lastWeightReading = currentWeight;
          setState(() {});
        }
      } else {
        _lastWeightReading = currentWeight;
        _stableReadingsCount = 0;
      }
    }
  }

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
    _resetLogic(fullReset: false);
    final cowData = await DatabaseHelper.instance.getCowByRFID(rfid);

    if (cowData != null) {
      setState(() {
        _currentCowData = cowData;
      });
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
    if (_currentCowData == null) return;
    _timerController.stop();

    int cowId = _currentCowData!['CowID'];
    int cycle = _currentCowData!['CurrentMilkingCycle'];

    setState(() {
      _currentCowData = null;
      _timerController.reset();
      _stableReadingsCount = 0;
      _lastWeightReading = null;
    });

    final now = DateTime.now();
    final hour = now.hour;
    String session = (hour < 12) ? "Morning" : "Evening";

    Map<String, dynamic> milkRow = {
      'CowID': cowId,
      'Date': DateFormat('yyyy-MM-dd').format(now),
      'Time': session,
      'CycleNumber': cycle,
      'MorningMilk': (session == "Morning") ? weight : 0,
      'EveningMilk': (session == "Evening") ? weight : 0,
      'TotalMilk': weight,
      'IsSynced': 0,
    };

    await DatabaseHelper.instance.insertMilkRecord(milkRow);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                "SAVED: $weight Liters",
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    _keyboardFocusNode.requestFocus();
  }

  void _resetLogic({required bool fullReset}) {
    _timerController.stop();
    _timerController.reset();
    _lastWeightReading = null;
    _stableReadingsCount = 0;
    if (fullReset) setState(() => _currentCowData = null);
    _keyboardFocusNode.requestFocus();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    bool isCowActive = _currentCowData != null;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.green[50],
        appBar: AppBar(
          title: const Text(
            "Jeyam Dairy Farms",
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.green[800],
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildActionGrid(),
                const SizedBox(height: 24),
                Expanded(child: _buildMainStatusCard(isCowActive)),
                const SizedBox(height: 24),
                _buildReportButtons(),
                const SizedBox(height: 16),
                _buildSyncButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildHeaderBtn(
            icon: Icons.add_circle_outline,
            label: "Add Cow",
            color: Colors.green[700]!,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddCowPage()),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildHeaderBtn(
            icon: Icons.qr_code_scanner,
            label: "Update",
            color: Colors.blue[700]!,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UpdateCowScanPage(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainStatusCard(bool isCowActive) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green[100]!, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCowActive) _buildActiveCowUI() else _buildIdleUI(),
            ],
          ),
        ),
      ),
    );
  }

  // --- IDLE STATE: PULSING HOME IMAGE ---
  Widget _buildIdleUI() {
    bool isConnected = _bleStatus.contains("Connected");
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: Tween(begin: 1.0, end: 1.05).animate(
            // Subtle breathing
            CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 180, // Adjust size as needed
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green[50] : Colors.orange[50],
              boxShadow: [
                BoxShadow(
                  color: isConnected
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            // THE NEW IMAGE LOGIC
            child: ClipOval(
              child: Image.asset(
                'assets/Home_Image.png', // <--- YOUR NEW IMAGE
                fit: BoxFit.cover, // Fills the circle nicely
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),
        Text(
          "Ready to Scan",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.green[900],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isConnected
                ? Colors.green.withOpacity(0.1)
                : Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_searching,
                size: 16,
                color: isConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                _bleStatus,
                style: TextStyle(
                  color: isConnected ? Colors.green[700] : Colors.orange[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- ACTIVE STATE (UNCHANGED) ---
  Widget _buildActiveCowUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Cow #${_currentCowData!['RFID']}",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.green[900],
          ),
        ),
        const SizedBox(height: 30),
        Icon(Icons.scale, size: 80, color: Colors.green[700]),
        const SizedBox(height: 30),
        AnimatedBuilder(
          animation: _timerController,
          builder: (context, child) {
            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Weighing Window",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    Text(
                      "${(60 - (_timerController.value * 60)).toInt()}s",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: 1.0 - _timerController.value,
                  backgroundColor: Colors.grey[200],
                  color: Colors.green[600],
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Text(
          _lastWeightReading != null
              ? "${_lastWeightReading!.toStringAsFixed(2)} kg"
              : "--.-- kg",
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.green[800],
          ),
        ),
      ],
    );
  }

  Widget _buildReportButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildFooterBtn(
            "Reports",
            Icons.bar_chart,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ReportPage()),
            ),
            Colors.green[700]!,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildFooterBtn(
            "Cow Metrics",
            Icons.insights,
            _showCowMetricsDialog, // Triggers the Scan/Manual Dialog
            Colors.purple[700]!,
          ),
        ),
      ],
    );
  }

  Widget _buildFooterBtn(
    String label,
    IconData icon,
    VoidCallback onTap,
    Color color,
  ) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.green[800],
        elevation: 1,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSyncButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          // 1. LOADING DIALOG (Farm Theme)
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => Center(
              child: CircularProgressIndicator(
                color: Colors.green[800], // Farm Green Spinner
              ),
            ),
          );

          String result = await SyncService.syncToCloud();

          if (mounted) {
            Navigator.pop(context); // Close Loading

            // 2. SUCCESS/ERROR POPUP (Farm Theme)
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Colors.green[50], // Farm Background
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.green[200]!, width: 2),
                ),
                title: Row(
                  children: [
                    Icon(
                      result == "Success" ? Icons.check_circle : Icons.error,
                      color: result == "Success"
                          ? Colors.green[700]
                          : Colors.red,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      result == "Success" ? "Sync Complete" : "Sync Failed",
                      style: TextStyle(
                        color: Colors.green[900],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  result == "Success"
                      ? "All farm data has been successfully uploaded to the cloud."
                      : result,
                  style: TextStyle(color: Colors.green[900], fontSize: 16),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "OK",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }
        },
        icon: const Icon(Icons.cloud_upload),
        label: const Text("Sync Data to Cloud"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange[800],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  void _showCowMetricsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Cow Metrics"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("How do you want to find the cow?"),
              const SizedBox(height: 20),
              // Option 1: SCAN
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _startScanForMetrics(); // Re-use scan logic or navigate
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text("Scan RFID Tag"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 10),
              // Option 2: MANUAL
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showManualEntryDialog();
                },
                icon: const Icon(Icons.keyboard),
                label: const Text("Enter ID Manually"),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 1. UPDATED MANUAL ENTRY DIALOG (Asks for CowID)
  void _showManualEntryDialog() {
    TextEditingController idController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter Cow ID"), // Changed from RFID
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter the short Cow ID (e.g. 1, 5, 12)",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: idController,
              keyboardType: TextInputType.number,
              // Limit input to numbers only
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "e.g. 5",
                prefixIcon: Icon(Icons.tag),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (idController.text.isNotEmpty) {
                // Parse the text to an Integer
                int? id = int.tryParse(idController.text);
                if (id != null) {
                  _navigateToMetricsById(id); // Call new ID function
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Please enter a valid number"),
                    ),
                  );
                }
              }
            },
            child: const Text("SEARCH"),
          ),
        ],
      ),
    );
  }

  // 2. NEW NAVIGATION FUNCTION (For CowID)
  void _navigateToMetricsById(int id) async {
    // Uses getCowById (Integer) instead of getCowByRFID (String)
    final cow = await DatabaseHelper.instance.getCowById(id);

    if (cow != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => CowMetricsPage(cowData: cow)),
      );
    } else {
      _showError("Cow ID #$id not found.");
    }
  }

  // Reuse logic to find cow and open Metrics Page
  void _startScanForMetrics() {
    // Navigate to a temporary scan page (UpdateCowScanPage logic can be reused or just a new simple one)
    // For simplicity, let's use a dialog listener here or navigate to a specialized scan page
    // Since we already have UpdateCowScanPage, we can create a similar "MetricsScanPage"
    // OR just use a simple listening dialog here.

    // Let's use the simple dialog listener approach for "Scan"
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ScanListenerDialog(),
    ).then((rfid) {
      if (rfid != null && rfid is String && rfid.isNotEmpty) {
        _navigateToMetrics(rfid);
      }
    });
  }

  void _navigateToMetrics(String rfid) async {
    final cow = await DatabaseHelper.instance.getCowByRFID(rfid);
    if (cow != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => CowMetricsPage(cowData: cow)),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Cow Not Found!")));
    }
  }
}

// --- MISSING DIALOG CLASS ---
class _ScanListenerDialog extends StatefulWidget {
  const _ScanListenerDialog();

  @override
  State<_ScanListenerDialog> createState() => _ScanListenerDialogState();
}

class _ScanListenerDialogState extends State<_ScanListenerDialog> {
  final FocusNode _focusNode = FocusNode();
  String _buffer = "";

  @override
  void initState() {
    super.initState();
    // Automatically request focus so the scanner input is captured immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        // Scanner sends ENTER at the end of the tag
        if (_buffer.isNotEmpty) {
          Navigator.pop(context, _buffer); // Return the RFID to the parent
        }
      } else if (event.character != null) {
        // Collect numeric characters
        if (RegExp(r'[0-9]').hasMatch(event.character!)) {
          setState(() {
            _buffer += event.character!;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Scan RFID Tag"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner, size: 60, color: Colors.green),
            const SizedBox(height: 20),
            const Text(
              "Please scan the cow's tag now...",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(
              _buffer.isEmpty ? "Waiting..." : "Reading: $_buffer",
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Cancel and return null
            child: const Text("CANCEL", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
