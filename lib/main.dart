import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

void main() {
  // Capture toutes les erreurs non gérées au démarrage pour éviter les écrans figés/blancs
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Initialisation sécurisée de Firebase avec gestion d'erreur
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint("Erreur d'initialisation Firebase : $e");
    }

    runApp(const RezoPlusMobileApp());
  }, (error, stack) {
    debugPrint("Erreur critique interceptée : $error");
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
  String unitId = '260 ALPHA';

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

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Exécution différée des vérifications pour garantir que l'UI s'affiche instantanément
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocationSafely();
    });
  }

  // Initialisation sécurisée du GPS pour ne jamais bloquer le chargement de l'app
  Future<void> _initLocationSafely() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isInitialized = true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isInitialized = true);
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isInitialized = true);
        return;
      }

      // Écoute du flux GPS en arrière-plan sans bloquer l'interface
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        _updateFirebaseLocation(position.latitude, position.longitude);
      }, onError: (e) {
        debugPrint("Erreur flux GPS : $e");
      });

    } catch (e) {
      debugPrint("Erreur lors de l'initialisation de la localisation : $e");
    } finally {
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    }
  }

  void _updateFirebaseLocation(double lat, double lng) {
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref("units/$unitId");
      ref.update({
        "latitude": lat,
        "longitude": lng,
        "status": currentStatus,
        "equipment": equipmentState,
        "derniere_maj": ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Erreur mise à jour Firebase GPS : $e");
    }
  }

  void _changeStatus(String newStatus) {
    setState(() {
      currentStatus = newStatus;
    });
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref("units/$unitId");
      ref.update({
        "status": currentStatus,
        "derniere_maj": ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Erreur mise à jour statut Firebase : $e");
    }
  }

  void _updateEquipment() {
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref("units/$unitId");
      ref.update({
        "equipment": equipmentState,
        "derniere_maj": ServerValue.timestamp,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Matériel embarqué mis à jour !')),
        );
      }
    } catch (e) {
      debugPrint("Erreur mise à jour matériel Firebase : $e");
    }
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
