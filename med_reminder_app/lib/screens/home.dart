import 'package:flutter/material.dart';
import 'medicine_reminder.dart';
import 'medicine_options.dart';
import 'prescription_scanner.dart';
import 'user_profile.dart';
import 'buying_history.dart'; // Assuming this is already done

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    PrescriptionScanner(),
    MedicineOptionsScreen(medicineNames: const []),
    MedicineReminderScreen(),
    BuyingHistoryScreen(),
    UserProfileScreen(),
  ];

  final List<String> _titles = [
    'Prescription Scanner',
    'Buy Medicines',
    'Reminders',
    'History',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_currentIndex])),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.document_scanner), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.medical_services), label: 'Buy'),
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Remind'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
