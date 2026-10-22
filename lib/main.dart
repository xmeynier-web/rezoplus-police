import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const RezoPlusMobileApp());
}

class RezoPlusMobileApp extends StatelessWidget {
  const RezoPlusMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Mobile',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1a1a24),
      ),
      home: const PatrolDashboardScreen(),
    );
  }
}

class PatrolDashboardScreen extends StatefulWidget {
  const PatrolDashboardScreen({super.key});

  @override
  State<PatrolDashboardScreen> createState() => _PatrolDashboardScreenState();
}

class _PatrolDashboardScreenState extends State<PatrolDashboardScreen> {
  // Liste exacte des statuts mis à jour
  final List<Map<String, String>> availableStatuses = [
    {'id': 'EN_PATROUILLE', 'label': 'En Patrouille'},
    {'id': 'EN_INTERVENTION', 'label': 'En Intervention'},
    {'id': 'CONTROLE_PR', 'label': 'Contrôle PR'},
    {'id': 'TRANSPORT_ESCORTE', 'label': 'Transport / Escorte'},
    {'id': 'ESCALE_TECHNIQUE', 'label': 'Escale Technique'},
    {'id': 'RETOUR_POSTE', 'label': 'Retour Poste'},
    {'id': 'SOS_ACTIF', 'label': 'SOS ACTIF'},
  ];

  String currentStatus = 'EN_PATROUILLE';
  String unitId = '260 ALPHA'; // Indicatif de l'unité

  // Matériel embarqué : décoché par défaut (false), ordre strict demandé
  final Map<String, bool> equipmentState = {
    'BTD': false,
    'GAIL': false,
    'LBD': false,
    'PIE': false,
    'PSA': false,
    '❌ FAK': false,
    'Casque': false,
    'Bouclier': false,
    'Ethylo': false,
    'Test Stup': false,
    'Stop-Stick': false,
    'DSA': false,
  };

  @override
  void initState() {
    super.initState();
    _initLocationAndSync();
  }

  // Gestion des autorisations de géolocalisation et du flux GPS
  Future<void> _initLocationAndSync() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      _updateFirebaseLocation(position.latitude, position.longitude);
    });
  }

  void _updateFirebaseLocation(double lat, double lng) {
    DatabaseReference ref = FirebaseDatabase.instance.ref("units/$unitId");
    ref.update({
      "latitude": lat,
      "longitude": lng,
      "status": currentStatus,
      "equipment": equipmentState,
      "derniere_maj": ServerValue.timestamp,
    });
  }

  void _changeStatus(String newStatus) {
    setState(() {
      currentStatus = newStatus;
    });
    DatabaseReference ref = FirebaseDatabase.instance.ref("units/$unitId");
    ref.update({
      "status": currentStatus,
      "derniere_maj": ServerValue.timestamp,
    });
  }

  void _updateEquipment() {
    DatabaseReference ref = FirebaseDatabase.instance.ref("units/$unitId");
    ref.update({
      "equipment": equipmentState,
      "derniere_maj": ServerValue.timestamp,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Matériel embarqué mis à jour !')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Unité : $unitId'),
        backgroundColor: const Color(0xFF222230),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Statut Opérationnel',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: availableStatuses.map((statusMap) {
              bool isSelected = currentStatus == statusMap['id'];
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.orange : const Color(0xFF2d2d3f),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _changeStatus(statusMap['id']!),
                child: Text(statusMap['label']!),
              );
            }).toList(),
          ),
          const Divider(height: 40, color: Colors.grey),
          const Text(
            'Contrôle du Matériel Embarqué',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 10),
          ...equipmentState.keys.map((String key) {
            return CheckboxListTile(
              title: Text(key),
              value: equipmentState[key],
              activeColor: Colors.orange,
              onChanged: (bool? value) {
                setState(() {
                  equipmentState[key] = value ?? false;
                });
                _updateEquipment();
              },
            );
          }),
        ],
      ),
    );
  }
}
