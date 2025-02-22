// screens/leaderboard_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //appBar: AppBar(
      //  title: Row(
      //    mainAxisAlignment: MainAxisAlignment.spaceBetween,
      //    children: [
      //      Text('GetReady BMX'),
      //      Text('Leaderboard'),
      //    ],
      //  ),
      //),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('race_times')
            .orderBy('time', descending: false)
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No hay tiempos registrados.'));
          }
          return ListView(
            children: snapshot.data!.docs.map((doc) {
              return ListTile(
                title: Text(doc['userId']),
                subtitle: Text('Tiempo: ${doc['time']} segundos'),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}