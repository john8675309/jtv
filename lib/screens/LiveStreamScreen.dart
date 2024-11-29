// Example: LiveStreamScreen.dart
import 'package:flutter/material.dart';
import 'package:xtream_code_client/xtream_code_client.dart';

class LiveStreamScreen extends StatelessWidget {
  final XtreamCodeClient client;
  //final Box<XTremeCodeChannelEpgListing> epgBox;

  LiveStreamScreen({required this.client});

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
