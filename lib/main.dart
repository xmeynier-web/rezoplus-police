import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
  runApp(const RezoPatrouilleApp());
}

class RezoPatrouilleApp extends StatelessWidget {
  const RezoPatrouilleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezo+ Patrouille',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const PatrouilleScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PatrouilleScreen extends StatefulWidget {
  const PatrouilleScreen({Key? key}) : super(key: key);

  @override
  State<PatrouilleScreen> createState() => _PatrouilleScreenState();
}

class _PatrouilleScreenState extends State<PatrouilleScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final TextEditingController _msgCtrl = TextEditingController();
  
  final String _unitId = "Patrouille-01";
  
  // Les 7 statuts opérationnels stricts
  final List<String> _statuses = [
    "En Patrouille",
    "En Intervention",
    "Contrôle PR",
    "Transport / Escorte",
    "Escale Technique",
    "Retour Poste",
    "SOS ACTIF"
  ];
  
  late String _selectedStatus;
  bool _isOnline = false;
  bool _sosActive = false;
  Position? _pos;

  // Liste complète du matériel embarqué
  final Map<String, bool> _gear = {
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

  @override
  void initState() {
    super.initState();
    _selectedStatus = _statuses[0];
  }

  // Synchronisation Firebase propre
  void _syncData() {
    if (!_isOnline) return;
    try {
      _db.child("units/$_unitId").set({
        "latitude": _pos?.latitude ?? 48.777,
        "longitude": _pos?.longitude ?? 2.325,
        "status": _selectedStatus,
        "equipment": _gear,
        "sos": _sosActive,
        "timestamp": ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("Sync error: $e");
    }
  }

  // Gestion du service et du GPS
  Future<void> _toggleService() async {
    if (_isOnline) {
      // Fin de service
      setState(() {
        _isOnline = false;
        _sosActive = false;
        _selectedStatus = _statuses[0];
      });
      try {
        await _db.child("units/$_unitId").remove();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unité déconnectée (Fin de service).")),
        );
      }
    } else {
      // Prise de service
      bool serviceOk = await Geolocator.isLocationServiceEnabled();
      if (!serviceOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Activez le GPS pour prendre votre service.")),
        );
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }

      try {
        Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        setState(() {
          _pos = p;
          _isOnline = true;
        });
        _syncData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Prise de service enregistrée auprès du CSU.")),
          );
        }
      } catch (e) {
        debugPrint("GPS error: $e");
      }
    }
  }

  void _toggleSOS() {
    setState(() {
      _sosActive = !_sosActive;
      _selectedStatus = _sosActive ? "SOS ACTIF" : _statuses[0];
    });
    _syncData();
  }

  void _sendMessage() {
    if (_msgCtrl.text.trim().isEmpty || !_isOnline) return;
    try {
      _db.child("messages").push().set({
        "sender": _unitId,
        "text": _msgCtrl.text.trim(),
        "timestamp": ServerValue.timestamp,
      });
      _msgCtrl.clear();
    } catch (e) {
      debugPrint("Msg error: $e");
    }
  }

  void _openGearModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Gestion du Matériel Embarqué",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Divider(color: Colors.grey),
                  Expanded(
                    child: ListView(
                      children: _gear.keys.map((item) {
                        return CheckboxListTile(
                          title: Text(item, style: const TextStyle(color: Colors.white)),
                          value: _gear[item],
                          activeColor: Colors.blue,
                          onChanged: (val) {
                            setModalState(() {
                              _gear[item] = val ?? false;
                            });
                            setState(() {});
                            _syncData();
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
        backgroundColor: _sosActive ? Colors.red[900] : Colors.grey[900],
        actions: [
          IconButton(
            icon: Icon(Icons.circle, color: _isOnline ? Colors.greenAccent : Colors.redAccent),
            onPressed: _toggleService,
            tooltip: _isOnline ? "Fin de service" : "Prise de service",
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bouton SOS d'urgence
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _sosActive ? Colors.orange[800] : Colors.red[700],
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isOnline ? _toggleSOS : null,
              icon: const Icon(Icons.warning, size: 28, color: Colors.white),
              label: Text(
                _sosActive ? "DÉSACTIVER ALERTE SOS" : "DÉCLENCHER SOS DÉTRESSE",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),

            // Statut et GPS Card
            Card(
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text(
                      _isOnline ? "STATUT : EN LIGNE" : "STATUT : HORS LIGNE",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pos != null 
                        ? "GPS : ${_pos!.latitude.toStringAsFixed(4)}, ${_pos!.longitude.toStringAsFixed(4)}"
                        : "GPS : En attente de prise de service",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Sélecteur de statut opérationnel
            DropdownButtonFormField<String>(
              value: _selectedStatus,
              dropdownColor: Colors.grey[900],
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedStatus = val);
                  _syncData();
                }
              },
            ),
            const SizedBox(height: 10),

            // Bouton Matériel
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _openGearModal,
              icon: const Icon(Icons.backpack, color: Colors.blueAccent),
              label: const Text("Gérer le Matériel Embarqué"),
            ),
            const SizedBox(height: 10),

            // Messagerie CSU Directe
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[800]!),
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
                        stream: _db.child("messages").limitToLast(20).onValue,
                        builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                            return const Center(child: Text("Aucun message", style: TextStyle(color: Colors.grey)));
                          }
                          try {
                            Map map = snapshot.data!.snapshot.value as Map;
                            var entries = map.entries.toList()
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
                                      color: isMe ? Colors.blue[900] : Colors.grey[800],
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text("${msg['sender']}: ${msg['text']}"),
                                  ),
                                );
                              },
                            );
                          } catch (e) {
                            return const Center(child: Text("Erreur de chargement des messages"));
                          }
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgCtrl,
                              decoration: const InputDecoration(
                                hintText: "Écrire au CSU...",
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.blueAccent),
                            onPressed: _sendMessage,
                          )
                        ],
                      ),
                    )
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
