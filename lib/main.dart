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

  // Matériel embarqué (avec Stop-Stick ajouté)
  final Map<String, bool> _equipment = {
    "PVE": true,
    "Radio TLK": true,
    "Kit Secours": false,
    "Gilet Pare-Balles": true,
    "Éthylotest": false,
    "Stop-Stick": false,
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

  // Fonction GPS sécurisée (contournement services Google récents + fallback)
  Future<void> _shareCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _gpsStatusText = "Recherche du signal GPS...";
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsStatusText = "⚠️ Activez le GPS dans les paramètres du téléphone";
          _isLocating = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsStatusText = "❌ Permission GPS refusée par l'utilisateur";
            _isLocating = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsStatusText = "❌ GPS bloqué définitivement (voir réglages Android)";
          _isLocating = false;
        });
        return;
      }

      Position? position;

      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 6),
          forceAndroidLocationManager: true,
        );
      } catch (e) {
        position = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager: true,
        );
      }

      if (position == null) {
        setState(() {
          _gpsStatusText = "⚠️ Signal GPS introuvable (allez près d'une fenêtre)";
          _isLocating = false;
        });
        return;
      }

      await _dbRef.child("units/$_unitId").update({
        "latitude": position.latitude,
        "longitude": position.longitude,
        "derniere_maj": ServerValue.timestamp,
      });

      setState(() {
        _gpsStatusText = "✅ Position transmise (${position!.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
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
        _gpsStatusText = "⚠️ Erreur technique lors du ciblage GPS";
        _isLocating = false;
      });
    }
  }

  // Fonction de déconnexion : Supprime l'unité de Firebase pour qu'elle disparaisse du CSU
  Future<void> _disconnectUnit() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2d2d3f),
          title: const Text("Déconnexion de l'unité"),
          content: Text("Voulez-vous vraiment déconnecter l'équipage $_unitId ? Il disparaîtra du centre de contrôle."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Déconnecter", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      // Suppression du nœud dans Firebase
      await _dbRef.child("units/$_unitId").remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🔌 Unité $_unitId déconnectée et retirée du CSU"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('REZO+ // ÉQUIPAGE : $_unitId'),
        backgroundColor: _currentStatus == "SOS_ACTIF" ? Colors.red : const Color(0xFF222230),
        centerTitle: true,
        actions: [
          // Bouton de déconnexion rapide dans la barre supérieure
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
            tooltip: "Déconnecter la patrouille",
            onPressed: _disconnectUnit,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sélection de l'unité
            Card(
              color: const Color(0xFF2d2d3f),
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
                        dropdownColor: const Color(0xFF2d2d3f),
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

            // Bouton GPS Manuel
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isLocating ? null : _shareCurrentLocation,
              icon: _isLocating 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 26),
              label: Text(
                _isLocating ? "Acquisition en cours..." : "📍 TRANSMETTRE MA POSITION GPS",
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _gpsStatusText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 20),
            const Text("STATUT DE L'ÉQUIPAGE", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
            const SizedBox(height: 8),

            // Grille des Statuts (Harmonisée, avec Contrôle Police Route)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusButton("EN_PATROUILLE", "Patrouille", Colors.green),
                _buildStatusButton("EN_INTERVENTION", "Intervention", Colors.orange),
                _buildStatusButton("CONTROLE_ROUTE", "Contrôle Route", Colors.teal),
                _buildStatusButton("TRANSPORT", "Transport", Colors.blue),
                _buildStatusButton("RETOUR_POSTE", "Retour Poste", Colors.purple),
                _buildStatusButton("HORS_SERVICE", "Hors Service", Colors.grey),
                _buildStatusButton("SOS_ACTIF", "🚨 SOS DÉTRESSE", Colors.red),
              ],
            ),

            const SizedBox(height: 20),
            const Text("MATÉRIEL EMBARQUÉ", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
            const SizedBox(height: 8),

            // Matériel (avec Stop-Stick)
            Card(
              color: const Color(0xFF2d2d3f),
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
            const SizedBox(height: 20),

            // Bouton de déconnexion explicite en bas de page
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _disconnectUnit,
              icon: const Icon(Icons.logout),
              label: const Text("DÉCONNECTER ET QUITTER LE CSU", style: TextStyle(fontWeight: FontWeight.bold)),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
