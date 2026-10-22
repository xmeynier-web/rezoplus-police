import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

// ---------------------------------------------------------------------------
// DÉMARRAGE
// runApp() est appelé IMMÉDIATEMENT : l'application s'ouvre toujours, même si
// Firebase échoue. L'erreur éventuelle s'affiche à l'écran au lieu d'un écran
// blanc / figé.
// ---------------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RezoPlusApp());
}

class RezoPlusApp extends StatelessWidget {
  const RezoPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Patrouille',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const BootScreen(),
    );
  }
}

/// Écran d'amorçage : initialise Firebase puis affiche l'écran principal.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  late Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = _initFirebase();
  }

  Future<void> _initFirebase() async {
    // Sur Android, google-services.json + plugin Gradle suffisent.
    // Le timeout évite un chargement infini en cas de problème réseau/config.
    await Firebase.initializeApp().timeout(const Duration(seconds: 15));
  }

  void _retry() {
    setState(() => _init = _initFirebase());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Rezo+ : démarrage…'),
                ],
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Rezo+ : erreur de démarrage')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Impossible d\'initialiser Firebase.\n'
                    'Vérifiez google-services.json (package_name = '
                    'com.rezoplus.rezoplus_terrain) et la connexion réseau.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText('${snap.error}',
                      style: const TextStyle(color: Colors.orangeAccent)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                      onPressed: _retry, child: const Text('Réessayer')),
                ],
              ),
            ),
          );
        }
        return const PatrouilleHomePage();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ÉCRAN PRINCIPAL
// ---------------------------------------------------------------------------
class PatrouilleHomePage extends StatefulWidget {
  const PatrouilleHomePage({super.key});

  @override
  State<PatrouilleHomePage> createState() => _PatrouilleHomePageState();
}

class _PatrouilleHomePageState extends State<PatrouilleHomePage> {
  // Firebase est déjà initialisé quand cet écran est construit.
  late final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final TextEditingController _msgController = TextEditingController();
  StreamSubscription<Position>? _gpsSub;

  final String _unitId = 'Patrouille-01';

  static const List<String> _statusList = [
    'En Patrouille',
    'En Intervention',
    'Contrôle PR',
    'Transport / Escorte',
    'Escale Technique',
    'Retour Poste',
    'SOS ACTIF',
  ];
  late String _currentStatus = _statusList[0];

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
    'Éthylotest': false,
    'Test stupéfiants': false,
    'DSA': false,
  };

  bool _isOnline = false;
  bool _sosActive = false;
  Position? _currentPosition;
  String _gpsMessage = 'Recherche du signal GPS...';

  @override
  void initState() {
    super.initState();
    // Lancé après le premier rendu : ne bloque jamais l'affichage.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initGPS());
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _msgController.dispose();
    super.dispose();
  }

  // ----------------------------- GPS ---------------------------------------
  Future<void> _initGPS() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setGpsMessage('GPS désactivé sur le téléphone');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setGpsMessage('Permission de localisation refusée');
        return;
      }

      final LocationSettings settings = defaultTargetPlatform ==
              TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              // Service de premier plan : le suivi continue écran éteint.
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'Rezo+ Patrouille',
                notificationText: 'Géolocalisation active',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high, distanceFilter: 10);

      _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          if (!mounted) return;
          setState(() => _currentPosition = position);
          if (_isOnline) _sendDataToFirebase();
        },
        onError: (Object e) => _setGpsMessage('Erreur GPS : $e'),
      );
    } catch (e) {
      _setGpsMessage('GPS indisponible : $e');
    }
  }

  void _setGpsMessage(String msg) {
    if (mounted) setState(() => _gpsMessage = msg);
  }

  // --------------------------- FIREBASE ------------------------------------
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
      debugPrint('Erreur synchronisation Firebase : $e');
    }
  }

  Future<void> _toggleService() async {
    if (_isOnline) {
      final ok = await _confirm('Fin de service',
          'Voulez-vous vraiment quitter le service ?');
      if (!ok) return;
    }
    setState(() {
      _isOnline = !_isOnline;
      if (!_isOnline) {
        _sosActive = false;
        _currentStatus = _statusList[0];
      }
    });
    if (_isOnline) {
      await _sendDataToFirebase();
      _snack('Prise de service enregistrée auprès du CSU.');
    } else {
      try {
        await _dbRef.child('units/$_unitId').remove();
      } catch (e) {
        debugPrint('Erreur fin de service : $e');
      }
      _snack('Fin de service. Unité déconnectée.');
    }
  }

  Future<void> _triggerSOS() async {
    if (!_sosActive) {
      // Évite le déclenchement accidentel.
      final ok = await _confirm('SOS détresse',
          'Déclencher l\'alerte SOS vers le CSU ?');
      if (!ok) return;
    }
    setState(() {
      _sosActive = !_sosActive;
      _currentStatus = _sosActive ? 'SOS ACTIF' : _statusList[0];
    });
    if (_isOnline) _sendDataToFirebase();
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || !_isOnline) return;
    _msgController.clear();
    try {
      await _dbRef.child('messages').push().set({
        'sender': _unitId,
        'text': text,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Erreur envoi message : $e');
    }
  }

  // ------------------------------ UI ---------------------------------------
  Future<bool> _confirm(String title, String content) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    return res ?? false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showEquipmentModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => Container(
          padding: const EdgeInsets.all(16),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gestion du Matériel Embarqué',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(
                child: ListView(
                  children: _equipment.keys.map((key) {
                    return CheckboxListTile(
                      title: Text(key),
                      value: _equipment[key],
                      onChanged: (v) {
                        setStateModal(() => _equipment[key] = v ?? false);
                        setState(() {});
                        if (_isOnline) _sendDataToFirebase();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return StreamBuilder<DatabaseEvent>(
      stream: _dbRef.child('messages').limitToLast(20).onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Messagerie indisponible'));
        }
        final raw = snapshot.data?.snapshot.value;
        if (raw == null) return const Center(child: Text('Aucun message'));

        // Firebase peut renvoyer une Map (cas normal) ou une List.
        final List<Map<dynamic, dynamic>> msgs = [];
        if (raw is Map) {
          for (final v in raw.values) {
            if (v is Map) msgs.add(v);
          }
        } else if (raw is List) {
          for (final v in raw) {
            if (v is Map) msgs.add(v);
          }
        }
        msgs.sort((a, b) => ((a['timestamp'] ?? 0) as num)
            .compareTo((b['timestamp'] ?? 0) as num));

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final msg = msgs[i];
            final isMe = msg['sender'] == _unitId;
            return Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe ? Colors.blue[800] : Colors.grey[700],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${msg['sender']}: ${msg['text']}'),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _currentPosition;
    return Scaffold(
      appBar: AppBar(
        title: Text('Rezo+ : $_unitId'),
        backgroundColor: _sosActive ? Colors.red[900] : null,
        actions: [
          IconButton(
            icon: Icon(Icons.circle,
                color: _isOnline ? Colors.green : Colors.red),
            onPressed: _toggleService,
            tooltip: _isOnline ? 'Fin de service' : 'Prise de service',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _sosActive ? Colors.orange[800] : Colors.red[700],
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              onPressed: _isOnline ? _triggerSOS : null,
              icon: const Icon(Icons.warning, size: 30, color: Colors.white),
              label: Text(
                _sosActive ? 'DÉSACTIVER ALERTE SOS' : 'DÉCLENCHER SOS DÉTRESSE',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              color: _isOnline ? Colors.grey[900] : Colors.black26,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      _isOnline ? 'STATUT : EN LIGNE' : 'STATUT : HORS LIGNE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(pos != null
                        ? 'GPS fixé (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})'
                        : _gpsMessage),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            DropdownButton<String>(
              value: _currentStatus,
              isExpanded: true,
              items: _statusList
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _currentStatus = v;
                  _sosActive = v == 'SOS ACTIF';
                });
                if (_isOnline) _sendDataToFirebase();
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _showEquipmentModal,
              icon: const Icon(Icons.backpack),
              label: const Text('Gérer le Matériel Embarqué'),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[700]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.grey[850],
                      width: double.infinity,
                      child: const Text('Messagerie CSU Directe',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: _buildMessages()),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              decoration: const InputDecoration(
                                hintText: 'Envoyer un message au CSU...',
                                isDense: true,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.blue),
                            onPressed: _sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isOnline ? Colors.grey[800] : Colors.green,
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
