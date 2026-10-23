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
// ÉCRAN DE CONNEXION / INDICATIF RADIO (Vide par défaut)
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

  // Coordonnées fixes de base (12 Rue Roger Salengro, 94260 Fresnes)[cite: 7]
  static const double _fixedLatitude = 48.755578;
  static const double _fixedLongitude = 2.321367;

  final List<String> _statusList = [
    'En Patrouille',
    'En Intervention',
    'Contrôle PR',
    'Transport',
    'Retour au poste',
    'Indisponible',
    'SOS ACTIF',
  ];

  late String _currentStatus = _statusList[0];

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

  bool _isOnline = true;
  bool _sosActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendDataToFirebase();
    });
  }

  // --------------------------- FIREBASE ------------------------------------
  
  String _getStatusColorHex(String status) {
    switch (status) {
      case 'En Patrouille':
        return '#22bb33';
      case 'En Intervention':
        return '#ff8800';
      case 'Contrôle PR':
        return '#009688';
      case 'Transport':
        return '#00a8ff';
      case 'Retour au poste':
        return '#9c27b0';
      case 'Indisponible':
        return '#777777';
      case 'SOS ACTIF':
        return '#ff2222';
      default:
        return '#777777';
    }
  }

  Future<void> _sendDataToFirebase() async {
    try {
      await _dbRef.child('units/${widget.unitId}').set({
        'latitude': _fixedLatitude,
        'longitude': _fixedLongitude,
        'status': _currentStatus,
        'statusColor': _getStatusColorHex(_currentStatus),
        'equipment': _equipment,
        'sos': _sosActive,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Erreur synchronisation Firebase : $e');
    }
  }

  Future<void> _changeStatus(String newStatus) async {
    setState(() {
      _currentStatus = newStatus;
      _sosActive = (newStatus == 'SOS ACTIF');
    });
    await _sendDataToFirebase();
    if (_sosActive) {
      _snack('ALERTE SOS DÉCLENCHÉE !');
    } else {
      _snack('Statut mis à jour : $newStatus');
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
  Color _getStatusColor(String status) {
    switch (status) {
      case 'En Patrouille':
        return Colors.green.shade700;
      case 'En Intervention':
        return Colors.orange.shade800;
      case 'Contrôle PR':
        return Colors.teal.shade700;
      case 'Transport':
        return Colors.blue.shade700;
      case 'Retour au poste':
        return Colors.purple.shade700;
      case 'Indisponible':
        return Colors.grey.shade800;
      case 'SOS ACTIF':
        return Colors.red.shade900;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Unité : ${widget.unitId}'),
        backgroundColor: _sosActive ? Colors.red[900] : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _toggleService,
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Bouton SOS d'urgence visible immédiatement en haut
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _sosActive ? Colors.orange[800] : Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _changeStatus(_sosActive ? 'En Patrouille' : 'SOS ACTIF'),
              icon: const Icon(Icons.warning, size: 24, color: Colors.white),
              label: Text(
                _sosActive ? 'DÉSACTIVER L\'ALERTE SOS' : 'DÉCLENCHER UN SOS',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),

            // 2. Statut actuel & Localisation fixe
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getStatusColor(_currentStatus),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                children: [
                  const Text('STATUT OPÉRATIONNEL ACTUEL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(_currentStatus.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text(
                    'Position : 12 Rue Roger Salengro, Fresnes',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. Grille des boutons de statuts rapides (avec surbrillance active)
            const Text('Modifier le statut :', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.8,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: _statusList.where((s) => s != 'SOS ACTIF').map((status) {
                final bool isActive = (status == _currentStatus);
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getStatusColor(status),
                    elevation: isActive ? 8 : 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: isActive
                          ? const BorderSide(color: Colors.white, width: 3)
                          : const BorderSide(color: Colors.transparent, width: 0),
                    ),
                  ),
                  onPressed: () => _changeStatus(status),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 24),

            // 4. Contrôle du Matériel Embarqué
            const Text('Contrôle du Matériel Embarqué :', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 3.2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: _equipment.keys.map((item) {
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.black12,
                  ),
                  child: CheckboxListTile(
                    title: Text(item, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    value: _equipment[item],
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    onChanged: (val) {
                      setState(() {
                        _equipment[item] = val ?? false;
                      });
                      _sendDataToFirebase();
                    },
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
