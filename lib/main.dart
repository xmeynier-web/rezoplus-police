Future<void> _initLocationAndSync() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Vérifier si le service de localisation du téléphone est activé
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur : Activez le GPS dans les paramètres du téléphone !', style: TextStyle(color: Colors.red))),
      );
      return;
    }

    // 2. Vérifier les permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission de localisation refusée.', style: TextStyle(color: Colors.red))),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Localisation bloquée définitivement. Allez dans les paramètres Android de l\'app.', style: TextStyle(color: Colors.red))),
      );
      return;
    }

    // 3. Lancer la boucle de suivi GPS si tout est OK
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 3),
        );
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        _updateFirebaseData();
      } catch (e) {
        // En cas de délai dépassé, on retente au cycle suivant
      }
    });
  }
