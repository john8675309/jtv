import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:jtv/epg_models.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart'; // Provides [Player], [Media], [Playlist] etc.
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jtv/screens/SearchDialog.dart';
import 'package:jtv/screens/VodScreen.dart';
import 'package:jtv/screens/PickerScreen.dart';

class VodScreen extends StatefulWidget {
  final dynamic client;

  const VodScreen({
    super.key,
    required this.client,
  });

  @override
  State<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  bool _isLoading = true;
  List<dynamic> _vodContent = [];
  String _error = '';

  int selectedRow = 0;
  int selectedCol = 0;

  final focusNode = FocusNode(); // Declare FocusNode here

  @override
  void initState() {
    super.initState();
    _loadVodContent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!focusNode.hasFocus) {
        focusNode.requestFocus(); // Request focus when widget builds
      }
    });
  }

  @override
  void dispose() {
    focusNode.dispose(); // Dispose FocusNode when no longer needed
    super.dispose();
  }

  Future<void> _loadVodContent() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      await Future.delayed(Duration(seconds: 2)); // Simulate loading
      setState(() {
        _vodContent = List.generate(
          20,
          (index) => {
            "name": "VOD Item $index",
            "streamIcon": "https://via.placeholder.com/150",
            "rating": math.Random().nextInt(5) + 1,
          },
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load VOD content: $e';
        _isLoading = false;
      });
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    print(event);
    if (event is KeyDownEvent) {
      setState(() {
        switch (event.physicalKey.usbHidUsage) {
          case 458831: // Right
            if (selectedCol < 1) selectedCol++;
            break;
          case 458832: // Left
            if (selectedCol > 0) selectedCol--;
            break;
          case 458833: // Down
            if (selectedRow < 1) selectedRow++;
            break;
          case 458834: // Up
            if (selectedRow > 0) selectedRow--;
            break;
          case 786979: // Enter key
            _showSectionMenu().then((section) {});
            break;
          case 786980: // Escape/Back
            Navigator.of(context).pop();
            break;
        }
      });
    }
  }

  Future<void> _showSectionMenu() async {
    final section = await showDialog<ViewSection>(
      context: context,
      builder: (_) => _SectionMenuDialog(client: widget.client),
    );

    if (section != null) {
      // Handle the returned section here
      print('Selected Section: $section');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          focusNode.requestFocus(); // Request focus on tap
        },
        child: KeyboardListener(
          focusNode: focusNode, // Apply FocusNode directly to KeyboardListener
          onKeyEvent: _handleKeyEvent, // Handle key events here
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? Center(
                      child: Text(
                        _error,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 2 / 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _vodContent.length,
                      itemBuilder: (context, index) {
                        final item = _vodContent[index];
                        return Card(
                          color: Colors.grey.shade900,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    image: DecorationImage(
                                      image: NetworkImage(
                                          item['streamIcon'] ?? ''),
                                      fit: BoxFit.cover,
                                      onError: (_, __) =>
                                          print('Failed to load image'),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    if (item['rating'] != null)
                                      Text(
                                        'Rating: ${item['rating']}',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 14,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

enum ViewSection { all, favorites, vod, series }

class _SectionMenuDialog extends StatefulWidget {
  final dynamic client;

  const _SectionMenuDialog({required this.client, Key? key}) : super(key: key);

  @override
  State<_SectionMenuDialog> createState() => _SectionMenuDialogState();
}

class _SectionMenuDialogState extends State<_SectionMenuDialog> {
  int selectedRow = 0;
  int selectedCol = 0;
  late FocusNode
      dialogFocusNode; // Declare a dedicated FocusNode for the dialog

  @override
  void initState() {
    super.initState();
    dialogFocusNode = FocusNode(); // Initialize the FocusNode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dialogFocusNode.requestFocus(); // Request focus after the widget is built
    });
  }

  @override
  void dispose() {
    dialogFocusNode
        .dispose(); // Dispose the FocusNode when the dialog is closed
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      setState(() {
        switch (event.physicalKey.usbHidUsage) {
          case 458831: // Right
            if (selectedCol < 1) selectedCol++;
            break;
          case 458832: // Left
            if (selectedCol > 0) selectedCol--;
            break;
          case 458833: // Down
            if (selectedRow < 1) selectedRow++;
            break;
          case 458834: // Up
            if (selectedRow > 0) selectedRow--;
            break;
          case 786979: // Enter key
            Navigator.of(context).pop(ViewSection.all); // Return a value
            break;
          case 786980: // Escape/Back
            Navigator.of(context).pop(); // Close the dialog
            break;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: dialogFocusNode,
      child: KeyboardListener(
        focusNode: dialogFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 400,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSectionButton("All", Icons.grid_view_rounded,
                    selectedRow == 0 && selectedCol == 0),
                _buildSectionButton("Favorites", Icons.star_rounded,
                    selectedRow == 0 && selectedCol == 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionButton(String label, IconData icon, bool isSelected) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey,
      ),
      onPressed: () => Navigator.of(context).pop(), // Return or perform actions
      icon: Icon(icon, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
