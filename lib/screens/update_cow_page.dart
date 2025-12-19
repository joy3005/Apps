import 'dart:io'; // Needed for FileImage
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jeyam_dairy/database_helper.dart';
import 'package:jeyam_dairy/theme.dart';
import 'package:intl/intl.dart';

// 1. THE SCANNER PAGE (Entry Point) - No Changes Here
class UpdateCowScanPage extends StatefulWidget {
  const UpdateCowScanPage({super.key});

  @override
  State<UpdateCowScanPage> createState() => _UpdateCowScanPageState();
}

class _UpdateCowScanPageState extends State<UpdateCowScanPage> {
  final FocusNode _focusNode = FocusNode();
  String _buffer = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
        appBar: AppBar(title: const Text("Scan Cow to Update")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.qr_code_scanner,
                size: 100,
                color: AppTheme.emeraldGreen,
              ),
              SizedBox(height: 20),
              Text(
                "Scan RFID Tag Now",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                "Use keyboard to type ID + Enter for Simulator",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 2. THE EDIT FORM (With Image)
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
      appBar: AppBar(title: Text("Update Cow #${c['RFID']}")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 1. COW IMAGE (New)
              _buildCowImage(imagePath),
              const SizedBox(height: 20),

              // 2. READ ONLY FIELDS
              _buildReadOnlyCard("Cow Identity", [
                "Cow ID: ${c['CowID']}",
                "RFID Tag: ${c['RFID']}",
                "Age: $age Years (Born $birthYear)",
              ]),
              const SizedBox(height: 15),

              // 3. EDITABLE FIELDS
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Update Information",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.emeraldGreen,
                          fontSize: 16,
                        ),
                      ),
                      const Divider(),
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
              // 4. BUTTONS
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text("CANCEL"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _update,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emeraldGreen,
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

  // --- NEW HELPER FOR IMAGE ---
  Widget _buildCowImage(String? path) {
    bool hasValidImage =
        path != null && path.isNotEmpty && File(path).existsSync();

    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.emeraldGreen, width: 3),
        image: hasValidImage
            ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover)
            : null,
      ),
      child: hasValidImage
          ? null
          : const Icon(
              Icons.cruelty_free,
              size: 60,
              color: Colors.grey,
            ), // Placeholder icon
    );
  }

  Widget _buildReadOnlyCard(String title, List<String> lines) {
    return Card(
      color: AppTheme.softGray, // Using theme color
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.emeraldGreen,
              ),
            ),
            const Divider(),
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
