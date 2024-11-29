import 'package:flutter/material.dart';
import 'package:xtream_code_client/xtream_code_client.dart';

class VodScreen extends StatelessWidget {
  final XtreamCodeClient client;

  VodScreen({required this.client});

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
