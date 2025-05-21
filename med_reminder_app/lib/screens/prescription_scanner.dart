// [IMPORTS]
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';

import '/mlkit_ocr_helper.dart';
import 'medicine_options.dart';
import 'medicine_history.dart';
import 'user_profile.dart';
import 'medicine_reminder.dart';
import 'shop_lists.dart';

class PrescriptionScanner extends StatefulWidget {
  const PrescriptionScanner({super.key});

  @override
  State<PrescriptionScanner> createState() => _PrescriptionScannerState();
}

class _PrescriptionScannerState extends State<PrescriptionScanner> {
  File? _image;
  String _extractedText = '';
  bool _isProcessing = false;
  int _secondsRemaining = 0;
  Timer? _countdownTimer;

  final picker = ImagePicker();

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _getImage(ImageSource source) async {
    try {
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile == null) return;

      if (!mounted) return;
      setState(() {
        _isProcessing = true;
        _secondsRemaining = 60;
      });

      _startCountdown();

      File file = File(pickedFile.path);
      print("🖼️ Original Image Path: ${file.path}");

      final bytes = await file.readAsBytes();
      final original = img.decodeImage(bytes);

      if (original == null) throw Exception('Image could not be decoded');

      img.Image preprocessed = img.copyResize(original, width: 1024);
      preprocessed = img.grayscale(preprocessed);
      preprocessed = img.adjustColor(preprocessed, contrast: 1.4, brightness: 0.1);
      img.gaussianBlur(preprocessed, radius: 1);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final processedPath = '${file.parent.path}/processed_$timestamp.jpg';
      final processedFile = File(processedPath)..writeAsBytesSync(img.encodeJpg(preprocessed));

      print("🧪 Processed image saved at: $processedPath");

      if (!mounted) return;
      setState(() {
        _image = processedFile;
        _extractedText = '';
      });

      String ocrText = await extractTextFromImage(processedFile);
      print("📜 Recognized Text: '$ocrText'");

      if (ocrText.trim().isEmpty) {
        setState(() {
          _image = null;
          _extractedText = '';
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OCR failed: Please try again with a clearer image.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _sendTextToServer(ocrText);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _sendTextToServer(String ocrText) async {
    if (_image == null) return;

    const flaskUrl = 'http://127.0.0.1:5000/process_prescription';

    try {
      var request = http.MultipartRequest('POST', Uri.parse(flaskUrl));
      request.files.add(await http.MultipartFile.fromPath('image', _image!.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final json = jsonDecode(responseData);

        final List<dynamic> medicines = json['medicines_found'];
        setState(() {
          _extractedText = medicines.join(', ');
        });
      } else {
        throw Exception('Flask error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Flask API error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<String> extractMedicines(String text) {
    return text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _navigateTo(Widget screen) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Prescription')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _image != null
                  ? Card(
                key: ValueKey(_image),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_image!),
                    ),
                    if (_isProcessing)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Shimmer.fromColors(
                                  baseColor: Colors.white70,
                                  highlightColor: Colors.grey.shade300,
                                  child: const Text(
                                    'Processing...',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$_secondsRemaining seconds remaining',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
                  : const SizedBox(
                height: 200,
                child: Center(child: Text('No image selected.')),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _getImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Picture'),
                ),
                FilledButton.icon(
                  onPressed: () => _getImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Choose from Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 30),
            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else if (_extractedText.isNotEmpty) ...[
              const Text('Extracted Text:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_extractedText, style: const TextStyle(fontSize: 14)),
              ),
            ],
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: _extractedText.isEmpty
                  ? null
                  : () => _navigateTo(MedicineOptionsScreen(
                  medicineNames: extractMedicines(_extractedText))),
              icon: const Icon(Icons.medication),
              label: const Text('Show Medicine Options'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _navigateTo(const MedicineHistoryScreen()),
              icon: const Icon(Icons.history),
              label: const Text('My Orders'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _navigateTo(const UserProfileScreen()),
              icon: const Icon(Icons.person),
              label: const Text('User Profile'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _navigateTo(const MedicineReminderScreen()),
              icon: const Icon(Icons.alarm),
              label: const Text('Medicine Reminder'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _extractedText.isEmpty
                  ? null
                  : () => _navigateTo(ShopListScreen(
                  medicineNames: extractMedicines(_extractedText))),
              icon: const Icon(Icons.local_pharmacy),
              label: const Text('Find Nearby Shops'),
            ),
          ],
        ),
      ),
    );
  }
}