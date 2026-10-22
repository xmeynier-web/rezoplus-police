import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint("Erreur d'initialisation Firebase : $e");
    }
    runApp(const RezoPlusMobileApp());
  }, (error, stack) {
    debugPrint("Erreur critique : $error");
  });
}

class RezoPlusMobileApp extends StatelessWidget {
  const RezoPlusMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'REZO+',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF13131D),
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(),
    );
  }
}

// ==========================================
// 1. ÉCRAN DE CONNEXION
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _unitController = TextEditingController();

  void _connectUnit() {
    String unitId = _unitController.text.trim().toUpperCase();
    if (unitId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un indicatif radio (ex: CS)')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PatrolDashboardScreen(unitId: unitId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'REZO+ // Connexion Équipage',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
        ),
        backgroundColor: const Color(0xFF1A1A26),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFF4285F4),
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(50),
                    top: Radius.circular(10),
                  ),
                ),
                child: const Icon(
                  Icons.star,
                  size: 60,
                  color: Color(0xFF13131D),
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Entrez votre indicatif radio :',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _unitController,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'Ex: ALPHA-1, BRAVO-2...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.normal),
                  filled: true,
                  fillColor: const Color(0xFF1A1A26),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.grey, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A8CFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _connectUnit,
                  child: const Text(
                    'Démarrer la prise de service',
                    style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. DASHBOARD UNITÉ
// ==========================================
class PatrolDashboardScreen extends StatefulWidget {
  final String unitId;
  const PatrolDashboardScreen({super.key, required this.unitId});

  @override
  State<PatrolDashboardScreen> createState() => _PatrolDashboardScreenState();
}

class _PatrolDashboardScreenState extends State<PatrolDashboardScreen> {
  final List<Map<String, dynamic>> availableStatuses = [
    {'id': 'EN_PATROUILLE', 'label': 'En Patrouille', 'color': const Color(0xFF4CAF50), 'bg': const Color(0xFF1B2E21)},
    {'id': 'EN_INTERVENTION', 'label': 'En Intervention', 'color': const Color(0xFFFF9800), 'bg': const Color(0xFF332211)},
    {'id': 'CONTROLE_PR', 'label': 'Contrôle PR', 'color': const Color(0xFF009688), 'bg': const Color(0xFF113330)},
    {'id': 'TRANSPORT_ESCORTE', 'label': 'Transport / Escorte', 'color': const Color(0xFF2196F3), 'bg': const Color(0xFF112233)},
    {'id': 'ESCALE_TECHNIQUE', 'label': 'Escale Technique', 'color': const Color(0xFFE91E63), 'bg': const Color(0xFF331122)},
    {'id': 'RETOUR_POSTE', 'label': 'Retour Poste', 'color': const Color(0xFF9C27B0), 'bg': const Color(0xFF2B1638)},
    {'id': 'SOS_ACTIF', 'label': 'SOS ACTIF', 'color': const Color(0xFFF44336), 'bg': const Color(0xFF3B1212)},
  ];

  String currentStatus = 'EN_PATROUILLE';

  final Map<String, bool> equipmentState = {
    'BTD': false,
    'GAIL': false,
    'LBD': false,
    'PIE': false,
    'PSA': false,
    '❌ FAK': false,
    'Casque': false,
    'Bouclier': false,
    'Ethylo': false,
    'Test Stup': false,
    'Stop-Stick': false,
    'DSA': false,
  };

  StreamSubscription<Position>? _positionStream;
  DatabaseReference? _unitRef;

  @override
  void initState() {
    super.initState();
    _unitRef = FirebaseDatabase.instance.ref("units/${widget.unitId}");
    
    // Initialisation immédiate de l'unité dans Firebase pour forcer la visibilité au PC
    _pushInitialState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocationAndSync();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _pushInitialState() {
    try {
      _unitRef?.set({
        "status": currentStatus,
        "equipment": equipmentState,
        "derniere_maj": ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Erreur initialisation Firebase : $e");
    }
  }

  Future<void> _initLocationAndSync() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return;
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        // Envoi isolé de la position pour ne pas perturber le statut
        _unitRef?.update({
          "latitude": position.latitude,
          "longitude": position.longitude,
          "derniere_maj": ServerValue.timestamp,
        });
      });
    } catch (e) {
      debugPrint("Erreur GPS : $e");
    }
  }

  void _changeStatus(String newStatus) {
    setState(() {
      currentStatus = newStatus;
    });

    // Mise à jour immédiate et explicite du statut et du matériel dans Firebase
    try {
      _unitRef?.update({
        "status": newStatus,
        "equipment": equipmentState,
        "derniere_maj": ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Erreur mise à jour statut : $e");
    }
  }

  void _updateEquipment() {
    try {
      _unitRef?.update({
        "equipment": equipmentState,
        "derniere_maj": ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Erreur mise à jour matériel : $e");
    }
  }

  void _disconnectUnit() async {
    try {
      _positionStream?.cancel();
      await _unitRef?.remove();
    } catch (e) {
      debugPrint("Erreur suppression unité : $e");
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Map<String, dynamic> _getCurrentStatusConfig() {
    return availableStatuses.firstWhere(
      (s) => s['id'] == currentStatus,
      orElse: () => availableStatuses[0],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusConfig = _getCurrentStatusConfig();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Unité : ${widget.unitId}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.normal),
        ),
        backgroundColor: const Color(0xFF13131D),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 28),
            onPressed: _disconnectUnit,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Cadre de Statut Actuel avec couleurs dynamiques
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusConfig['bg'],
                border: Border.all(color: statusConfig['color'], width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'STATUT OPÉRATIONNEL ACTUEL',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    currentStatus,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: statusConfig['color'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                      SizedBox(width: 5),
                      Text(
                        'Synchronisé avec le CSU',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 13),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Bouton SOS
            SizedBox(
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF44336),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _changeStatus('SOS_ACTIF'),
                icon: const Icon(Icons.warning_rounded, color: Colors.white, size: 28),
                label: const Text(
                  'DÉCLENCHEMENT SOS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 25),

            // 3. Grille des statuts
            const Text(
              'Modifier le statut :',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: availableStatuses.length - 1,
              itemBuilder: (context, index) {
                final status = availableStatuses[index];
                final isSelected = currentStatus == status['id'];
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status['color'],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: isSelected
                          ? const BorderSide(color: Colors.white, width: 3)
                          : BorderSide.none,
                    ),
                  ),
                  onPressed: () => _changeStatus(status['id']),
                  child: Text(
                    status['label'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
            const Divider(color: Colors.grey, thickness: 0.8),
            const SizedBox(height: 10),

            // 4. Contrôle du matériel
            const Text(
              'Contrôle du Matériel Embarqué :',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: equipmentState.keys.length,
              itemBuilder: (context, index) {
                String key = equipmentState.keys.elementAt(index);
                bool value = equipmentState[key]!;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF294372), width: 1.5),
                  ),
                  child: CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    title: Text(
                      key,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    value: value,
                    activeColor: const Color(0xFF4285F4),
                    onChanged: (bool? newValue) {
                      setState(() {
                        equipmentState[key] = newValue ?? false;
                      });
                      _updateEquipment();
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
