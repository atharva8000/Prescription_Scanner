import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class ShopListScreen extends StatefulWidget {
  final List<String> medicineNames;

  const ShopListScreen({super.key, required this.medicineNames});

  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  List<Map<String, dynamic>> nearbyShops = [];
  bool isLoading = true;
  final String _apiKey = 'YOUR_API_KEY_HERE'; // <-- Replace with your actual API key

  @override
  void initState() {
    super.initState();
    _loadNearbyShops();
  }

  Future<void> _loadNearbyShops() async {
    final position = await _getCurrentLocation();
    if (position != null) {
      final shops = await fetchNearbyMedicalShops(position, _apiKey);
      setState(() {
        nearbyShops = shops;
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition();
  }

  Future<List<Map<String, dynamic>>> fetchNearbyMedicalShops(
      Position position, String apiKey) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${position.latitude},${position.longitude}&radius=2000&type=pharmacy&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final results = data['results'] as List;

      return results.map((place) {
        return {
          'name': place['name'],
          'address': place['vicinity'],
          'lat': place['geometry']['location']['lat'],
          'lng': place['geometry']['location']['lng'],
        };
      }).toList();
    } else {
      throw Exception('Failed to fetch nearby shops');
    }
  }

  void _openInMap(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open map')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Medical Shops')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: nearbyShops.length,
        itemBuilder: (context, index) {
          final shop = nearbyShops[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(shop['name']),
              subtitle: Text(shop['address']),
              trailing: IconButton(
                icon: const Icon(Icons.map),
                onPressed: () => _openInMap(shop['lat'], shop['lng']),
              ),
            ),
          );
        },
      ),
    );
  }
}
