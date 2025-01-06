import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';

class FriendsListScreen extends StatefulWidget {
  @override
  _FriendsListScreenState createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  String? _currentUserId;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _currentUserId = _authService.getCurrentUserId();
    _getCurrentUserEmail();
  }

  Future<void> _getCurrentUserEmail() async {
    final currentUserDoc =
        await _firestore.collection('users').doc(_currentUserId).get();
    setState(() {
      _currentUserEmail = currentUserDoc['email'];
    });
  }

  Future<void> _addFriend(String friendEmail) async {
    if (friendEmail == _currentUserEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('You cannot send a friend request to yourself!')),
      );
      return;
    }

    try {
      final friendQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: friendEmail)
          .get();

      if (friendQuery.docs.isNotEmpty) {
        final friendDoc = friendQuery.docs.first;
        final friendId = friendDoc.id;

        final currentUserDoc =
            await _firestore.collection('users').doc(_currentUserId).get();
        final friends = List<String>.from(currentUserDoc['friends'] ?? []);
        if (friends.contains(friendId)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You are already friends with this user!')),
          );
          return;
        }

        await _firestore.collection('users').doc(_currentUserId).update({
          'friendRequests.sent': FieldValue.arrayUnion([friendId])
        });

        await _firestore.collection('users').doc(friendId).update({
          'friendRequests.received': FieldValue.arrayUnion([_currentUserId])
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Friend request sent!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User not found!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _unfriend(String friendId) async {
    try {
      await _firestore.collection('users').doc(_currentUserId).update({
        'friends': FieldValue.arrayRemove([friendId])
      });

      await _firestore.collection('users').doc(friendId).update({
        'friends': FieldValue.arrayRemove([_currentUserId])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend removed!')),
      );

      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        elevation: 5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(_currentUserId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final userDoc = snapshot.data!;
          final friends = List<String>.from(userDoc['friends'] ?? []);
          final receivedRequests =
              List<String>.from(userDoc['friendRequests']['received'] ?? []);

          return ListView(
            padding: EdgeInsets.all(16.0),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Send Friend Request via Email',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.email),
                  ),
                  onSubmitted: (value) => _addFriend(value),
                ),
              ),
              Divider(),
              ListTile(
                title: Text(
                  'Friends',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ),
              ...friends.map((friendId) {
                return FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('users').doc(friendId).get(),
                  builder: (context, friendSnapshot) {
                    if (!friendSnapshot.hasData) return Container();

                    final friendData = friendSnapshot.data!;
                    return Card(
                      elevation: 2,
                      margin: EdgeInsets.symmetric(vertical: 8.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(16.0),
                        title: Text(friendData['name'] ?? 'Unknown'),
                        subtitle: Text(friendData['email'] ?? 'No Email'),
                        trailing: IconButton(
                          icon: Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () => _unfriend(friendId),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
              Divider(),
              ListTile(
                title: Text(
                  'Friend Requests',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ),
              ...receivedRequests.map((requestId) {
                return FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('users').doc(requestId).get(),
                  builder: (context, requestSnapshot) {
                    if (!requestSnapshot.hasData) return Container();

                    final requestData = requestSnapshot.data!;
                    return Card(
                      elevation: 2,
                      margin: EdgeInsets.symmetric(vertical: 8.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(16.0),
                        title: Text(requestData['name'] ?? 'Unknown'),
                        subtitle: Text(requestData['email'] ?? 'No Email'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.check, color: Colors.green),
                              onPressed: () async {
                                await _firestore
                                    .collection('users')
                                    .doc(_currentUserId)
                                    .update({
                                  'friends': FieldValue.arrayUnion([requestId])
                                });
                                await _firestore
                                    .collection('users')
                                    .doc(requestId)
                                    .update({
                                  'friends':
                                      FieldValue.arrayUnion([_currentUserId])
                                });
                                await _firestore
                                    .collection('users')
                                    .doc(_currentUserId)
                                    .update({
                                  'friendRequests.received':
                                      FieldValue.arrayRemove([requestId])
                                });
                                await _firestore
                                    .collection('users')
                                    .doc(requestId)
                                    .update({
                                  'friendRequests.sent':
                                      FieldValue.arrayRemove([_currentUserId])
                                });
                                setState(() {});
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: Colors.red),
                              onPressed: () async {
                                await _firestore
                                    .collection('users')
                                    .doc(_currentUserId)
                                    .update({
                                  'friendRequests.received':
                                      FieldValue.arrayRemove([requestId])
                                });
                                await _firestore
                                    .collection('users')
                                    .doc(requestId)
                                    .update({
                                  'friendRequests.sent':
                                      FieldValue.arrayRemove([_currentUserId])
                                });
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}
