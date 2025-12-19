import 'dart:io'; // Needed for File handling
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart'; // New Package
import 'package:path_provider/path_provider.dart'; // To save locally
import 'package:path/path.dart' as syspath; // To manage file names
import '../database_helper.dart';
import '../theme.dart';

class AddCowPage extends StatefulWidget {
  const AddCowPage({super.key});

  @override
  State<AddCowPage> createState() => _AddCowPageState();
}

class _AddCowPageState extends State<AddCowPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _rfidController = TextEditingController();
  final TextEditingController _purchaseDateController = TextEditingController();
  final TextEditingController _calfBirthDateController =
      TextEditingController();
  final TextEditingController _injectionDateController =
      TextEditingController();

  // State Variables
  File? _storedImage; // Holds the image file locally
  int? _selectedBirthYear;
  int? _selectedAge;
  int? _milkCycle;
  String? _currentStage;

  @override
  void initState() {
    super.initState();
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _purchaseDateController.text = today;
    _calfBirthDateController.text = today;
  }

  // --- IMAGE PICKER LOGIC ---
  Future<void> _takePicture() async {
    // Show dialog to choose Camera or Gallery
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        height: 150,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Choose Image Source",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _processImage(ImageSource.camera);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Camera"),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _processImage(ImageSource.gallery);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.photo),
                  label: const Text("Gallery"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processImage(ImageSource source) async {
    final picker = ImagePicker();
    final imageFile = await picker.pickImage(
      source: source,
      maxWidth: 600, // Optimize size
    );

    if (imageFile == null) return;

    // 1. Update UI immediately
    setState(() {
      _storedImage = File(imageFile.path);
    });

    // 2. Save permanent copy to App Documents
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = syspath.basename(imageFile.path);
    final savedImage = await File(
      imageFile.path,
    ).copy('${appDir.path}/$fileName');

    // 3. Update the stored file reference to the PERMANENT path
    setState(() {
      _storedImage = savedImage;
    });
  }

  // --- SAVE LOGIC ---
  void _saveCow() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedBirthYear == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Birth Year')),
        );
        return;
      }

      Map<String, dynamic> row = {
        'RFID': _rfidController.text,
        'PurchaseDate': _purchaseDateController.text,
        'BirthYear': _selectedBirthYear.toString(),
        'CurrentMilkingCycle': _milkCycle,
        'CurrentStage': _currentStage,
        'CalfBirthDate': _calfBirthDateController.text,
        'LastInjectionDate': _injectionDateController.text,
        // SAVE THE PATH (String), not the file itself
        'CowPicturePath': _storedImage?.path ?? '',
      };

      try {
        await DatabaseHelper.instance.addCow(row);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cow Added Successfully!')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: RFID ${_rfidController.text} already exists!',
            ),
          ),
        );
      }
    }
  }

  // --- UI HELPERS ---
  Future<void> _selectDate(TextEditingController controller) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _onBirthYearChanged(int? year) {
    if (year != null) {
      setState(() {
        _selectedBirthYear = year;
        _selectedAge = DateTime.now().year - year;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add New Cow")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 1. IMAGE PICKER SECTION
              GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.emeraldGreen, width: 2),
                    image: _storedImage != null
                        ? DecorationImage(
                            image: FileImage(_storedImage!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _storedImage == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.camera_alt,
                              size: 40,
                              color: Colors.grey,
                            ),
                            Text(
                              "Add Photo",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),

              // 2. RFID Section
              _buildCard(
                title: "Cow Identity",
                child: TextFormField(
                  controller: _rfidController,
                  decoration: const InputDecoration(
                    labelText: "RFID Tag Number",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.nfc),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) => value!.isEmpty ? "Enter RFID" : null,
                ),
              ),

              // 3. Dates & Age
              _buildCard(
                title: "Lifecycle Details",
                child: Column(
                  children: [
                    _buildDateField("Purchase Date", _purchaseDateController),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedBirthYear,
                            decoration: const InputDecoration(
                              labelText: "Birth Year",
                              border: OutlineInputBorder(),
                            ),
                            items:
                                List.generate(
                                      20,
                                      (index) => DateTime.now().year - index,
                                    )
                                    .map(
                                      (year) => DropdownMenuItem(
                                        value: year,
                                        child: Text("$year"),
                                      ),
                                    )
                                    .toList(),
                            onChanged: _onBirthYearChanged,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: TextEditingController(
                              text: _selectedAge?.toString() ?? "",
                            ),
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: "Age",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildDateField(
                      "Calf Birth Date",
                      _calfBirthDateController,
                    ),
                    const SizedBox(height: 10),
                    _buildDateField(
                      "Last Injection Date",
                      _injectionDateController,
                    ),
                  ],
                ),
              ),

              // 4. Status
              _buildCard(
                title: "Production Status",
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
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
                      onChanged: (val) => setState(() => _milkCycle = val),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: "Current Stage",
                        border: OutlineInputBorder(),
                      ),
                      items: ["Milking", "Dry", "Pregnant"]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => _currentStage = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              // 5. Buttons
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
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveCow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emeraldGreen,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text("SUBMIT"),
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

  Widget _buildCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.emeraldGreen,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            const SizedBox(height: 10),
            child,
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
      onTap: () => _selectDate(controller),
    );
  }
}
