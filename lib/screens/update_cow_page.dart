import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jeyam_dairy/database_helper.dart';
import 'package:jeyam_dairy/theme.dart';
import 'package:intl/intl.dart';

// 1. THE SCANNER PAGE (Updated with Custom Image Animation)
class UpdateCowScanPage extends StatefulWidget {
  const UpdateCowScanPage({super.key});

  @override
  State<UpdateCowScanPage> createState() => _UpdateCowScanPageState();
}

class _UpdateCowScanPageState extends State<UpdateCowScanPage>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  String _buffer = "";
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // Slower breathing
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) async {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_buffer.isNotEmpty) {
          _findAndEdit(_buffer);
          _buffer = "";
        }
      } else if (event.character != null) {
        if (RegExp(r'[0-9]').hasMatch(event.character!)) {
          _buffer += event.character!;
        }
      }
    }
  }

  void _findAndEdit(String rfid) async {
    final cow = await DatabaseHelper.instance.getCowByRFID(rfid);
    if (!mounted) return;

    if (cow != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => EditCowForm(cowData: cow)),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("RFID $rfid not found!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.green[50],
        appBar: AppBar(
          title: const Text("Scan Cow to Update"),
          backgroundColor: Colors.green[800],
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ANIMATED HOME IMAGE
              ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.05).animate(
                  CurvedAnimation(
                    parent: _pulseController,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: Container(
                  width: 200, // Slightly larger for this screen
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  // THE NEW IMAGE
                  child: ClipOval(
                    child: Image.asset(
                      'assets/Home_Image.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                "Scan RFID Tag Now",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[900],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Waiting for input...",
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 2. THE EDIT FORM (UNCHANGED)
class EditCowForm extends StatefulWidget {
  final Map<String, dynamic> cowData;
  const EditCowForm({super.key, required this.cowData});

  @override
  State<EditCowForm> createState() => _EditCowFormState();
}

class _EditCowFormState extends State<EditCowForm> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _purchaseDate;
  late TextEditingController _calfBirthDate;
  late TextEditingController _lastInjection;
  int? _milkCycle;
  String? _currentStage;

  @override
  void initState() {
    super.initState();
    var c = widget.cowData;
    _purchaseDate = TextEditingController(text: c['PurchaseDate']);
    _calfBirthDate = TextEditingController(text: c['CalfBirthDate']);
    _lastInjection = TextEditingController(text: c['LastInjectionDate']);
    _milkCycle = c['CurrentMilkingCycle'];
    _currentStage = c['CurrentStage'];
  }

  Future<void> _update() async {
    if (_formKey.currentState!.validate()) {
      Map<String, dynamic> updatedCow = Map.from(widget.cowData);
      updatedCow['PurchaseDate'] = _purchaseDate.text;
      updatedCow['CalfBirthDate'] = _calfBirthDate.text;
      updatedCow['LastInjectionDate'] = _lastInjection.text;
      updatedCow['CurrentMilkingCycle'] = _milkCycle;
      updatedCow['CurrentStage'] = _currentStage;

      await DatabaseHelper.instance.updateCow(updatedCow);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Cow Updated!")));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var c = widget.cowData;
    int birthYear = int.parse(c['BirthYear']);
    int age = DateTime.now().year - birthYear;
    String? imagePath = c['CowPicturePath'];

    return Scaffold(
      backgroundColor: Colors.green[50],
      appBar: AppBar(
        title: Text("Update Cow #${c['RFID']}"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildCowImage(imagePath),
              const SizedBox(height: 20),

              _buildReadOnlyCard("Cow Identity", [
                "Cow ID: ${c['CowID']}",
                "RFID Tag: ${c['RFID']}",
                "Age: $age Years (Born $birthYear)",
              ]),
              const SizedBox(height: 15),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Update Information",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                          fontSize: 18,
                        ),
                      ),
                      Divider(color: Colors.green[200]),
                      const SizedBox(height: 10),
                      _buildDateField("Calf Birth Date", _calfBirthDate),
                      const SizedBox(height: 10),
                      _buildDateField("Last Injection Date", _lastInjection),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _milkCycle,
                        decoration: const InputDecoration(
                          labelText: "Lactation Cycle",
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(10, (i) => i + 1)
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text("Cycle $e"),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _milkCycle = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _currentStage,
                        decoration: const InputDecoration(
                          labelText: "Current Stage",
                          border: OutlineInputBorder(),
                        ),
                        items: ["Milking", "Dry", "Pregnant"]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _currentStage = v),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.green[800]!),
                        foregroundColor: Colors.green[800],
                      ),
                      child: const Text("CANCEL"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _update,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text("UPDATE"),
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

  Widget _buildCowImage(String? path) {
    bool hasValidImage =
        path != null && path.isNotEmpty && File(path).existsSync();
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.green[700]!, width: 4),
        image: hasValidImage
            ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: hasValidImage
          ? null
          : const Icon(Icons.cruelty_free, size: 60, color: Colors.grey),
    );
  }

  Widget _buildReadOnlyCard(String title, List<String> lines) {
    return Card(
      color: Colors.green[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
                fontSize: 16,
              ),
            ),
            Divider(color: Colors.green[200]),
            ...lines.map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(l, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today),
      ),
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2010),
          lastDate: DateTime(2030),
        );
        if (picked != null)
          controller.text = DateFormat('yyyy-MM-dd').format(picked);
      },
    );
  }
}
