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
        scaffoldBackgroundColor: const Color(0xFF12121a),
        primaryColor: Colors.blueAccent,
      ),
      home: const PatrouilleScreen(),
    );
  }
}

class PatrouilleScreen extends StatefulWidget {
  const PatrouilleScreen({super.key});

  @override
  State<PatrouilleScreen> createState() => _PatrouilleScreenState();
}

class _PatrouilleScreenState extends State<PatrouilleScreen> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  
  String _unitId = "ALPHA-1";
  String _currentStatus = "EN_PATROUILLE";
  bool _isLocating = false;
  String _gpsStatusText = "Position non transmise";

  final Map<String, bool> _equipment = {
    "PVE": true,
    "Radio TLK": true,
    "Kit Secours": false,
    "Gilet Pare-Balles": true,
    "Éthylotest": false,
  };

  @override
  void initState() {
    super.initState();
    _updateUnitFirebase();
  }

  Future<void> _updateUnitFirebase() async {
    await _dbRef.child("units/$_unitId").update({
      "status": _currentStatus,
      "equipment": _equipment,
      "derniere_maj": ServerValue.timestamp,
    });
  }

  Future<void> _shareCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _gpsStatusText = "Acquisition du signal GPS...";
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsStatusText = "⚠️ Activez la localisation GPS sur le téléphone";
          _isLocating = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsStatusText = "❌ Permission GPS refusée";
            _isLocating = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsStatusText = "❌ GPS bloqué dans les paramètres d'Android";
          _isLocating = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      await _dbRef.child("units/$_unitId").update({
        "latitude": position.latitude,
        "longitude": position.longitude,
        "derniere_maj": ServerValue.timestamp,
      });

      setState(() {
        _gpsStatusText = "✅ Position envoyée au PC (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
        _isLocating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📍 Position GPS transmise au CSU avec succès !"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _gpsStatusText = "⚠️ Erreur lors de l'acquisition GPS";
        _isLocating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('REZO+ // ÉQUIPAGE : $_unitId'),
        backgroundColor: _currentStatus == "SOS_ACTIF" ? Colors.red : const Color(0xFF1a1a2e),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: const Color(0xFF1e1e2d),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Text("Nom de l'équipage : ", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _unitId,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1e1e2d),
                        items: ["ALPHA-1", "ALPHA-2", "PATROUILLE-VTT", "CANINE-1"]
                            .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _unitId = val;
                            });
                            _updateUnitFirebase();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isLocating ? null : _shareCurrentLocation,
              icon: _isLocating 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 28),
              label: Text(
                _isLocating ? "Acquisition en cours..." : "📍 TRANSMETTRE MA POSITION GPS",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _gpsStatusText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Text("STATUT DE L'ÉQUIPAGE", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusButton("EN_PATROUILLE", "Patrouille", Colors.green),
                _buildStatusButton("EN_INTERVENTION", "Intervention", Colors.orange),
                _buildStatusButton("TRANSPORT", "Transport", Colors.blue),
                _buildStatusButton("RETOUR_POSTE", "Retour Poste", Colors.purple),
                _buildStatusButton("HORS_SERVICE", "Hors Service", Colors.grey),
                _buildStatusButton("SOS_ACTIF", "🚨 SOS DÉTRESSE", Colors.red),
              ],
            ),
            const SizedBox(height: 24),
            const Text("MATÉRIEL EMBARQUÉ", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1e1e2d),
              child: Column(
                children: _equipment.keys.map((item) {
                  return CheckboxListTile(
                    title: Text(item),
                    value: _equipment[item],
                    activeColor: Colors.blueAccent,
                    onChanged: (bool? val) {
                      setState(() {
                        _equipment[item] = val ?? false;
                      });
                      _updateUnitFirebase();
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton(String statusKey, String label, Color color) {
    bool isSelected = _currentStatus == statusKey;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : color.withOpacity(0.2),
        side: BorderSide(color: color, width: isSelected ? 2 : 1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: () {
        setState(() {
          _currentStatus = statusKey;
        });
        _updateUnitFirebase();
      },
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : color,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
