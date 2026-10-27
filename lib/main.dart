import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        databaseURL:
            "https://rezoplus-police-default-rtdb.europe-west1.firebasedatabase.app",
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
                  SelectableText(
                    '${snap.error}',
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('Réessayer'),
                  ),
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

  void _startService() {
    final unitId = _controller.text.trim();
    if (unitId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer un indicatif radio valide.'),
        ),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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

class _PatrouilleHomePageState extends State<PatrouilleHomePage>
    with WidgetsBindingObserver {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final DatabaseReference _mainCouranteRef =
      FirebaseDatabase.instance.ref().child('mains_courantes');

  double? _currentLatitude;
  double? _currentLongitude;
  bool _gpsReady = false;

  String _locationStatus = "Vérification des permissions GPS...";
  bool _permissionDenied = false;

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<DatabaseEvent>? _missionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _watchdogTimer;

  List<Map<String, dynamic>> _offlineQueue = [];
  bool _isSyncing = false;

  Map<dynamic, dynamic>? _activeMission;
  String _missionStatus = 'AUCUN';
  String _missionFeedback = 'Aucune information';
  bool _missionPopupVisible = false;

  final List<Map<String, String>> _statusList = [
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

    _loadOfflineQueue().then((_) {
      _flushOfflineQueue();
    });

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool hasConnection =
          results.any((result) => result != ConnectivityResult.none);

      if (hasConnection) {
        debugPrint('📶 Réseau rétabli ! Synchronisation du buffer...');
        _flushOfflineQueue();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestPermissionAndStartGPS();
      _listenToAssignedMissions();
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _missionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _watchdogTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRequestPermissionAndStartGPS();
      _sendDataToFirebase();
    }
  }

  Future<void> _loadOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? storedData = prefs.getString('offline_gps_queue');
      if (storedData != null) {
        final List<dynamic> decodedList = jsonDecode(storedData);
        setState(() {
          _offlineQueue =
              decodedList.map((item) => Map<String, dynamic>.from(item)).toList();
        });
        debugPrint('📂 Buffer restauré : ${_offlineQueue.length} points en attente.');
      }
    } catch (e) {
      debugPrint('Erreur chargement buffer : $e');
    }
  }

  Future<void> _saveOfflineQueueToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encodedData = jsonEncode(_offlineQueue);
      await prefs.setString('offline_gps_queue', encodedData);
    } catch (e) {
      debugPrint('Erreur sauvegarde buffer : $e');
    }
  }

  Future<void> _flushOfflineQueue() async {
    if (_isSyncing || _offlineQueue.isEmpty) return;

    _isSyncing = true;

    try {
      while (_offlineQueue.isNotEmpty) {
        final item = _offlineQueue.first;
        await _dbRef.child('units/${widget.unitId}').update(item);
        _offlineQueue.removeAt(0);
        await _saveOfflineQueueToDisk();
      }
      debugPrint('✅ Buffer entièrement synchronisé.');
    } catch (e) {
      debugPrint('Échec de la synchronisation du buffer : $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _checkAndRequestPermissionAndStartGPS() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationStatus = 'GPS désactivé sur le terminal';
        _permissionDenied = true;
      });
      _snack('Veuillez activer le GPS dans la barre d\'état du Crosscall');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationStatus = 'Permission GPS refusée par l\'utilisateur';
          _permissionDenied = true;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationStatus = 'Permission bloquée définitivement';
        _permissionDenied = true;
      });
      _showSettingsPermissionDialog();
      return;
    }

    if (permission == LocationPermission.whileInUse) {
      setState(() {
        _locationStatus =
            'Permission GPS en premier plan uniquement. Activez "Toujours".';
        _permissionDenied = true;
      });
      _showBackgroundPermissionDialog();
      return;
    }

    if (permission != LocationPermission.always) {
      setState(() {
        _locationStatus =
            'Autorisation GPS non conforme. Permission "Toujours" requise.';
        _permissionDenied = true;
      });
      _showBackgroundPermissionDialog();
      return;
    }

    _gpsReady = false;
    setState(() {
      _permissionDenied = false;
      _locationStatus = 'Acquisition du signal GPS...';
    });

    await _initRobustGeolocation();
  }

  void _resetWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(const Duration(seconds: 30), () {
      debugPrint(
          '⚠️ Watchdog : Aucune position reçue depuis 30s. Redémarrage du GPS...');
      setState(() => _locationStatus = 'Signal figé - Redémarrage GPS...');
      _restartGeolocationStream();
    });
  }

  Future<void> _restartGeolocationStream() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    await _initRobustGeolocation();
  }

  Future<void> _initRobustGeolocation() async {
    try {
      final Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        _currentLatitude = lastPosition.latitude;
        _currentLongitude = lastPosition.longitude;
        _gpsReady = true;
        setState(() {
          _locationStatus =
              'Cache OK (${lastPosition.latitude.toStringAsFixed(4)}, ${lastPosition.longitude.toStringAsFixed(4)})';
        });
        await _sendDataToFirebase();
      }
    } catch (_) {}

    try {
      final Position currentPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
        forceAndroidLocationManager: true,
      );
      _currentLatitude = currentPos.latitude;
      _currentLongitude = currentPos.longitude;
      _gpsReady = true;
      setState(() {
        _locationStatus =
            'GPS Natif Fixé (${currentPos.latitude.toStringAsFixed(4)}, ${currentPos.longitude.toStringAsFixed(4)})';
      });
      await _sendDataToFirebase();
    } catch (e) {
      debugPrint('Échec fix immédiat : $e');
    }

    if (_currentLatitude == null || _currentLongitude == null) {
      setState(() {
        _locationStatus = 'En attente d\'un signal GPS valide...';
      });
    }

    final LocationSettings locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Rezo+ en service',
        notificationText: 'Le suivi GPS de la patrouille est actif.',
        enableWakeLock: true,
      ),
      forceLocationManager: true,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        _gpsReady = true;
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;

        _resetWatchdog();
        setState(() {
          _locationStatus = _offlineQueue.isNotEmpty
              ? 'Hors-ligne (Buffer : ${_offlineQueue.length})'
              : 'GPS Actif (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})';
        });

        _sendDataToFirebase();
      },
      onError: (e) {
        debugPrint('Erreur flux GPS : $e');
        _gpsReady = false;
        setState(() => _locationStatus = 'Perte de signal GPS');
      },
    );

    _resetWatchdog();
  }

  void _showSettingsPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorisation GPS requise'),
        content: const Text(
          'Les permissions de géolocalisation ont été refusées. '
          'Veuillez autoriser la localisation dans les paramètres de l\'application.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Ouvrir les Paramètres', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showBackgroundPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorisation de suivi en arrière-plan'),
        content: const Text(
          'Pour que la géolocalisation reste active pendant le service, '
          'l’application doit être autorisée en mode “Toujours”. '
          'Ouvrez les paramètres et activez la localisation en arrière-plan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Ouvrir les Paramètres', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _closeMissionPopupIfNeeded() {
    if (_missionPopupVisible && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _missionPopupVisible = false;
  }

  void _showMissionPopupIfNeeded() {
    if (_missionStatus == 'TERMINEE' || _activeMission == null) {
      _closeMissionPopupIfNeeded();
      return;
    }

    if (_missionPopupVisible) return;

    _missionPopupVisible = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.brown.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'MISSION CSU EN COURS',
          style: TextStyle(
            color: Colors.orangeAccent,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Statut CSU : $_missionStatus',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _missionFeedback.isNotEmpty ? _missionFeedback : 'Mission CSU active.',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                'Objet : ${_activeMission?['title'] ?? _activeMission?['titre'] ?? 'Intervention'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Lieu : ${_activeMission?['location'] ?? _activeMission?['adresse'] ?? 'Non précisé'}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _missionPopupVisible = false;
              _endMission();
            },
            icon: const Icon(Icons.check),
            label: const Text(
              'Fin d\'intervention',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ).then((_) {
      _missionPopupVisible = false;
    });
  }

  void _listenToAssignedMissions() {
    _missionSubscription = _dbRef.child('units/${widget.unitId}').onValue.listen((event) {
      if (event.snapshot.value != null && event.snapshot.value is Map) {
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

          if (data['mission_status'] != null) {
            _missionStatus = data['mission_status'].toString();
          } else if (_activeMission != null) {
            _missionStatus = 'MISSION EN COURS';
          } else {
            _missionStatus = 'AUCUN';
          }

          if (data['mission_feedback'] != null) {
            _missionFeedback = data['mission_feedback'].toString();
          } else if (_activeMission != null) {
            _missionFeedback = 'Mission active en cours';
          } else {
            _missionFeedback = 'Aucune information';
          }
        });

        if (_missionStatus == 'TERMINEE' || _activeMission == null) {
          _closeMissionPopupIfNeeded();
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showMissionPopupIfNeeded();
          });
        }
      } else {
        setState(() {
          _activeMission = null;
          _missionStatus = 'AUCUN';
          _missionFeedback = 'Aucune information';
        });
        _closeMissionPopupIfNeeded();
      }
    });
  }

  Map<String, dynamic> _buildUnitPayload() {
    return {
      'latitude': _currentLatitude,
      'longitude': _currentLongitude,
      'status': _currentStatusMap['code'],
      'statusLabel': _currentStatusMap['label']?.replaceAll('\n', ' '),
      'statusColor': _currentStatusMap['hex'],
      'equipment': _equipment,
      'sos': _currentStatusMap['code'] == 'SOS_ACTIF',
      'mission_status': _missionStatus,
      'mission_feedback': _missionFeedback,
      'active_mission': _activeMission,
      'timestamp': ServerValue.timestamp,
    };
  }

  Future<void> _writeMainCourante(String message, String color) async {
    try {
      await _mainCouranteRef.push().set({
        'message': message,
        'author': widget.unitId,
        'statusColor': color,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Erreur main-courante : $e');
    }
  }

  Future<void> _sendDataToFirebase() async {
    if (!_gpsReady || _currentLatitude == null || _currentLongitude == null) {
      return;
    }

    final payload = _buildUnitPayload();

    try {
      await _dbRef.child('units/${widget.unitId}').update(payload);
      if (_offlineQueue.isNotEmpty) {
        _flushOfflineQueue();
      }
    } catch (e) {
      debugPrint('⚠️ Réseau absent - Ajout au buffer persistant : $e');
      _offlineQueue.add(payload);
      await _saveOfflineQueueToDisk();
      setState(() {
        _locationStatus = "Hors-ligne (Buffer : ${_offlineQueue.length})";
      });
    }
  }

  Future<void> _changeStatus(Map<String, String> statusMap) async {
    setState(() {
      _currentStatusMap = statusMap;
      _locationStatus = "Actualisation position (Statut)...";

      if (statusMap['code'] == 'SOS_ACTIF') {
        _missionStatus = 'SOS_ACTIF';
        _missionFeedback = 'Alerte SOS déclenchée';
      } else if (_activeMission != null) {
        _missionStatus = 'MISSION EN COURS';
        _missionFeedback = 'Mission active en cours';
      } else {
        _missionStatus = 'AUCUN';
        _missionFeedback = 'Aucune information';
      }
    });

    try {
      final Position forcedPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
        forceAndroidLocationManager: true,
      );
      _gpsReady = true;
      _currentLatitude = forcedPos.latitude;
      _currentLongitude = forcedPos.longitude;
      setState(() {
        _locationStatus =
            "GPS Forcé (${forcedPos.latitude.toStringAsFixed(4)}, ${forcedPos.longitude.toStringAsFixed(4)})";
      });
    } catch (_) {}

    await _sendDataToFirebase();

    if (statusMap['code'] == 'SOS_ACTIF') {
      await _writeMainCourante(
        'ALERTE SOS déclenchée par ${widget.unitId}',
        '#ff2222',
      );
    } else if (statusMap['code'] == 'EN_PATROUILLE') {
      await _writeMainCourante(
        'Unité ${widget.unitId} : statut ${statusMap['label']?.replaceAll('\n', ' ') ?? ''}',
        statusMap['hex'] ?? '#777777',
      );
    }

    _snack(
      statusMap['code'] == 'SOS_ACTIF'
          ? 'ALERTE SOS DÉCLENCHÉE !'
          : 'Statut : ${statusMap['label']?.replaceAll('\n', ' ') ?? ''}',
    );
  }

  Future<void> _endMission() async {
    final patrouilleStatus = _statusList.firstWhere((s) => s['code'] == 'EN_PATROUILLE');

    setState(() {
      _currentStatusMap = patrouilleStatus;
      _missionStatus = 'TERMINEE';
      _missionFeedback = 'Mission terminée';
      _activeMission = null;
      _locationStatus = "Mission terminée - retour au statut En Patrouille";
    });

    try {
      await _dbRef.child('units/${widget.unitId}').update({
        'status': patrouilleStatus['code'],
        'statusLabel': patrouilleStatus['label']?.replaceAll('\n', ' '),
        'statusColor': patrouilleStatus['hex'],
        'mission_status': 'TERMINEE',
        'mission_feedback': 'Mission terminée',
        'active_mission': null,
      });

      await _writeMainCourante(
        'FIN MISSION -> Unité ${widget.unitId} a clôturé l’intervention',
        '#22bb33',
      );

      _snack('Intervention clôturée avec succès.');
      _closeMissionPopupIfNeeded();
    } catch (e) {
      debugPrint('Erreur fin mission : $e');
    }

    await _changeStatus(patrouilleStatus);
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
      _positionStreamSubscription?.cancel();
      _missionSubscription?.cancel();
      _connectivitySubscription?.cancel();
      _watchdogTimer?.cancel();

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

    return Scaffold(
      appBar: AppBar(
        title: Text('Unité : ${widget.unitId}'),
        backgroundColor: isSosActive ? Colors.red[900] : null,
        actions: [
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
            if (_permissionDenied) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final LocationPermission p = await Geolocator.requestPermission();
                  if (p == LocationPermission.deniedForever) {
                    Geolocator.openAppSettings();
                  } else {
                    _checkAndRequestPermissionAndStartGPS();
                  }
                },
                icon: const Icon(Icons.location_on, color: Colors.white),
                label: const Text(
                  'AUTORISER LA GÉOLOCALISATION MAINTENANT',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSosActive ? Colors.orange[800] : Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final targetStatus = isSosActive
                    ? _statusList.firstWhere((s) => s['code'] == 'EN_PATROUILLE')
                    : _statusList.firstWhere((s) => s['code'] == 'SOS_ACTIF');

                _changeStatus(targetStatus);
              },
              icon: const Icon(Icons.warning, size: 24, color: Colors.white),
              label: Text(
                isSosActive ? 'DÉSACTIVER L\'ALERTE SOS' : 'DÉCLENCHER UN SOS',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getStatusColor(_currentStatusMap['code']!),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                children: [
                  const Text(
                    'STATUT OPÉRATIONNEL ACTUEL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentStatusMap['label']!.replaceAll('\n', ' ').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _locationStatus,
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (_activeMission != null ||
                _missionStatus == 'EN_COURS' ||
                _missionStatus == 'TERMINEE') ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _missionStatus == 'TERMINEE'
                      ? Colors.brown.shade900.withOpacity(0.9)
                      : Colors.orange.shade900.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MISSION CSU EN COURS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Statut CSU : ${_missionStatus}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Retour CSU : ${_missionFeedback.isNotEmpty ? _missionFeedback : 'Mission CSU active.'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    if (_activeMission != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Objet : ${_activeMission!['title'] ?? _activeMission!['titre'] ?? 'Intervention'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Lieu : ${_activeMission!['location'] ?? _activeMission!['adresse'] ?? 'Non précisé'}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (_missionStatus != 'TERMINEE') ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: _endMission,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text(
                            'Fin d\'intervention',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () {
                            setState(() {
                              _missionStatus = 'AUCUN';
                              _missionFeedback = 'Aucune information';
                              _activeMission = null;
                            });
                            _closeMissionPopupIfNeeded();
                            _sendDataToFirebase();
                          },
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Fermer', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            const Text(
              'Modifier le statut :',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: _statusList
                  .where((s) => s['code'] != 'SOS_ACTIF')
                  .map((statusMap) {
                final bool isActive = (statusMap['code'] == _currentStatusMap['code']);
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getStatusColor(statusMap['code']!),
                    elevation: isActive ? 8 : 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: isActive
                          ? const BorderSide(color: Colors.white, width: 3)
                          : BorderSide.none,
                    ),
                  ),
                  onPressed: () => _changeStatus(statusMap),
                  child: Text(
                    statusMap['label']!,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 24),

            const Text(
              'Contrôle du Matériel Embarqué :',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
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
                    title: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: _equipment[item],
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
          ],
        ),
      ),
    );
  }
}
