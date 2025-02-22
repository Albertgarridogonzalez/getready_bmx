import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RecordsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //appBar: AppBar(
      //  title: Row(
      //    mainAxisAlignment: MainAxisAlignment.spaceBetween,
      //    children: [
      //      Text('GetReady BMX'),
      //      Text('Historial'),
      //    ],
      //  ),
      //),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('race_times')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No hay registros disponibles.'));
          }
          return ListView(
            children: snapshot.data!.docs.map((doc) {
              return ListTile(
                title: Text('Piloto: ${doc['userId']}'),
                subtitle: Text('Tiempo: ${doc['time']} segundos'),
                trailing: Text('${(doc['timestamp'] as Timestamp).toDate()}'),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
