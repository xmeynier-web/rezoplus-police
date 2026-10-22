import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint("Erreur d'initialisation Firebase : $e");
    }
    runApp(const RezoPlusMobileApp());
  }, (error, stack) {
    debugPrint("Erreur critique : $error");
  });
}

class RezoPlusMobileApp extends StatelessWidget {
  const RezoPlusMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1a1a24),
      ),
      home: const LoginScreen(),
    );
  }
}

// ==========================================
// 1. ÉCRAN DE CONNEXION (Saisie Indicatif Radio)
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _unitController = TextEditingController();

  void _connectUnit() {
    String unitId = _unitController.text.trim().toUpperCase();
    if (unitId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un indicatif radio valide (ex: 260 ALPHA)')),
      );
      return;
    }

    // Navigation vers le tableau de bord de l'unité connectée
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PatrolDashboardScreen(unitId: unitId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion - Poste de Commandement'),
        backgroundColor: const Color(0xFF222230),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.local_police, size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            const Text(
              'REZO+ MOBILE',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _unitController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Indicatif Radio de l\'Unité (ex: 260 ALPHA)',
                labelStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2d2d3f),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _connectUnit,
              child: const Text('Se connecter au CSU', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. TABLEAU DE BORD DE L'UNITÉ CONNECTÉE
// ==========================================
class PatrolDashboardScreen extends StatefulWidget {
  final String unitId;
  const PatrolDashboardScreen({super.key, required this.unitId});

  @override
  State<PatrolDashboardScreen> createState() => _PatrolDashboardScreenState();
}

class _PatrolDashboardScreenState extends State<PatrolDashboardScreen> {
  // Liste des statuts à jour
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

  // Matériel embarqué : décoché par défaut, ordre strict demandé
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

  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocationAndSync();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // Gestion de la géolocalisation et des permissions Android
  Future<void> _initLocationAndSync() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return;
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        _updateFirebaseData(lat: position.latitude, lng: position.longitude);
      });
    } catch (e) {
      debugPrint("Erreur GPS : $e");
    }
  }

  void _updateFirebaseData({double? lat, double? lng}) {
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref("units/${widget.unitId}");
      Map<String, dynamic> updateData = {
        "status": currentStatus,
        "equipment": equipmentState,
        "derniere_maj": ServerValue.timestamp,
      };
      if (lat != null && lng != null) {
        updateData["latitude"] = lat;
        updateData["longitude"] = lng;
      }
      ref.update(updateData);
    } catch (e) {
      debugPrint("Erreur mise à jour Firebase : $e");
    }
  }

  void _changeStatus(String newStatus) {
    setState(() {
      currentStatus = newStatus;
    });
    _updateFirebaseData();
  }

  // Bouton de déconnexion : supprime l'unité de Firebase et retourne à l'écran de connexion
  void _disconnectUnit() async {
    try {
      _positionStream?.cancel();
      await FirebaseDatabase.instance.ref("units/${widget.unitId}").remove();
    } catch (e) {
      debugPrint("Erreur lors de la suppression de l'unité : $e");
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Unité : ${widget.unitId}'),
        backgroundColor: const Color(0xFF222230),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Déconnexion',
            onPressed: _disconnectUnit,
          ),
        ],
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
              title: Text(key, style: const TextStyle(color: Colors.white)),
              value: equipmentState[key],
              activeColor: Colors.orange,
              onChanged: (bool? value) {
                setState(() {
                  equipmentState[key] = value ?? false;
                });
                _updateFirebaseData();
              },
            );
          }),
        ],
      ),
    );
  }
}
