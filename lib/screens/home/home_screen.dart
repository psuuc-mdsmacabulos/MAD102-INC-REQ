import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:inc_req_location_sharing_app/screens/auth/logout_screen.dart';
import 'friend_list_screen.dart';
import 'dart:async';

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
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<QuerySnapshot>? _friendsLocationStream;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _startListeningToFriendsLocations();
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

  void _startListeningToUserLocation() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen((Position position) {
      if (_isSharingLocation) {
        if (_currentPosition != null) {
          double distance = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          if (distance < 1.0) {
            return;
          }
        }

        setState(() {
          _currentPosition = position;
        });

        Marker updatedMarker = Marker(
          markerId: const MarkerId('My Location'),
          position: LatLng(position.latitude, position.longitude),
          infoWindow: const InfoWindow(
            title: 'My Location',
            snippet: 'This is your current location.',
          ),
          icon: _userIcon!,
        );

        setState(() {
          _markers
              .removeWhere((marker) => marker.markerId.value == 'My Location');
          _markers.add(updatedMarker);
        });

        _updateLocationInFirestore(position.latitude, position.longitude);
      }
    });
  }

  void _startListeningToFriendsLocations() {
    _friendsLocationStream = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      Set<Marker> updatedMarkers = {};

      for (var doc in snapshot.docs) {
        if (doc.id == FirebaseAuth.instance.currentUser?.uid) continue;

        if (doc['locationSharing'] == true && doc['location'] != null) {
          GeoPoint location = doc['location'];
          String friendName = doc['name'] ?? 'Friend';

          int hash = friendName.hashCode;
          double hue = (hash % 360).toDouble();

          BitmapDescriptor friendIcon =
              BitmapDescriptor.defaultMarkerWithHue(hue);

          LatLng friendLocation = LatLng(location.latitude, location.longitude);

          updatedMarkers.add(
            Marker(
              markerId: MarkerId(friendName),
              position: friendLocation,
              infoWindow: InfoWindow(
                title: friendName,
                snippet: '$friendName\'s location',
              ),
              icon: friendIcon,
            ),
          );
        }
      }

      if (_isSharingLocation && _currentPosition != null) {
        updatedMarkers.add(
          Marker(
            markerId: const MarkerId('My Location'),
            position: LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            infoWindow: const InfoWindow(
              title: 'My Location',
              snippet: 'This is your current location.',
            ),
            icon: _userIcon!,
          ),
        );
      }

      setState(() {
        _markers = updatedMarkers;
      });
    });
  }

  void _addMarker(
      LatLng position, String markerId, String snippet, BitmapDescriptor icon) {
    setState(() {
      print(
          'Adding marker: $markerId at ${position.latitude}, ${position.longitude}');
      _markers.removeWhere((marker) => marker.markerId.value == markerId);

      _markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: position,
          infoWindow: InfoWindow(
            title: markerId,
            snippet: snippet,
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
        print('Location sharing enabled. Adding marker.');

        _addMarker(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          'My Location',
          'This is your current location.',
          _userIcon!,
        );

        _startListeningToUserLocation();
        _updateLocationInFirestore(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      } else {
        print('Location sharing disabled. Removing marker.');

        _positionStream?.cancel();
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

      print(
          'Updating Firestore: location = $latitude, $longitude, sharing = $_isSharingLocation');

      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'location': geoPoint,
        'locationSharing': _isSharingLocation,
      }, SetOptions(merge: true));
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

  @override
  void dispose() {
    _positionStream?.cancel();
    _friendsLocationStream?.cancel();
    super.dispose();
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
