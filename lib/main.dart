import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialisation de Firebase pour rezoplus-police
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init note: $e");
  }
  
  runApp(const RezoPlusPatrouilleApp());
}

class RezoPlusPatrouilleApp extends StatelessWidget {
  const RezoPlusPatrouilleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Patrouille',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121824),
        primaryColor: const Color(0xFF1E88E5),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1E88E5),
          secondary: Color(0xFF26A69A),
          error: Color(0xFFD32F2F),
        ),
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
  // Configuration
  String _indicatif = "PAM 1";
  final List<String> _indicatifsDisponibles = ["PAM 1", "PAM 2", "SRT 1", "SRT 2", "SRT 3", "BAC 1", "OPJ 1"];
  
  // Statuts opérationnels
  String _statutActuel = "Disponible";
  final List<Map<String, dynamic>> _statuts = [
    {"label": "Disponible", "color": Colors.green},
    {"label": "En Patrouille", "color": Colors.blue},
    {"label": "Contrôle Police Route", "color": Colors.orange},
    {"label": "Intervention", "color": Colors.purple},
    {"label": "Indisponible", "color": Colors.grey},
  ];

  // Matériel embarqué
  final Map<String, bool> _materiels = {
    "Stop-Stick": true,
    "ETHYLOTEST": true,
    "CINETOMÈTRE": false,
    "KIT PNEU": true,
    "HERSE": false,
  };

  // Géolocalisation & Geofencing
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  bool _isTracking = false;

  // Firebase Realtime Database
  DatabaseReference? _unitRef;

  @override
  void initState() {
    super.initState();
    _initFirebaseRef();
    _startLocationService();
  }

  void _initFirebaseRef() {
    final db = FirebaseDatabase.instance;
    _unitRef = db.ref("unites/$_indicatif");
  }

  Future<void> _startLocationService() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    setState(() => _isTracking = true);

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      setState(() {
        _currentPosition = position;
      });
      _updateFirebasePosition(position);
    });
  }

  void _updateFirebasePosition(Position position) {
    if (_unitRef == null) return;

    // Détection simplifiée de zone (Hybride Geofencing)
    String zoneEstimee = _calculerZoneGeofence(position.latitude, position.longitude);

    _unitRef!.update({
      "indicatif": _indicatif,
      "statut": _statutActuel,
      "latitude": position.latitude,
      "longitude": position.longitude,
      "vitesse": position.speed,
      "cap": position.heading,
      "zone": zoneEstimee,
      "materiel": _materiels,
      "dernier_horodatage": ServerValue.timestamp,
    });
  }

  String _calculerZoneGeofence(double lat, double lng) {
    // Calcul de Geofence hybride basé sur des coordonnées
    return "Secteur Centre";
  }

  void _changerStatut(String nouveauStatut) {
    setState(() {
      _statutActuel = nouveauStatut;
    });
    if (_unitRef != null) {
      _unitRef!.update({"statut": nouveauStatut, "dernier_horodatage": ServerValue.timestamp});
    }
  }

  void _declencherSOS() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C1010),
        title: const Text("ALERTES SOS DÉTRESSE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text("Voulez-vous déclencher une alerte d'urgence au Centre de Commandement ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ANNULER", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (_unitRef != null) {
                _unitRef!.update({
                  "statut": "SOS / URGENCE",
                  "sos": true,
                  "dernier_horodatage": ServerValue.timestamp,
                });
              }
              setState(() => _statutActuel = "SOS / URGENCE");
              Navigator.pop(context);
            },
            child: const Text("DECLENCHER SOS", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deconnexionPropre() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Déconnexion Opérationnelle"),
        content: const Text("La déconnexion supprimera cette unité de la carte temps-réel du PC. Confirmer ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("ANNULER")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("DÉCONNEXION"),
          ),
        ],
      ) ?? false;

    if (confirm) {
      await _positionStream?.cancel();
      if (_unitRef != null) {
        await _unitRef!.remove(); // Suppression propre de l'unité de Firebase
      }
      setState(() {
        _isTracking = false;
        _currentPosition = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unité retirée de Firebase avec succès.")),
        );
      }
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("REZO+ Patrouille", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1F2937),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
            tooltip: "Déconnexion",
            onPressed: _deconnexionPropre,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sélection d'indicatif
            Card(
              color: const Color(0xFF1F2937),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Indicatif Patrouille :", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    DropdownButton<String>(
                      value: _indicatif,
                      dropdownColor: const Color(0xFF1F2937),
                      underline: Container(),
                      items: _indicatifsDisponibles.map((String val) {
                        return DropdownMenuItem<String>(
                          value: val,
                          child: Text(val, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _indicatif = val;
                            _initFirebaseRef();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Boutons de Statuts Dynamiques
            const Text("Statut Opérationnel", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statuts.map((item) {
                bool selected = _statutActuel == item["label"];
                return ChoiceChip(
                  label: Text(item["label"]),
                  selected: selected,
                  selectedColor: item["color"],
                  backgroundColor: const Color(0xFF1F2937),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.grey[300],
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (bool selected) {
                    if (selected) _changerStatut(item["label"]);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Bouton Urgence SOS
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[800],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.warning, color: Colors.white, size: 28),
              label: const Text("BOUTON SOS / DETRESSE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              onPressed: _declencherSOS,
            ),
            const SizedBox(height: 16),

            // Matériel embarqué (Stop-Stick, etc.)
            Card(
              color: const Color(0xFF1F2937),
              child: ExpansionTile(
                title: const Text("Matériel Embarqué", style: TextStyle(fontWeight: FontWeight.bold)),
                leading: const Icon(Icons.build_circle, color: Colors.blueAccent),
                children: _materiels.keys.map((key) {
                  return CheckboxListTile(
                    title: Text(key),
                    value: _materiels[key],
                    onChanged: (bool? val) {
                      setState(() {
                        _materiels[key] = val ?? false;
                      });
                      if (_unitRef != null) {
                        _unitRef!.update({"materiel": _materiels});
                      }
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // État GPS / Geofencing
            Card(
              color: const Color(0xFF1F2937),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isTracking ? Icons.gps_fixed : Icons.gps_off,
                          color: _isTracking ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isTracking ? "Géolocalisation Active (Back-end)" : "GPS Inactif",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text("Latitude : ${_currentPosition?.latitude.toStringAsFixed(5) ?? "En attente..."}"),
                    Text("Longitude : ${_currentPosition?.longitude.toStringAsFixed(5) ?? "En attente..."}"),
                    Text("Vitesse : ${((_currentPosition?.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
