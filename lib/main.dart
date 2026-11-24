import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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
                  const Text('Impossible d\'initialiser Firebase.'),
                  const SizedBox(height: 12),
                  SelectableText('${snap.error}', style: const TextStyle(color: Colors.orangeAccent)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _retry, child: const Text('Réessayer')),
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
      appBar: AppBar(title: const Text('REZO+ // Connexion Équipement')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text('Entrez votre indicatif radio :', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

class PatrouilleHomePage extends StatefulWidget {
  final String unitId;
  const PatrouilleHomePage({super.key, required this.unitId});

  @override
  State<PatrouilleHomePage> createState() => _PatrouilleHomePageState();
}

class _PatrouilleHomePageState extends State<PatrouilleHomePage> with WidgetsBindingObserver {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  double _currentLatitude = 48.755578;
  double _currentLongitude = 2.321367;
  String _locationStatus = "Initialisation du capteur...";
  bool _isRefreshingLocation = false;

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  StreamSubscription<DatabaseEvent>? _missionSubscription;

  Map<dynamic, dynamic>? _activeMission;

  final List> _statusList = [
    {'label': 'En Patrouille', 'code': 'EN_PATROUILLE', 'hex': '#22bb33'},
    {'label': 'En Intervention', 'code': 'EN_INTERVENTION', 'hex': '#ff8800'},
    {'label': 'Contrôle PR', 'code': 'CONTROLE_PR', 'hex': '#f1c40f'},
    {'label': 'Transport\nEscorte', 'code': 'TRANSPORT_ESCORTE', 'hex': '#00a8ff'},
    {'label': 'Attente\nFourrière', 'code': 'ATTENTE_FOURRIERE', 'hex': '#009688'},
    {'label': 'Escale\nTechnique', 'code': 'ESCALE_TECHNIQUE', 'hex': '#e91e63'},
    {'label': 'Retour\nau poste', 'code': 'RETOUR_POSTE', 'hex': '#9c27b0'},
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
    WidgetsBinding.instance.addObserver(this);

    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (!mounted) return;
      if (status == ServiceStatus.enabled) {
        _initRobustGeolocation();
      } else {
        setState(() => _locationStatus = "GPS désactivé dans les réglages");
        _sendDataToFirebase();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initRobustGeolocation();
      _listenToAssignedMissions();
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _missionSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPositionNow(showFeedback: false);
    }
  }

  Future<bool> _ensureLocationReady() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() => _locationStatus = "GPS désactivé dans les réglages");
        _snack("Veuillez activer la localisation Android");
      }
      await _sendDataToFirebase();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() => _locationStatus = "Permission GPS refusée");
          _snack("Autorisation de localisation requise");
        }
        await _sendDataToFirebase();
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _locationStatus = "Permission bloquée (Paramètres requis)");
        _showSettingsPermissionDialog();
      }
      return false;
    }

    return true;
  }

  Future<void> _initRobustGeolocation() async {
    final ready = await _ensureLocationReady();
    if (!ready || !mounted) return;

    setState(() => _locationStatus = "Recherche de position en cours...");

    try {
      final Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null && mounted) {
        setState(() {
          _currentLatitude = lastPosition.latitude;
          _currentLongitude = lastPosition.longitude;
          _locationStatus =
              "Dernière position (${lastPosition.latitude.toStringAsFixed(4)}, ${lastPosition.longitude.toStringAsFixed(4)})";
        });
        await _sendDataToFirebase();
      }
    } catch (_) {}

    await _refreshPositionNow(showFeedback: false);

    await _positionStreamSubscription?.cancel();
    const LocationSettings streamSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: streamSettings).listen(
      (Position position) {
        if (!mounted) return;
        setState(() {
          _currentLatitude = position.latitude;
          _currentLongitude = position.longitude;
          _locationStatus =
              "GPS Actif (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})";
        });
        _sendDataToFirebase();
      },
      onError: (e) {
        debugPrint("Erreur flux GPS : $e");
        if (mounted) {
          setState(() => _locationStatus = "Signal GPS instable");
        }
      },
    );
  }

  Future<void> _refreshPositionNow({required bool showFeedback}) async {
    if (!mounted) return;
    setState(() => _isRefreshingLocation = true);

    try {
      Position? acquired;
      try {
        acquired = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } catch (_) {
        acquired = await Geolocator.getCurrentPosition(
          locationSettings: const AndroidSettings(
            accuracy: LocationAccuracy.medium,
            forceLocationManager: true,
            timeLimit: Duration(seconds: 6),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _currentLatitude = acquired!.latitude;
          _currentLongitude = acquired.longitude;
          _locationStatus =
              "GPS Fixé (${acquired.latitude.toStringAsFixed(4)}, ${acquired.longitude.toStringAsFixed(4)})";
        });
        await _sendDataToFirebase();
        if (showFeedback) {
          _snack("Position GPS actualisée");
        }
      }
    } catch (_) {
      if (mounted && showFeedback) {
        _snack("Position non disponible pour le moment, conservation du dernier point");
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingLocation = false);
      }
    }
  }

  void _showSettingsPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorisation GPS requise'),
        content: const Text(
          'L\'accès à la localisation a été refusé de manière permanente. '
          'Ouvrez les paramètres de l\'application pour autoriser la position.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Paramètres', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _listenToAssignedMissions() {
    _missionSubscription = _dbRef.child('units/${widget.unitId}').onValue.listen((event) {
      if (event.snapshot.value != null && event.snapshot.value is Map && mounted) {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);

        setState(() {
          if (data['active_mission'] != null && data['active_mission'] is Map) {
            _activeMission = Map<dynamic, dynamic>.from(data['active_mission']);
          } else {
            _activeMission = null;
          }

          final remoteStatus = data['status'];
          if (remoteStatus != null) {
            try {
              _currentStatusMap = _statusList.firstWhere((s) => s['code'] == remoteStatus);
            } catch (_) {}
          }
        });
      }
    });
  }

  Future<void> _sendDataToFirebase() async {
    try {
      await _dbRef.child('units/${widget.unitId}').update({
        'latitude': _currentLatitude,
        'longitude': _currentLongitude,
        'status': _currentStatusMap['code'],
        'statusLabel': _currentStatusMap['label']?.replaceAll('\n', ' '),
        'statusColor': _currentStatusMap['hex'],
        'equipment': _equipment,
        'sos': _currentStatusMap['code'] == 'SOS_ACTIF',
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Erreur Firebase : $e');
    }
  }

  Future<void> _changeStatus(Map<String, String> statusMap) async {
    setState(() {
      _currentStatusMap = statusMap;
      _locationStatus = "Actualisation position...";
    });

    await _refreshPositionNow(showFeedback: false);
    await _sendDataToFirebase();

    final cleanLabel = statusMap['label']?.replaceAll('\n', ' ') ?? '';
    _snack(statusMap['code'] == 'SOS_ACTIF' ? 'ALERTE SOS DÉCLENCHÉE !' : 'Statut : $cleanLabel');
  }

  Future<void> _endMission() async {
    final patrouilleStatus = _statusList.firstWhere((s) => s['code'] == 'EN_PATROUILLE');
    await _changeStatus(patrouilleStatus);

    try {
      await _dbRef.child('units/${widget.unitId}').update({
        'active_mission': null,
      });
      _snack('Intervention clôturée.');
    } catch (e) {
      debugPrint('Erreur fin mission : $e');
    }
  }

  Future<void> _toggleService() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fin de service'),
        content: const Text('Voulez-vous vraiment quitter le service et vous déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
        ],
      ),
    );

    if (ok == true) {
      await _positionStreamSubscription?.cancel();
      await _serviceStatusSubscription?.cancel();
      await _missionSubscription?.cancel();
      try {
        await _dbRef.child('units/${widget.unitId}').remove();
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Color _getStatusColor(String code) {
    switch (code) {
      case 'EN_PATROUILLE':
        return Colors.green.shade700;
      case 'EN_INTERVENTION':
        return Colors.orange.shade800;
      case 'CONTROLE_PR':
        return Colors.amber.shade700;
      case 'TRANSPORT_ESCORTE':
        return Colors.blue.shade700;
      case 'ATTENTE_FOURRIERE':
        return Colors.teal.shade700;
      case 'ESCALE_TECHNIQUE':
        return Colors.pink.shade700;
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

  @override
  Widget build(BuildContext context) {
    final bool isSosActive = (_currentStatusMap['code'] == 'SOS_ACTIF');
    final int checkedEquipmentCount = _equipment.values.where((v) => v).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Unité : ${widget.unitId}', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isSosActive ? Colors.red[900] : const Color(0xFF222230),
        actions: [
          IconButton(
            icon: _isRefreshingLocation
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.my_location),
            onPressed: _isRefreshingLocation ? null : () => _refreshPositionNow(showFeedback: true),
            tooltip: 'Actualiser la position GPS',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _toggleService,
            tooltip: 'Fin de service',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSosActive ? Colors.orange[800] : Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final targetStatus = isSosActive
                    ? _statusList.firstWhere((s) => s['code'] == 'EN_PATROUILLE')
                    : _statusList.firstWhere((s) => s['code'] == 'SOS_ACTIF');
                _changeStatus(targetStatus);
              },
              icon: const Icon(Icons.warning_amber_rounded, size: 24, color: Colors.white),
              label: Text(
                isSosActive ? 'DÉSACTIVER L\'ALERTE SOS' : 'DÉCLENCHER UN SOS',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: _getStatusColor(_currentStatusMap['code']!),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white30),
              ),
              child: Column(
                children: [
                  const Text(
                    'STATUT OPÉRATIONNEL ACTUEL',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white75, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentStatusMap['label']!.replaceAll('\n', ' ').toUpperCase(),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.gps_fixed, size: 13, color: Colors.white75),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _locationStatus,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_activeMission != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orangeAccent, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.assignment_late, size: 16, color: Colors.orangeAccent),
                        SizedBox(width: 6),
                        Text(
                          'MISSION CSU EN COURS',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orangeAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Objet : ${_activeMission!['title'] ?? _activeMission!['titre'] ?? 'Intervention'}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Lieu : ${_activeMission!['location'] ?? _activeMission!['adresse'] ?? 'Non précisé'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: _endMission,
                        icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                        label: const Text('Fin d\'intervention', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            const Text('Modifier le statut :', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.55,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: _statusList.where((s) => s['code'] != 'SOS_ACTIF').map((statusMap) {
                final bool isActive = (statusMap['code'] == _currentStatusMap['code']);
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getStatusColor(statusMap['code']!),
                    elevation: isActive ? 8 : 2,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: isActive ? const BorderSide(color: Colors.white, width: 3) : BorderSide.none,
                    ),
                  ),
                  onPressed: () => _changeStatus(statusMap),
                  child: Text(
                    statusMap['label']!,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 13,
                      height: 1.15,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Contrôle du Matériel Embarqué :', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text(
                  '$checkedEquipmentCount / ${_equipment.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent),
                ),
              ],
            ),
            const SizedBox(height: 8),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 3.1,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: _equipment.keys.map((item) {
                final bool checked = _equipment[item] ?? false;
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: checked ? Colors.lightBlueAccent : Colors.blue.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(8),
                    color: checked ? Colors.blue.withValues(alpha: 0.18) : Colors.black12,
                  ),
                  child: CheckboxListTile(
                    title: Text(item, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    value: checked,
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    onChanged: (val) {
                      setState(() => _equipment[item] = val ?? false);
                      _sendDataToFirebase();
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
