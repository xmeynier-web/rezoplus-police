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
  runApp(const RezoPlusMobileApp());
}

class RezoPlusMobileApp extends StatelessWidget {
  const RezoPlusMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Terrain',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF12121a),
      ),
      home: const UnitLoginScreen(),
    );
  }
}

// 1. Écran de connexion / Choix de l'indicatif
class UnitLoginScreen extends StatefulWidget {
  const UnitLoginScreen({super.key});

  @override
  State<UnitLoginScreen> createState() => _UnitLoginScreenState();
}

class _UnitLoginScreenState extends State<UnitLoginScreen> {
  final TextEditingController _unitController = TextEditingController();

  void _startService() {
    if (_unitController.text.trim().isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ActiveServiceScreen(unitId: _unitController.text.trim().toUpperCase()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('REZO+ // Connexion Équipage')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_police, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 24),
            const Text('Entrez votre indicatif radio :', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ex: ALPHA-1, BRAVO-2...',
                filled: true,
                fillColor: Color(0xFF1e1e2d),
              ),
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: _startService,
                child: const Text('Démarrer la prise de service', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. Écran Principal en Service
class ActiveServiceScreen extends StatefulWidget {
  final String unitId;
  const ActiveServiceScreen({super.key, required this.unitId});

  @override
  State<ActiveServiceScreen> createState() => _ActiveServiceScreenState();
}

class _ActiveServiceScreenState extends State<ActiveServiceScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  
  String _currentStatus = 'EN_PATROUILLE';
  double? _latitude;
  double? _longitude;
  Timer? _locationTimer;
  Map<String, dynamic> _activeMission = {};
  
  // Liste du matériel embarqué validé
  final Map<String, bool> _equipmentChecklist = {
    "Radio portable": false,
    "Gilet pare-balles": false,
    "PV électronique / Ordzo": false,
    "Bâton de défense / LBD": false,
    "Trousse de premiers secours": false,
  };

  @override
  void initState() {
    super.initState();
    _initLocationAndSync();
    _listenToMissions();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    // Nettoyage ou mise hors ligne propre dans Firebase à la fermeture
    _dbRef.child("units/${widget.unitId}").update({"status": "HORS_SERVICE"});
    super.dispose();
  }

  Future<void> _initLocationAndSync() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // Boucle de mise à jour GPS et Keep-Alive en arrière-plan
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        _updateFirebaseData();
      } catch (e) {
        // Ignorer les erreurs temporaires de GPS pour éviter de couper le flux
      }
    });
  }

  void _updateFirebaseData() {
    _dbRef.child("units/${widget.unitId}").update({
      "status": _currentStatus,
      "latitude": _latitude,
      "longitude": _longitude,
      "equipment": _equipmentChecklist,
      "last_seen": ServerValue.timestamp,
    });
  }

  void _listenToMissions() {
    _dbRef.child("units/${widget.unitId}/active_mission").onValue.listen((event) {
      final data = event.snapshot.value;
      if (data != null && data is Map) {
        setState(() {
          _activeMission = Map<String, dynamic>.from(data);
        });
      } else {
        setState(() {
          _activeMission = {};
        });
      }
    });
  }

  void _changeStatus(String newStatus) {
    setState(() {
      _currentStatus = newStatus;
    });
    _updateFirebaseData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Statut mis à jour : $newStatus'), duration: const Duration(seconds: 1)),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'SOS_ACTIF': return Colors.red;
      case 'EN_INTERVENTION': return Colors.orange;
      case 'TRANSPORT': return Colors.blue;
      case 'RETOUR_POSTE': return Colors.purple;
      case 'EN_PATROUILLE': return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isSos = _currentStatus == 'SOS_ACTIF';

    return Scaffold(
      appBar: AppBar(
        title: Text('Unité : ${widget.unitId}'),
        backgroundColor: isSos ? Colors.red.shade900 : const Color(0xFF1a1a2e),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              _dbRef.child("units/${widget.unitId}").remove();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const UnitLoginScreen()));
            },
            tooltip: 'Fin de service',
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Indicateur de statut actuel
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(_currentStatus).withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _getStatusColor(_currentStatus), width: 2),
              ),
              child: Column(
                children: [
                  const Text('STATUT OPÉRATIONNEL ACTUEL', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(_currentStatus, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _getStatusColor(_currentStatus))),
                  const SizedBox(height: 8),
                  Text('GPS : ${_latitude != "$_latitude", _longitude != null ? "$_latitude, $_longitude" : "Acquisition..."}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bouton SOS Urgence
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSos ? Colors.grey : Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                _changeStatus(isSos ? 'EN_PATROUILLE' : 'SOS_ACTIF');
              },
              icon: const Icon(Icons.warning_amber_rounded, size: 28),
              label: Text(isSos ? 'QUITTER L\'ÉTAT D\'URGENCE SOS' : '🚨 DÉCLENCHER UN SOS', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),

            // Grille des statuts (Incluant "Retour au poste")
            const Text('Modifier le statut :', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () => _changeStatus('EN_PATROUILLE'),
                  child: const Text('En Patrouille'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: () => _changeStatus('EN_INTERVENTION'),
                  child: const Text('En Intervention'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () => _changeStatus('TRANSPORT'),
                  child: const Text('Transport'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  onPressed: () => _changeStatus('RETOUR_POSTE'),
                  child: const Text('Retour au poste'),
                ),
              ],
            ),
            const Divider(height: 32, color: Colors.grey),

            // Ordre de mission reçu du CSU
            if (_activeMission.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.shade900.withOpacity(0.4), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📢 ORDRE DE MISSION REÇU :', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                    const SizedBox(height: 4),
                    Text('Objet : ${_activeMission['title']}', style: const TextStyle(fontSize: 16)),
                    Text('Lieu : ${_activeMission['location']}', style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),

            // Checklist du matériel embarqué validable
            const Text('Contrôle du Matériel Embarqué :', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1e1e2d),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _equipmentChecklist.length,
                itemBuilder: (context, index) {
                  String keyName = _equipmentChecklist.keys.elementAt(index);
                  bool isChecked = _equipmentChecklist[keyName] ?? false;

                  return CheckboxListTile(
                    title: Text(keyName, style: const TextStyle(color: Colors.white)),
                    value: isChecked,
                    activeColor: Colors.blueAccent,
                    onChanged: (bool? value) {
                      setState(() {
                        _equipmentChecklist[keyName] = value ?? false;
                      });
                      // Synchronisation immédiate avec Firebase lors du check/uncheck
                      _updateFirebaseData();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
