import 'package:flutter/material.dart';

class BuyingHistoryScreen extends StatelessWidget {
  const BuyingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Buying History")),
      body: const Center(child: Text("No past orders.")),
    );
  }
}
