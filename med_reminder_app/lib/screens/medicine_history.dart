import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MedicineHistoryScreen extends StatefulWidget {
  const MedicineHistoryScreen({super.key});

  @override
  State<MedicineHistoryScreen> createState() => _MedicineHistoryScreenState();
}

class _MedicineHistoryScreenState extends State<MedicineHistoryScreen> {
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _history = prefs.getStringList('buying_history') ?? [];
    });
  }

  Future<void> _clearHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('buying_history');
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearHistory,
          )
        ],
      ),
      body: _history.isEmpty
          ? const Center(child: Text('No purchases yet.'))
          : ListView.builder(
        itemCount: _history.length,
        itemBuilder: (context, index) {
          return ListTile(
            leading: const Icon(Icons.medical_services),
            title: Text(_history[index]),
          );
        },
      ),
    );
  }
}
