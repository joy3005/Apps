import 'dart:async';
import 'dart:convert'; // For utf8 decoding
import 'dart:typed_data'; // For Bluetooth data handling
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart'; // Bluetooth Package
import 'package:intl/intl.dart';
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

class _HomePageState extends State<HomePage> {
  // --- LOGIC VARIABLES ---
  final FocusNode _keyboardFocusNode = FocusNode();
  String _inputBuffer = "";
  String _bluetoothBuffer = "";
  Timer? _milkTimer;
  Map<String, dynamic>? _currentCowData;

  // --- BLUETOOTH VARIABLES ---
  BluetoothConnection? _connection;
  bool _isConnecting = false;
  bool _isConnected = false;

  // UI Status Variables
  String _statusMessage = "Ready for Scanning";
  String _subStatusMessage = "Waiting for Cow RFID...";
  Color _statusColor = AppTheme.emeraldGreen;
  IconData _statusIcon = Icons.sensors;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
      // AUTO-CONNECT STARTUP: Try to connect immediately when app opens
      _connectToScale();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _milkTimer?.cancel();
    _connection?.dispose();
    super.dispose();
  }

  // --- 1. INTELLIGENT CONNECT LOGIC ---
  Future<void> _connectToScale() async {
    // If already connected or currently trying, do nothing
    if (_isConnected || _isConnecting) return;

    setState(() => _isConnecting = true);

    try {
      // PERMISSION CHECK (Critical for Android 12+)
      // This asks the user "Allow Bluetooth?" if not already granted
      await FlutterBluetoothSerial.instance.requestEnable();

      // Get Paired Devices
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance
          .getBondedDevices();

      // SMART FINDER: Look for DSD Tech / HC-05 / Serial Adapter
      BluetoothDevice? scale;
      try {
        scale = devices.firstWhere(
          (d) =>
              (d.name ?? "").toUpperCase().contains("DSD") ||
              (d.name ?? "").toUpperCase().contains("SH-") ||
              (d.name ?? "").toUpperCase().contains("HC-05"),
        );
      } catch (e) {
        // Fallback: If no specific name found, try the first paired device
        if (devices.isNotEmpty) scale = devices.first;
      }

      if (scale == null) {
        // Only show error if we are actively expecting a device
        // We fail silently in background to avoid annoying popups
        setState(() => _isConnecting = false);
        return;
      }

      // Connect
      // Note: toAddress automatically uses the Standard Serial Port UUID (SPP)
      BluetoothConnection connection = await BluetoothConnection.toAddress(
        scale.address,
      );

      if (mounted) {
        setState(() {
          _connection = connection;
          _isConnected = true;
          _isConnecting = false;
        });

        // VISUAL CONFIRMATION
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connected to Scale: ${scale.name}")),
        );

        // Listen for Data
        connection.input!.listen(_onBluetoothDataReceived).onDone(() {
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("Scale Disconnected")));
          }
        });
      }
    } catch (e) {
      // Connection failed
      print("Connect Error: $e");
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  // --- 2. DATA LISTENER (Runs in Background) ---
  void _onBluetoothDataReceived(Uint8List data) {
    String incoming = utf8.decode(data);
    _bluetoothBuffer += incoming;

    // Wait for a "End of Line" (Enter key from scale)
    // We check for \n (Newline) OR \r (Carriage Return) to be safe
    if (_bluetoothBuffer.contains('\n') || _bluetoothBuffer.contains('\r')) {
      // Clean the data: remove letters/spaces, keep numbers and decimal points
      String cleanData = _bluetoothBuffer.replaceAll(RegExp(r'[^\d.]'), '');
      _bluetoothBuffer = "";

      // ONLY SAVE IF WE ARE WAITING FOR A COW
      if (cleanData.isNotEmpty && _currentCowData != null) {
        double? weight = double.tryParse(cleanData);
        if (weight != null && weight > 0) {
          _saveMilkEntry(weight);
        }
      }
    }
  }

  // --- 3. COW SCAN LOGIC (Triggers Connection Check) ---
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
    _resetLogic(); // Reset timers
    setState(() => _statusMessage = "Verifying...");

    final cowData = await DatabaseHelper.instance.getCowByRFID(rfid);

    if (cowData != null) {
      setState(() {
        _currentCowData = cowData;
        _statusMessage = "Cow #${cowData['RFID']}";
        _subStatusMessage = "Verified. Waiting for Milk Weight...";
        _statusColor = AppTheme.goldenOrange;
        _statusIcon = Icons.scale;
      });

      // AUTO-CONNECT CHECK:
      // "Whenever a cow is scanned, make sure we are dialed in"
      if (!_isConnected) {
        _connectToScale();
      }

      _startMilkTimer();
    } else {
      setState(() {
        _statusMessage = "Unknown Tag";
        _subStatusMessage = "RFID: $rfid not found.";
        _statusColor = Colors.redAccent;
        _statusIcon = Icons.error_outline;
      });
      Future.delayed(const Duration(seconds: 3), _resetLogic);
    }
  }

  // --- REST OF THE LOGIC (Unchanged) ---
  void _startMilkTimer() {
    _milkTimer = Timer(const Duration(minutes: 5), () {
      setState(() {
        _statusMessage = "Timeout";
        _subStatusMessage = "No milk recorded in 5 mins.";
        _statusColor = Colors.grey;
      });
      Future.delayed(const Duration(seconds: 4), _resetLogic);
    });
  }

  Future<void> _saveMilkEntry(double weight) async {
    if (_currentCowData == null) return;
    _milkTimer?.cancel();

    final now = DateTime.now();
    final hour = now.hour;
    String session = (hour < 12) ? "Morning" : "Evening";

    Map<String, dynamic> milkRow = {
      'CowID': _currentCowData!['CowID'],
      'Date': DateFormat('yyyy-MM-dd').format(now),
      'Time': session,
      'CycleNumber': _currentCowData!['CurrentMilkingCycle'],
      'MorningMilk': (session == "Morning") ? weight : 0,
      'EveningMilk': (session == "Evening") ? weight : 0,
      'TotalMilk': weight,
      'IsSynced': 0,
    };

    await DatabaseHelper.instance.insertMilkRecord(milkRow);

    setState(() {
      _statusMessage = "Saved!";
      _subStatusMessage = "$weight Liters recorded for $session.";
      _statusColor = AppTheme.emeraldGreen;
      _statusIcon = Icons.check_circle;
    });

    Future.delayed(const Duration(seconds: 2), _resetLogic);
  }

  void _resetLogic() {
    _milkTimer?.cancel();
    setState(() {
      _currentCowData = null;
      _statusMessage = "Ready for Scanning";
      _subStatusMessage = "Waiting for Cow RFID...";
      _statusColor = AppTheme.emeraldGreen;
      _statusIcon = Icons.sensors;
      _inputBuffer = "";
    });
    _keyboardFocusNode.requestFocus();
  }

  // --- MANUAL ENTRY POPUP ---
  void _showManualInput() {
    TextEditingController manualController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Manual Entry"),
        content: TextField(
          controller: manualController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Enter Cow RFID",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            Navigator.pop(ctx);
            if (manualController.text.isNotEmpty)
              _processCowScan(manualController.text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (manualController.text.isNotEmpty)
                _processCowScan(manualController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emeraldGreen,
            ),
            child: const Text("SCAN"),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Jeyam Dairy Farms"),
          actions: [
            // BLUETOOTH STATUS ICON (Now purely visual, no click needed)
            IconButton(
              icon: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      _isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                    ),
              color: _isConnected ? Colors.blueAccent : Colors.grey,
              tooltip: _isConnected ? "Scale Connected" : "Scale Disconnected",
              onPressed:
                  _connectToScale, // Still clickable if manual force needed
            ),
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: "Manual Entry",
              onPressed: _showManualInput,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildTopButtons(),
              const SizedBox(height: 15),
              Expanded(child: _buildLiveStatusCard()),
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

  // --- UI WIDGETS ---
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

  Widget _buildLiveStatusCard() {
    return Card(
      color: _statusColor,
      elevation: 6,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_statusIcon, size: 80, color: Colors.white),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _subStatusMessage,
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
