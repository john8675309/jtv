import 'package:flutter/material.dart';
import 'package:xtream_code_client/xtream_code_client.dart';

class SeriesScreen extends StatelessWidget {
  final XtreamCodeClient client;

  SeriesScreen({required this.client});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Stream'),
      ),
      body: Center(
        child: Text('Welcome to Live Stream!'),
      ),
    );
  }
}
