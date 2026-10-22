import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Erreur d'initialisation Firebase : $e");
  }
  runApp(const RezoPlusPatrouilleApp());
}

class RezoPlusPatrouilleApp extends StatelessWidget {
  const RezoPlusPatrouilleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Patrouille',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const PatrouilleHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PatrouilleHomePage extends StatefulWidget {
  const PatrouilleHomePage({Key? key}) : super(key: key);

  @override
  State<PatrouilleHomePage> createState() => _PatrouilleHomePageState();
}

class _PatrouilleHomePageState extends State<PatrouilleHomePage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final TextEditingController _msgController = TextEditingController();
  
  final String _unitId = "Patrouille-01";
  
  // Liste exacte des statuts opérationnels demandés
  final List<String> _statusList = [
    "En Patrouille",
    "En Intervention",
    "Contrôle PR",
    "Transport / Escorte",
    "Escale Technique",
    "Retour Poste",
    "SOS ACTIF"
  ];
  
  late String _currentStatus;

  // Matériel embarqué exact
  final Map<String, bool> _equipment = {
    "Stop-Stick": false,
    "BTD": false,
    "GAIL": false,
    "LBD": false,
    "PIE": false,
    "PSA": false,
    "Trousse de secours (FAK)": false,
    "Casque": false,
    "Bouclier": false,
    "Éthylotest": false,
    "Test stupéfiants": false,
    "DSA": false,
  };

  bool _isOnline = false;
  bool _sosActive = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _currentStatus = _statusList[0];
    _initGPS();
  }

  Future<void> _initGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
      });
      if (_isOnline) {
        _sendDataToFirebase();
      }
    });
  }

  Future<void> _toggleService() async {
    if (_isOnline) {
      bool confirm = await showDialog<bool>(
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
                child: const Text('Confirmer'),
              ),
            ],
          );
        },
      ) ?? false;

      if (!confirm) return;
    }

    setState(() {
      _isOnline = !_isOnline;
      if (!_isOnline) {
        _sosActive = false;
        _currentStatus = _statusList[0];
      }
    });

    if (_isOnline) {
      _sendDataToFirebase();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Prise de service enregistrée auprès du CSU.")),
      );
    } else {
      try {
        await _dbRef.child("units/$_unitId").remove();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fin de service. Unité déconnectée.")),
      );
    }
  }

  void _sendDataToFirebase() {
    if (_currentPosition == null) return;

    try {
      _dbRef.child("units/$_unitId").set({
        "latitude": _currentPosition!.latitude,
        "longitude": _currentPosition!.longitude,
        "status": _currentStatus,
        "equipment": _equipment,
        "sos": _sosActive,
        "timestamp": ServerValue.timestamp,
      });
    } catch (_) {}
  }

  void _triggerSOS() {
    setState(() {
      _sosActive = !_sosActive;
      if (_sosActive) {
        _currentStatus = "SOS ACTIF";
      } else {
        _currentStatus = _statusList[0];
      }
    });
    if (_isOnline) _sendDataToFirebase();
  }

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty || !_isOnline) return;

    try {
      _dbRef.child("messages").push().set({
        "sender": _unitId,
        "text": _msgController.text.trim(),
        "timestamp": ServerValue.timestamp,
      });
    } catch (_) {}

    _msgController.clear();
  }

  void _showEquipmentModal() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateModal) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Gestion du Matériel Embarqué",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                            setState(() {});
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Rezo+ : $_unitId"),
        backgroundColor: _sosActive ? Colors.red[900] : null,
        actions: [
          IconButton(
            icon: Icon(Icons.circle, color: _isOnline ? Colors.green : Colors.red),
            onPressed: _toggleService,
            tooltip: _isOnline ? "Fin de service" : "Prise de service",
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _sosActive ? Colors.orange[800] : Colors.red[700],
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              onPressed: _isOnline ? _triggerSOS : null,
              icon: const Icon(Icons.warning, size: 30, color: Colors.white),
              label: Text(
                _sosActive ? "DÉSACTIVER ALERTE SOS" : "DÉCLENCHER SOS DETRESSE",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              color: _isOnline ? Colors.grey[900] : Colors.black26,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text(
                      _isOnline ? "STATUT : EN LIGNE" : "STATUT : HORS LIGNE",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(_currentPosition != null
                        ? "GPS Fixé (${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)})"
                        : "Recherche du signal GPS..."),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            DropdownButton<String>(
              value: _currentStatus,
              isExpanded: true,
              items: _statusList.map((String status) {
                return DropdownMenuItem<String>(
                  value: status,
                  child: Text(status),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() => _currentStatus = newValue);
                  if (_isOnline) _sendDataToFirebase();
                }
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _showEquipmentModal,
              icon: const Icon(Icons.backpack),
              label: const Text("Gérer le Matériel Embarqué"),
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
                      child: const Text("Messagerie CSU Directe", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: StreamBuilder(
                        stream: _dbRef.child("messages").limitToLast(20).onValue,
                        builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                            return const Center(child: Text("Aucun message"));
                          }
                          Map<dynamic, dynamic> map = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                          List<MapEntry<dynamic, dynamic>> entries = map.entries.toList()
                            ..sort((a, b) => (a.value['timestamp'] ?? 0).compareTo(b.value['timestamp'] ?? 0));

                          return ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              var msg = entries[index].value;
                              bool isMe = msg['sender'] == _unitId;
                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isMe ? Colors.blue[800] : Colors.grey[700],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text("${msg['sender']}: ${msg['text']}"),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              decoration: const InputDecoration(
                                hintText: "Envoyer un message au CSU...",
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.blue),
                            onPressed: _sendMessage,
                          )
                        ],
                      ),
                    )
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
              label: Text(_isOnline ? "FIN DE SERVICE" : "PRISE DE SERVICE"),
            ),
          ],
        ),
      ),
    );
  }
}
