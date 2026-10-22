// lib/main.dart — Application Rezo+ Patrouille (Mairie de Fresnes)
// Version corrigée et compilable.
//
// Prérequis :
//  - pubspec.yaml : environment.sdk '>=3.13.0 <4.0.0', dépendances
//    firebase_core, firebase_database, geolocator, flutter (sdk).
//  - android/app/google-services.json présent, avec
//    "package_name": "com.rezoplus.rezoplus_terrain".
//  - android/app/build.gradle : applicationId "com.rezoplus.rezoplus_terrain",
//    plugin 'com.google.gms.google-services', minSdkVersion 21.
//  - AndroidManifest.xml : permissions ACCESS_FINE_LOCATION et
//    ACCESS_COARSE_LOCATION déclarées avant la balise <application>.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation Firebase robuste : toute erreur est affichée à l'écran
  // au lieu de provoquer un écran blanc silencieux.
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Erreur init Firebase : $e');
  }
  runApp(RezoPlusPatrouilleApp(firebaseReady: firebaseReady));
}

class RezoPlusPatrouilleApp extends StatelessWidget {
  const RezoPlusPatrouilleApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Patrouille',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: firebaseReady
          ? const PatrouilleHomePage()
          : const FirebaseErrorPage(),
    );
  }
}

/// Écran affiché si Firebase n'a pas pu s'initialiser
/// (google-services.json absent ou mal configuré, pas de réseau au premier
/// lancement, etc.). Évite le "gel" sans diagnostic.
class FirebaseErrorPage extends StatelessWidget {
  const FirebaseErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Impossible d\'initialiser Firebase',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Vérifiez que android/app/google-services.json est présent\n'
                'et que l\'appareil a accès à Internet, puis relancez.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PatrouilleHomePage extends StatefulWidget {
  const PatrouilleHomePage({super.key});

  @override
  State<PatrouilleHomePage> createState() => _PatrouilleHomePageState();
}

class _PatrouilleHomePageState extends State<PatrouilleHomePage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final TextEditingController _msgController = TextEditingController();

  final String _unitId = 'Patrouille-01';

  // Les 7 statuts opérationnels
  final List<String> _statusList = [
    'En Patrouille',
    'En Intervention',
    'Contrôle PR',
    'Transport / Escorte',
    'Escale Technique',
    'Retour Poste',
    'SOS ACTIF',
  ];

  late String _currentStatus;

  // Les 12 équipements embarqués
  final Map<String, bool> _equipment = {
    'Stop-Stick': false,
    'BTD': false,
    'GAIL': false,
    'LBD': false,
    'PIE': false,
    'PSA': false,
    'Trousse de secours (FAK)': false,
    'Casque': false,
    'Bouclier': false,
    'Ethylotest': false,
    'Test stupéfiants': false,
    'OSA': false,
  };

  bool _isOnline = false;
  bool _sosActive = false;
  Position? _currentPosition;
  String? _gpsError;

  @override
  void initState() {
    super.initState();
    _currentStatus = _statusList.first;
    // Lancement du GPS sans bloquer le rendu : initState n'attend pas.
    _initGPS();
  }

  Future<void> _initGPS() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setGpsError('Service de localisation désactivé.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setGpsError('Permission de localisation refusée.');
        return;
      }

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        if (!mounted) return;
        setState(() {
          _currentPosition = position;
          _gpsError = null;
        });
        if (_isOnline) {
          _sendDataToFirebase();
        }
      });
    } catch (e) {
      _setGpsError('Erreur GPS : $e');
    }
  }

  void _setGpsError(String message) {
    if (!mounted) return;
    setState(() {
      _gpsError = message;
    });
  }

  Future<void> _toggleService() async {
    if (_isOnline) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Confirmation'),
            content: const Text('Voulez-vous vraiment quitter le service ?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Quitter'),
              ),
            ],
          );
        },
      );
      if (confirm != true) return;

      setState(() {
        _isOnline = false;
        _sosActive = false;
        _currentStatus = _statusList.first;
      });
      try {
        await _dbRef.child('units/$_unitId').remove();
      } catch (e) {
        debugPrint('Erreur fin de service : $e');
      }
    } else {
      if (_currentPosition == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Position GPS non disponible pour l\'instant.')),
        );
        return;
      }
      setState(() {
        _isOnline = true;
      });
      _sendDataToFirebase();
    }
  }

  Future<void> _sendDataToFirebase() async {
    if (_currentPosition == null) return;
    try {
      await _dbRef.child('units/$_unitId').set({
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'status': _currentStatus,
        'equipment': _equipment,
        'sos': _sosActive,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Erreur envoi Firebase : $e');
    }
  }

  Future<void> _changeStatus(String status) async {
    setState(() {
      _currentStatus = status;
    });
    if (_isOnline) await _sendDataToFirebase();
  }

  Future<void> _triggerSOS() async {
    setState(() {
      _sosActive = !_sosActive;
      _currentStatus = _sosActive ? 'SOS ACTIF' : _statusList.first;
    });
    if (_isOnline) await _sendDataToFirebase();
  }

  Future<void> _sendMessage() async {
    final String text = _msgController.text.trim();
    if (text.isEmpty || !_isOnline) return;
    try {
      await _dbRef.child('messages').push().set({
        'sender': _unitId,
        'text': text,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Erreur envoi message : $e');
    }
    _msgController.clear();
  }

  void _showEquipmentModal() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateModal) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gestion du Matériel Embarqué',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      children: _equipment.keys.map((String key) {
                        return CheckboxListTile(
                          title: Text(key),
                          value: _equipment[key],
                          onChanged: (bool? value) {
                            setStateModal(() {
                              _equipment[key] = value ?? false;
                            });
                            if (_isOnline) _sendDataToFirebase();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezo+ Patrouille'),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_circle_outlined),
            tooltip: 'Matériel embarqué',
            onPressed: _showEquipmentModal,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bandeau d'état
            Card(
              color: _isOnline ? Colors.green.shade800 : Colors.grey.shade800,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  _isOnline
                      ? 'EN SERVICE — $_currentStatus'
                      : 'HORS SERVICE',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Alerte GPS si problème
            if (_gpsError != null)
              Card(
                color: Colors.orange.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _gpsError!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (_gpsError != null) const SizedBox(height: 10),

            // Sélection du statut
            Expanded(
              child: ListView(
                children: _statusList
                    .where((s) => s != 'SOS ACTIF')
                    .map((String status) {
                  return RadioListTile<String>(
                    title: Text(status),
                    value: status,
                    groupValue: _currentStatus,
                    onChanged: _isOnline
                        ? (String? value) {
                            if (value != null) _changeStatus(value);
                          }
                        : null,
                  );
                }).toList(),
              ),
            ),

            // Bouton SOS
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _sosActive ? Colors.red : Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isOnline ? _triggerSOS : null,
              icon: const Icon(Icons.warning),
              label: Text(_sosActive ? 'SOS ACTIF — ANNULER' : 'SOS'),
            ),
            const SizedBox(height: 10),

            // Envoi de message
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    enabled: _isOnline,
                    decoration: const InputDecoration(
                      hintText: 'Message vers le PC...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isOnline ? _sendMessage : null,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Prise / fin de service
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isOnline ? Colors.grey.shade800 : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _toggleService,
              icon: Icon(_isOnline ? Icons.logout : Icons.login),
              label: Text(_isOnline ? 'FIN DE SERVICE' : 'PRISE DE SERVICE'),
            ),
          ],
        ),
      ),
    );
  }
}
