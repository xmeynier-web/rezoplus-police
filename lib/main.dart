import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCu0BK4h2hhaGV4C46C9y65rBJlnLftq3A",
      appId: "1:561209004165:web:4c19c7b505bf7ad7df19ec",
      messagingSenderId: "561209004165",
      projectId: "rezoplus-police",
      databaseURL: "https://rezoplus-police-default-rtdb.europe-west1.firebasedatabase.app",
      storageBucket: "rezoplus-police.firebasestorage.app",
    ),
  );

  runApp(const PatrouilleApp());
}

class PatrouilleApp extends StatelessWidget {
  const PatrouilleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Patrouille',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1a1a24),
        primaryColor: Colors.blueAccent,
      ),
      home: const LoginScreen(),
    );
  }
}

// 1. ÉCRAN DE PRISE DE SERVICE
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _controller = TextEditingController();

  void _startService() {
    String unitId = _controller.text.trim();
    if (unitId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez entrer un indicatif radio valide")),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PatrouilleScreen(unitId: unitId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('REZO+ // Connexion Équipage'),
        backgroundColor: const Color(0xFF222230),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 30),
            const Text(
              "Entrez votre indicatif radio :",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Ex: ALPHA-1, CS...",
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2d2d3f),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _startService,
              child: const Text(
                "Démarrer la prise de service",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. ÉCRAN PRINCIPAL DE LA PATROUILLE
class PatrouilleScreen extends StatefulWidget {
  final String unitId;
  const PatrouilleScreen({super.key, required this.unitId});

  @override
  State<PatrouilleScreen> createState() => _PatrouilleScreenState();
}

class _PatrouilleScreenState extends State<PatrouilleScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  
  String _currentStatus = "EN_PATROUILLE";
  String _gpsStatusText = "Suivi GPS en cours...";
  String? _incomingMission;
  StreamSubscription<Position>? _positionStreamSubscription;

  final Map<String, bool> _equipment = {
    "GAIL": true,
    "LBD": true,
    "PIE": true,
    "BTD": true,
    "PSA": true,
    "Casque": true,
    "Trousse PS": true,
    "Ethylo": true,
    "Kit Stup": true,
    "DSA": true,
    "Stop-Stick": false,
  };

  @override
  void initState() {
    super.initState();
    _updateUnitFirebase();
    _listenForMissions();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  void _listenForMissions() {
    _dbRef.child("units/${widget.unitId}/active_mission").onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        setState(() {
          _incomingMission = "${data['title']} - Lieu :${data['location']}";
        });
      } else {
        setState(() {
          _incomingMission = null;
        });
      }
    });
  }

  Future<void> _updateUnitFirebase() async {
    await _dbRef.child("units/${widget.unitId}").update({
      "status": _currentStatus,
      "equipment": _equipment,
      "derniere_maj": ServerValue.timestamp,
    });
  }

  // Suivi continu des trajets en temps réel (mise à jour dès que l'unité bouge de 10 mètres)
  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _gpsStatusText = "⚠️ GPS désactivé (Position par défaut)";
      });
      await _sendDefaultLocation();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _gpsStatusText = "❌ Permission GPS refusée";
        });
        await _sendDefaultLocation();
        return;
      }
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        _dbRef.child("units/${widget.unitId}").update({
          "latitude": position.latitude,
          "longitude": position.longitude,
          "derniere_maj": ServerValue.timestamp,
        });

        if (mounted) {
          setState(() {
            _gpsStatusText = "📍 Trajet en direct (${position.latitude.toStringAsFixed(4)},${position.longitude.toStringAsFixed(4)})";
          });
        }
      },
      onError: (error) {
        setState(() {
          _gpsStatusText = "⚠️ Erreur de suivi GPS";
        });
      },
    );
  }

  Future<void> _sendDefaultLocation() async {
    await _dbRef.child("units/${widget.unitId}").update({
      "latitude": 48.7538,
      "longitude": 2.3218,
      "derniere_maj": ServerValue.timestamp,
    });
  }

  // Actualisation manuelle immédiate au clic sur l'en-tête
  Future<void> _forceRefreshLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
      );
      await _dbRef.child("units/${widget.unitId}").update({
        "latitude": position.latitude,
        "longitude": position.longitude,
        "derniere_maj": ServerValue.timestamp,
      });
      setState(() {
        _gpsStatusText = "✅ Position actualisée (${position.latitude.toStringAsFixed(4)},${position.longitude.toStringAsFixed(4)})";
      });
    } catch (e) {
      setState(() {
        _gpsStatusText = "⚠️ Actualisation impossible";
      });
    }
  }

  Future<void> _disconnectUnit() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2d2d3f),
          title: const Text("Fin de service"),
          content: Text("Voulez-vous déconnecter l'unité ${widget.unitId} ?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Confirmer", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _dbRef.child("units/${widget.unitId}").remove();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  Color _getStatusBoxColor() {
    if (_currentStatus == "SOS_ACTIF") return Colors.red;
    if (_currentStatus == "EN_INTERVENTION") return Colors.orange;
    if (_currentStatus == "CONTROLE_PR") return Colors.teal;
    if (_currentStatus == "EN_PATROUILLE") return Colors.green;
    if (_currentStatus == "TRANSPORT") return Colors.blue;
    if (_currentStatus == "RETOUR_POSTE") return Colors.purple;
    return Colors.grey;
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
            tooltip: "Fin de service",
            onPressed: _disconnectUnit,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_incomingMission != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.3),
                  border: Border.all(color: Colors.orange, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Text("🚨 NOUVELLE MISSION DISPATCH", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                    const SizedBox(height: 5),
                    Text(_incomingMission!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],

            // Bloc cliquable pour forcer le point GPS instantané
            GestureDetector(
              onTap: _forceRefreshLocation,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getStatusBoxColor().withOpacity(0.2),
                  border: Border.all(color: _getStatusBoxColor(), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      "STATUT OPÉRATIONNEL ACTUEL (Appuyez pour actualiser)",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _currentStatus,
                      style: TextStyle(fontSize: 22, color: _getStatusBoxColor(), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _
