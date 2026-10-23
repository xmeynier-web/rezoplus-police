import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// DÉMARRAGE
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

/// Écran d'amorçage : initialise Firebase via vos options explicites
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
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCu0BK4h2hhaGV4C46C9y65rBJlnLftq3A",
        appId: "1:561209004165:web:4c19c7b505bf7",
        messagingSenderId: "561209004165",
        projectId: "rezoplus-police",
        databaseURL: "https://rezoplus-police-default-rtdb.europe-west1.firebasedatabase.app",
      ),
    ).timeout(const Duration(seconds: 15));
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
                    'Vérifiez vos paramètres de configuration et la connexion réseau.',
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
        return const LoginScreen();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ÉCRAN DE CONNEXION / INDICATIF RADIO
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _controller = TextEditingController();

  void _startService() {
    final unitId = _controller.text.trim();
    if (unitId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un indicatif radio valide.')),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => PatrouilleHomePage(unitId: unitId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('REZO+ // Connexion Équipement'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Entrez votre indicatif radio :',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Ex: ALPHA, Patrouille-01...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _startService(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _startService,
                child: const Text(
                  'Démarrer la prise de service',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ÉCRAN PRINCIPAL
// ---------------------------------------------------------------------------
class PatrouilleHomePage extends StatefulWidget {
  final String unitId;
  const PatrouilleHomePage({super.key, required this.unitId});

  @override
  State<PatrouilleHomePage> createState() => _PatrouilleHomePageState();
}

class _PatrouilleHomePageState extends State<PatrouilleHomePage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Position fixe (12 Rue Roger Salengro, Fresnes)
  static const double _fixedLatitude = 48.755578;
  static const double _fixedLongitude = 2.321367;

  // Liste des statuts avec code technique normalisé pour le CSU
  final List<Map<String, String>> _statusList = [
    {'label': 'En Patrouille', 'code': 'EN_PATROUILLE', 'hex': '#22bb33'},
    {'label': 'En Intervention', 'code': 'EN_INTERVENTION', 'hex': '#ff8800'},
    {'label': 'Contrôle PR', 'code': 'CONTROLE_PR', 'hex': '#009688'},
    {'label': 'Transport', 'code': 'TRANSPORT', 'hex': '#00a8ff'},
    {'label': 'Retour au poste', 'code': 'RETOUR_POSTE', 'hex': '#9c27b0'},
    {'label': 'Indisponible', 'code': 'INDISPONIBLE', 'hex': '#777777'},
    {'label': 'SOS ACTIF', 'code': 'SOS_ACTIF', 'hex': '#ff2222'},
  ];

  late Map<String, String> _currentStatusMap = _statusList[0];

  final Map<String, bool> _equipment = {
    'Stop-Stick': false,
    'Bouclier': false,
    'GAIL': false,
    'LBD': false,
    'PIE': false,
    'BTD': false,
    'PSA': false,
    'Casque': false,
    'Trousse PS': false,
    'Ethylo': false,
    'Kit Stup': false,
    'DSA': false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendDataToFirebase();
    });
  }

  // --------------------------- FIREBASE ------------------------------------
  Future<void> _sendDataToFirebase() async {
    try {
      await _dbRef.child('units/${widget.unitId}').set({
        'latitude': _fixedLatitude,
        'longitude': _fixedLongitude,
        'status': _currentStatusMap['code'],
        'statusLabel': _currentStatusMap['label'],
        'statusColor': _currentStatusMap['hex'],
        'equipment': _equipment,
        'sos': _currentStatusMap['code'] == 'SOS_ACTIF',
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Erreur synchronisation Firebase : $e');
    }
  }

  Future<void> _changeStatus(Map<String, String> statusMap) async {
    setState(() {
      _currentStatusMap = statusMap;
    });
    await _sendDataToFirebase();
    if (statusMap['code'] == 'SOS_ACTIF') {
      _snack('ALERTE SOS DÉCLENCHÉE !');
    } else {
      _snack('Statut mis à jour : ${statusMap['label']}');
    }
  }

  Future<void> _toggleService() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment quitter le service ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _dbRef.child('units/${widget.unitId}').remove();
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ------------------------------ UI ---------------------------------------
  Color _getStatusColor(String code) {
    switch (code) {
      case 'EN_PATROUILLE':
        return Colors.green.shade700;
      case 'EN_INTERVENTION':
        return Colors.orange.shade800;
      case 'CONTROLE_PR':
        return Colors.teal.shade700;
      case 'TRANSPORT':
        return Colors.blue.shade700;
      case 'RETOUR_POSTE':
        return Colors.purple.shade700;
      case 'INDISPONIBLE':
        return Colors.grey.shade800;
      case 'SOS_ACTIF':
        return Colors.red.shade900;
      default:
        return Colors.grey.shade700;
    }
  }

  /// Widget affichant les ordres de mission / interventions (visible uniquement si une mission existe)
  Widget _buildDispatchesBox() {
    return StreamBuilder<DatabaseEvent>(
      stream: _dbRef.child('dispatches').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final raw = snapshot.data?.snapshot.value;
        if (raw == null) {
          return const SizedBox.shrink();
        }

        final List<Map<dynamic
