import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class MedicineOptionsScreen extends StatelessWidget {
  final List<String> medicineNames;

  const MedicineOptionsScreen({super.key, required this.medicineNames});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medicines Found')),
      body: ListView.builder(
        itemCount: medicineNames.length,
        itemBuilder: (context, index) {
          final name = medicineNames[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(name),
              trailing: ElevatedButton(
                child: const Text('Buy Now'),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final history = prefs.getStringList('buying_history') ?? [];
                  history.add(name);
                  await prefs.setStringList('buying_history', history);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved "$name" to order history')),
                  );
                }
                ,
              ),
            ),
          );
        },
      ),
    );
  }
}
