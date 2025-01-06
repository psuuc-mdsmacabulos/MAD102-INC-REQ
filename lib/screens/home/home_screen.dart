import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:inc_req_location_sharing_app/screens/auth/logout_screen.dart';
import 'friend_list_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Position? _currentPosition;
  bool _isSharingLocation = false;
  BitmapDescriptor? _userIcon;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _fetchFriendsLocations();
    _loadLocationSharingStatus();
    _loadIcons();
  }

  Future<void> _loadIcons() async {
    _userIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    setState(() {});
  }

  Future<void> _loadLocationSharingStatus() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('User is not authenticated');
        return;
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      bool locationSharing = userDoc['locationSharing'] ?? false;

      setState(() {
        _isSharingLocation = locationSharing;
      });

      if (_isSharingLocation && _currentPosition != null) {
        _addMarker(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          'My Location',
          'This is your current location.',
          _userIcon!,
        );
      }
    } catch (e) {
      print('Error loading location sharing status: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied.');
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;
    });

    if (_mapController != null && _currentPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
      );
    }

    if (_isSharingLocation) {
      _addMarker(
        LatLng(position.latitude, position.longitude),
        'My Location',
        'This is your current location.',
        _userIcon!,
      );
      _updateLocationInFirestore(position.latitude, position.longitude);
    }
  }

  Future<void> _fetchFriendsLocations() async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    User? user = FirebaseAuth.instance.currentUser;

    try {
      QuerySnapshot snapshot = await firestore.collection('users').get();

      for (var doc in snapshot.docs) {
        if (doc.id == user?.uid) {
          continue;
        }

        if (doc['locationSharing'] == true && doc['location'] != null) {
          GeoPoint location = doc['location'];
          String friendName = doc['name'] ?? 'Friend';

          int hash = friendName.hashCode;
          double hue = (hash % 360).toDouble();

          BitmapDescriptor friendIcon =
              BitmapDescriptor.defaultMarkerWithHue(hue);

          LatLng friendLocation = LatLng(location.latitude, location.longitude);

          _addMarker(
            friendLocation,
            friendName,
            '$friendName\'s location',
            friendIcon,
          );
        }
      }
    } catch (e) {
      print('Error fetching friends\' locations: $e');
    }
  }

  void _addMarker(
      LatLng position, String markerId, String snippet, BitmapDescriptor icon) {
    setState(() {
      _markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: position,
          infoWindow: InfoWindow(
            title: markerId,
            snippet: snippet,
            onTap: () {
              _showCustomInfoWindow(markerId, snippet);
            },
          ),
          icon: icon,
        ),
      );
    });
  }

  void _toggleLocationSharing() {
    setState(() {
      _isSharingLocation = !_isSharingLocation;
      if (_isSharingLocation && _currentPosition != null) {
        _addMarker(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          'My Location',
          'This is your current location.',
          _userIcon!,
        );
        _updateLocationInFirestore(
            _currentPosition!.latitude, _currentPosition!.longitude);
      } else {
        _markers
            .removeWhere((marker) => marker.markerId.value == 'My Location');
        _removeLocationFromFirestore();
      }
    });
  }

  Future<void> _updateLocationInFirestore(
      double latitude, double longitude) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('User is not authenticated');
        return;
      }
      String userId = user.uid;

      GeoPoint geoPoint = GeoPoint(latitude, longitude);

      DocumentReference userDocRef =
          FirebaseFirestore.instance.collection('users').doc(userId);

      await userDocRef.update({
        'location': geoPoint,
        'locationSharing': _isSharingLocation,
      });
    } catch (e) {
      print('Error updating location in Firestore: $e');
    }
  }

  Future<void> _removeLocationFromFirestore() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('User is not authenticated');
        return;
      }
      String userId = user.uid;

      DocumentReference userDocRef =
          FirebaseFirestore.instance.collection('users').doc(userId);

      await userDocRef.update({
        'location': FieldValue.delete(),
        'locationSharing': false,
      });
    } catch (e) {
      print('Error removing location from Firestore: $e');
    }
  }

  void _showCustomInfoWindow(String title, String snippet) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Text(snippet),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close', style: TextStyle(color: Colors.teal)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        elevation: 5,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LogoutScreen(),
                ),
              );
            },
          ),
          Switch(
            value: _isSharingLocation,
            onChanged: (value) => _toggleLocationSharing(),
            activeColor: Colors.green,
            inactiveThumbColor: Colors.red,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude)
                  : LatLng(0.0, 0.0),
              zoom: 14.0,
            ),
            markers: _markers,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FriendsListScreen(),
                  ),
                );
              },
              child: Text('Friends List',
                  style: TextStyle(fontSize: 16, color: Colors.black)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
