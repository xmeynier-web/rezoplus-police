import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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
  
  runApp(const RezoPlusApp());
}

class RezoPlusApp extends StatelessWidget {
  const RezoPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Terrain',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1a1a24),
      ),
      home: const UnitConfigScreen(),
    );
  }
}

class UnitConfigScreen extends StatefulWidget {
  const UnitConfigScreen({super.key});

  @override
  State<UnitConfigScreen> createState() => _UnitConfigScreenState();
}

class _UnitConfigScreenState extends State<UnitConfigScreen> {
  final TextEditingController _controller = TextEditingController(text: "ALPHA-1");

  void _startApp() {
    if (_controller.text.trim().isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PatrolScreen(unitId: _controller.text.trim().toUpperCase()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rezo+ Initialisation Terrain')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_police, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            const Text('Entrez l\'indicatif de l\'équipage :', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF2d2d3f),
              ),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.all(16)),
              onPressed: _startApp,
              child: const Text('Démarrer la prise de service', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class PatrolScreen extends StatefulWidget {
  final String unitId;
  const PatrolScreen({super.key, required this.unitId}); // Correction ici

  @override
  State<PatrolScreen> createState() => _PatrolScreenState();
}

class _PatrolScreenState extends State<PatrolScreen> {
  String _currentStatus = "EN_PATROUILLE";
  bool _isSosActive = false;
  Map<String, dynamic> _equipment = {
    "Arme de poing": false,
    "Gilet pare-balles": false,
    "Radio portative": false,
    "Lampe tactique": false,
    "Matraque télescopique": false,
    "P.I.E. (Taser)": false,
    "Menottes": false,
    "Kit PV / Carnet": false,
    "Trousse de premiers secours": false,
    "Ethylotest": false,
  };

  Map<String, dynamic>? _activeMission;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStartGPS();
    _listenToIncomingMissions();
  }

  void _checkPermissionsAndStartGPS() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((Position position) {
        _updateFirebaseData(lat: position.latitude, lng: position.longitude);
      });
    }
  }

  void _updateFirebaseData({double? lat, double? lng}) {
    Map<String, dynamic> data = {
      "status": _isSosActive ? "SOS_ACTIF" : _currentStatus,
      "last_update": ServerValue.timestamp,
      "equipment": _equipment,
    };
    if (lat != null && lng != null) {
      data["latitude"] = lat;
      data["longitude"] = lng;
    }
    _dbRef.child("units/${widget.unitId}").update(data);
  }

  void _listenToIncomingMissions() {
    _dbRef.child("units/${widget.unitId}/active_mission").onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _activeMission = Map<String, dynamic>.from(data);
        });
      } else {
        setState(() {
          _activeMission = null;
        });
      }
    });
  }

  void _setStatus(String status) {
    setState(() {
      _currentStatus = status;
      if (_isSosActive && status != "SOS_ACTIF") {
        _isSosActive = false;
      }
    });
    _updateFirebaseData();
  }

  void _toggleSos() {
    setState(() {
      _isSosActive = !_isSosActive;
    });
    _updateFirebaseData();
    if (_isSosActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🚨 ALERTE SOS DÉCLENCHÉE !", style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rezo+ : ${widget.unitId}'),
        backgroundColor: _isSosActive ? Colors.red : const Color(0xFF222230),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_activeMission != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("📢 ORDRE DE MISSION REÇU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text("Objet : ${_activeMission!['title']}", style: const TextStyle(fontSize: 15)),
                    Text("Lieu : ${_activeMission!['location']}", style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ),
              ),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSosActive ? Colors.grey : Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _toggleSos,
              icon: const Icon(Icons.warning, color: Colors.white, size: 28),
              label: Text(
                _isSosActive ? 'DÉSACTIVER L\'ALERTE SOS' : 'BOUTON SOS URGENCE',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),

            const Text('Statut Opérationnel :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusButton("En Patrouille", "EN_PATROUILLE", Colors.green),
                _statusButton("En Intervention", "EN_INTERVENTION", Colors.orange),
                _statusButton("Transport / Transf.", "TRANSPORT", Colors.blue),
                _statusButton("Indisponible", "INDISPONIBLE", Colors.grey),
              ],
            ),
            const Divider(height: 30, color: Colors.grey),

            const Text('Check-list Matériel Embarqué :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF2d2d3f),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _equipment.keys.length,
                itemBuilder: (context, index) {
                  String key = _equipment.keys.elementAt(index);
                  return CheckboxListTile(
                    title: Text(key, style: const TextStyle(fontSize: 14)),
                    value: _equipment[key],
                    activeColor: Colors.blue,
                    onChanged: (bool? value) {
                      setState(() {
                        _equipment[key] = value ?? false;
                      });
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

  Widget _statusButton(String label, String value, Color color) {
    bool isSelected = _currentStatus == value;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : const Color(0xFF2d2d3f),
        side: BorderSide(color: color, width: 2),
      ),
      onPressed: () => _setStatus(value),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
