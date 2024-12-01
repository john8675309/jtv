import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:jtv/epg_models.dart';
import 'package:flutter/services.dart';
import 'package:jtv/screens/SearchDialog.dart';
import 'package:jtv/screens/VodScreen.dart';
import 'package:jtv/screens/FavoritesScreen.dart';
import 'package:video_player/video_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PickerScreen extends StatefulWidget {
  final dynamic client;

  const PickerScreen({super.key, required this.client});

  @override
  // ignore: library_private_types_in_public_api
  _PickerScreenState createState() => _PickerScreenState();
}

class _PickerScreenState extends State<PickerScreen> {
  late final player;
  late final controller;
  final ScrollController _timelineController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final List<ScrollController> _programControllers = [];
  bool isLoading = false;
  final double timeSlotWidth = 200.0;
  final double channelLogoWidth = 80.0;
  final double rowHeight = 60.0;
  String? hoveredChannelName;
  EPGProgram? hoveredProgram;
  int selectedChannelIndex = 0;
  int selectedProgramIndex = 0;
  // ignore: prefer_final_fields
  bool _isScrolling = false;
  bool _isFullScreen = false;
  Timer? _longPressTimer;
  bool _isLongPress = false;
  final FocusNode _mainFocusNode = FocusNode();

  bool _shouldAutoPlay = false;
  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    player = Player(
      configuration: const PlayerConfiguration(
        vo: 'gpu', // Use GPU rendering
        osc: false, // Disable on-screen controls
        muted: true, // Mute audio
        logLevel: MPVLogLevel.trace, // Enable detailed logging
        bufferSize: 64 * 1024 * 1024, // Increase buffer size to 64 MB
        protocolWhitelist: [
          'udp',
          'rtp',
          'tcp',
          'tls',
          'data',
          'file',
          'http',
          'https',
          'crypto'
        ], // Allow necessary protocols
      ),
    );
    print(player.stream.log);
    controller = VideoController(player);
    _initializeData();
    _timelineController.addListener(_synchronizeScroll);
  }

  @override
  void dispose() {
    _timelineController.removeListener(_synchronizeScroll);
    _timelineController.dispose();
    _verticalController.dispose();
    for (var controller in _programControllers) {
      controller.dispose();
    }
    _mainFocusNode.dispose();

    // Stop playback and dispose of player
    player?.dispose();
    super.dispose();
  }

  void _synchronizeScroll() {
    for (var controller in _programControllers) {
      if (controller.hasClients &&
          controller.offset != _timelineController.offset) {
        controller.jumpTo(_timelineController.offset);
      }
    }
  }

  Future<void> _initializeData() async {
    setState(() => isLoading = true);
    try {
      await Hive.openBox<EPGChannel>('epg_channels');
      await Hive.openBox<EPGProgram>('epg_programs');
      await Hive.openBox<FavoriteChannel>('favorites');
      if (Hive.box<EPGChannel>('epg_channels').isEmpty) {
        await _refreshEPGData();
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _refreshEPGData() async {
    print("Starting EPG Refresh");
    try {
      final epgResponse = await widget.client.epg();
      final liveStreams = await widget.client.livestreamItems();

      // Create mapping of EPG channel IDs to stream IDs
      final streamMapping = <String, int>{};
      for (var stream in liveStreams) {
        if (stream.epgChannelId != null && stream.streamId != null) {
          streamMapping[stream.epgChannelId!] = stream.streamId!;
        }
      }

      final channelsBox = Hive.box<EPGChannel>('epg_channels');
      final programsBox = Hive.box<EPGProgram>('epg_programs');

      await channelsBox.clear();
      await programsBox.clear();

      // Get today's date for filtering
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(Duration(days: 1));

      // Process channels and programs
      for (var xmlChannel in epgResponse.channels) {
        // Get the stream ID if it exists
        final streamId = streamMapping[xmlChannel.id];

        try {
          // Filter programs for this channel
          final channelPrograms = epgResponse.programmes
              .where((p) => p.channel == xmlChannel.id)
              .where((p) {
            final programDate = p.start.toLocal();
            return programDate.isAfter(today) && programDate.isBefore(tomorrow);
          }).toList();

          if (channelPrograms.isEmpty) {
            continue;
          }

          final programIds = <int>[];

          // Add programs for this channel
          for (var xmlProgram in channelPrograms) {
            try {
              // Convert program times from UTC to local timezone
              final startLocal = xmlProgram.start.toLocal();
              final stopLocal = xmlProgram.stop?.toLocal();

              // Only process programs for today
              if (startLocal.year == today.year &&
                  startLocal.month == today.month &&
                  startLocal.day == today.day) {
                // Safely convert lists to List<String>
                final categories = xmlProgram.categories
                    .map((c) => c.value.toString())
                    .toList()
                    .cast<String>();

                final episodeNums = xmlProgram.episodeNums
                    .map((e) => e.value.toString())
                    .toList()
                    .cast<String>();

                final program = EPGProgram(
                  title: xmlProgram.titles.isNotEmpty
                      ? xmlProgram.titles.first.value.toString()
                      : 'Unknown',
                  start: startLocal,
                  stop: stopLocal,
                  channelId: xmlChannel.id,
                  description: xmlProgram.descs.isNotEmpty
                      ? xmlProgram.descs.first.value.toString()
                      : null,
                  categories: categories,
                  episodeNumbers: episodeNums,
                  isNew: xmlProgram.isNew,
                );

                final programId = await programsBox.add(program);
                programIds.add(programId);
              }
            } catch (e) {
              print('Error processing program: $e');
              continue;
            }
          }

          if (programIds.isNotEmpty) {
            // Safely convert display names to List<String>
            final displayNames = xmlChannel.displayNames
                .map((d) => d.value.toString())
                .toList()
                .cast<String>();

            final channel = EPGChannel(
              id: xmlChannel.id,
              name:
                  displayNames.isNotEmpty ? displayNames.first : xmlChannel.id,
              iconUrl: xmlChannel.icons.isNotEmpty
                  ? xmlChannel.icons.first.src
                  : null,
              displayNames: displayNames,
              programIds: programIds,
              streamId: streamId,
            );

            await channelsBox.add(channel);
          }
        } catch (e) {
          print('Error processing channel: $e');
          continue;
        }
      }
    } catch (e) {
      print('Error refreshing EPG: $e');
      rethrow;
    }
    print("Finished EPG Refresh");
  }

/*
  Future<void> _refreshEPGData() async {
    print("Starting EPG Refresh");
    try {
      final epgResponse = await widget.client.epg();
      final liveStreams = await widget.client.livestreamItems();

      // Create mapping of EPG channel IDs to stream IDs
      final streamMapping = <String, int>{};
      for (var stream in liveStreams) {
        if (stream.epgChannelId != null && stream.streamId != null) {
          streamMapping[stream.epgChannelId!] = stream.streamId!;
        }
      }

      final channelsBox = Hive.box<EPGChannel>('epg_channels');
      final programsBox = Hive.box<EPGProgram>('epg_programs');

      await channelsBox.clear();
      await programsBox.clear();
      
      // Process channels and programs
      for (var xmlChannel in epgResponse.channels) {
        // Get the stream ID if it exists
        final streamId = streamMapping[xmlChannel.id];
        if (streamId != null) {}

        try {
          final channelPrograms = epgResponse.programmes
              .where((p) => p.channel == xmlChannel.id)
              .toList();

          if (channelPrograms.isEmpty) {
            continue;
          }

          final programIds = <int>[];

          // Add programs for this channel
          for (var xmlProgram in channelPrograms) {
            try {
              // Convert program times from UTC to local timezone
              final startLocal = xmlProgram.start.toLocal();
              final stopLocal = xmlProgram.stop?.toLocal();

              // Safely convert lists to List<String>
              final categories = xmlProgram.categories
                  .map((c) => c.value.toString())
                  .toList()
                  .cast<String>();

              final episodeNums = xmlProgram.episodeNums
                  .map((e) => e.value.toString())
                  .toList()
                  .cast<String>();

              final program = EPGProgram(
                title: xmlProgram.titles.isNotEmpty
                    ? xmlProgram.titles.first.value.toString()
                    : 'Unknown',
                start: startLocal, // Use local time
                stop: stopLocal, // Use local time
                channelId: xmlChannel.id,
                description: xmlProgram.descs.isNotEmpty
                    ? xmlProgram.descs.first.value.toString()
                    : null,
                categories: categories,
                episodeNumbers: episodeNums,
                isNew: xmlProgram.isNew,
              );

              final programId = await programsBox.add(program);
              programIds.add(programId);
            } catch (e) {
              continue;
            }
          }

          if (programIds.isNotEmpty) {
            // Safely convert display names to List<String>
            final displayNames = xmlChannel.displayNames
                .map((d) => d.value.toString())
                .toList()
                .cast<String>();

            final channel = EPGChannel(
              id: xmlChannel.id,
              name:
                  displayNames.isNotEmpty ? displayNames.first : xmlChannel.id,
              iconUrl: xmlChannel.icons.isNotEmpty
                  ? xmlChannel.icons.first.src
                  : null,
              displayNames: displayNames,
              programIds: programIds,
              streamId: streamId, // Add the numeric stream ID
            );

            await channelsBox.add(channel);
          }
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      rethrow;
    }
    print("Finished EPG Refresh");
  }
*/
  Widget _buildVideoPreview() {
    if (player.state.playing == false) {
      return const SizedBox.shrink();
    }

    if (_isFullScreen) {
      return Positioned.fill(
        child: Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(
              controller: controller,
            ),
          ),
        ),
      );
    } else {
      return Positioned(
        top: 16,
        right: 16,
        width: 240, // Increased width to prevent overflow
        height: 135, // Maintain 16:9 aspect ratio
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            // Add ClipRRect to prevent overflow
            borderRadius: BorderRadius.circular(6),
            child: Video(controller: controller),
          ),
        ),
      );
    }
  }

  void _showProgramInfo() {
    if (!_shouldAutoPlay) {
      _shouldAutoPlay = true;
      return;
    }
    if (_isFullScreen) {
      // Exit full-screen mode
      setState(() {
        _isFullScreen = false;
      });
      return;
    }

    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final programsBox = Hive.box<EPGProgram>('epg_programs');
    String baseUrl = "";
    final channel = channelsBox.getAt(selectedChannelIndex);
    if (channel != null && channel.programIds.isNotEmpty) {
      final program = programsBox.get(channel.programIds[selectedProgramIndex]);
      if (program != null) {
        //print('\nProgram Information:');
        //print('Channel: ${channel.name}');
        //print('EPG Channel ID: ${channel.id}');

        if (channel.streamId != null) {
          //print('\nStream URLs:');
          try {
            final url = widget.client.streamUrl(channel.streamId!, ["ts"]);
            // Just use the base URL without extension
            //print(url);
            baseUrl = url.substring(0, url.lastIndexOf('.ts'));
            //print('Stream URL: $baseUrl');
          } catch (e) {
            //print('Error getting stream URL: $e');
          }
        } else {
          //print('\nNo stream ID available for this channel');
        }
      }

      if (baseUrl.isNotEmpty) {
        try {
          // No need to dispose of the player, MediaKit handles this
          player.open(Media(baseUrl));
        } catch (e) {
          print('Error initializing video: $e');
        }
      }

      // Enter full-screen mode
      setState(() {
        _isFullScreen = true;
      });
    }
  }

  Future<bool> _showAddToFavoritesDialog(
      BuildContext context, EPGChannel? channel) async {
    if (channel == null) return false;

    final favoritesBox = Hive.box<FavoriteChannel>('favorites');
    final isAlreadyFavorite =
        favoritesBox.values.any((fav) => fav.id == channel.id);

    if (isAlreadyFavorite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${channel.name} is already in favorites'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: Text(
          'Add to Favorites',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Would you like to add "${channel.name}" to your favorites?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Yes', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );

    if (result == true) {
      await _addToFavorites(channel);
    }

    return result ?? false;
  }

  Future<void> _addToFavorites(EPGChannel channel) async {
    if (channel.streamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot add channel without stream ID to favorites'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final favoritesBox = Hive.box<FavoriteChannel>('favorites');

    final favorite = FavoriteChannel(
      id: channel.id,
      name: channel.name,
      iconUrl: channel.iconUrl,
      streamId: channel.streamId!,
    );

    await favoritesBox.add(favorite);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${channel.name} added to favorites'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleLongPress() {
    _isLongPress = true;
    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final channel = channelsBox.getAt(selectedChannelIndex);
    if (channel != null) {
      _showAddToFavoritesDialog(context, channel);
    }
  }

  void _handleSearch() async {
    try {
      final result = await showDialog<SearchResult>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (BuildContext context) => SearchDialog(
          channelsBox: Hive.box<EPGChannel>('epg_channels'),
          programsBox: Hive.box<EPGProgram>('epg_programs'),
        ),
      );

      if (!mounted) return;

      // Request focus back to main screen
      _mainFocusNode.requestFocus();

      if (result != null) {
        final channelsBox = Hive.box<EPGChannel>('epg_channels');
        final programsBox = Hive.box<EPGProgram>('epg_programs');
        final channels = channelsBox.values.toList();

        print('Received in PickerScreen:');
        print('  Type: ${result.type}');
        print('  Channel ID: ${result.channelId}');
        print('  Program ID: ${result.programId}');
        print('  Stream ID: ${result.streamId}');
        print('  Title: ${result.title}');
        print('  Subtitle: ${result.subtitle}');

        final channelIndex =
            channels.indexWhere((c) => c.id == result.channelId);
        print('Found channel index: $channelIndex');

        if (channelIndex != -1 && mounted) {
          final channel = channels[channelIndex];
          print('Channel details:');
          print('  ID: ${channel.id}');
          print('  Name: ${channel.name}');
          print('  Stream ID: ${channel.streamId}');
          print('  Number of programs: ${channel.programIds.length}');

          // Calculate scroll positions
          final selectedPosition = channelIndex * rowHeight;
          final viewportHeight = _verticalController.position.viewportDimension;

          // Scroll to show the channel
          _verticalController.jumpTo(
            (selectedPosition - (viewportHeight / 2) + (rowHeight / 2)).clamp(
              0.0,
              _verticalController.position.maxScrollExtent,
            ),
          );

          // If it's a program, find the specific program and scroll horizontally
          if (result.type == 'program' && result.programId != null) {
            final programIndex = channel.programIds.indexOf(result.programId!);
            if (programIndex != -1) {
              double horizontalOffset = 0.0;

              for (int i = 0; i < programIndex; i++) {
                final program = programsBox.get(channel.programIds[i]);
                if (program != null && program.stop != null) {
                  final duration = program.stop!.difference(program.start);
                  horizontalOffset += (duration.inMinutes / 30) * timeSlotWidth;
                }
              }

              _timelineController.jumpTo(horizontalOffset.clamp(
                0.0,
                _timelineController.position.maxScrollExtent,
              ));

              // Sync program rows
              for (var controller in _programControllers) {
                if (controller.hasClients) {
                  controller.jumpTo(horizontalOffset.clamp(
                    0.0,
                    controller.position.maxScrollExtent,
                  ));
                }
              }
            }
          }

          // Add a small delay to ensure the UI has updated before changing selection
          Future.microtask(() {
            if (mounted) {
              setState(() {
                selectedChannelIndex = channelIndex;
                if (result.type == 'program' && result.programId != null) {
                  selectedProgramIndex =
                      channel.programIds.indexOf(result.programId!);
                } else {
                  selectedProgramIndex = 0;
                }
              });
            }
          });
        }
      }
    } catch (e) {
      print('Error in search handler: $e');
    }
  }

  Future<ViewSection?> _showSectionMenu() {
    return showDialog<ViewSection>(
      context: context,
      builder: (BuildContext context) => _SectionMenuDialog(),
    );
  }

  Widget _buildSectionButton(
    ViewSection section,
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onStateChange,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade700 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade700,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop(section);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (_) => _handleSearch(),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (KeyEvent event) {
          print(
              "Key pressed: ${event.logicalKey.keyId}, physical: ${event.physicalKey.usbHidUsage}");
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter) {
            _longPressTimer?.cancel();
            _longPressTimer = Timer(const Duration(seconds: 1), () {
              _handleLongPress();
            });
          } else if (event is KeyUpEvent &&
              event.logicalKey == LogicalKeyboardKey.enter) {
            _longPressTimer?.cancel();
            if (!_isLongPress) {
              _showProgramInfo(); // Normal press behavior
            }
            _isLongPress = false;
          }
          if (event.physicalKey.usbHidUsage == 458853) {
            _handleSearch();
          }
          if (event.physicalKey.usbHidUsage == 786979) {
            if (event.runtimeType.toString() == "KeyDownEvent") {
              _showSectionMenu().then((section) {
                if (section != null) {
                  // Handle section change
                  print('Selected section: $section');
                  switch (section) {
                    case ViewSection.all:
                      // Handle all channels view
                      break;
                    case ViewSection.favorites:
                      if (player.state.playing) {
                        player.stop();
                      }
                      // Handle favorites view
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              FavoritesScreen(client: widget.client),
                        ),
                      );
                      break;
                    case ViewSection.vod:
                      if (player.state.playing) {
                        player.stop();
                      }

                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              VodScreen(client: widget.client),
                        ),
                      );

                      break;
                    case ViewSection.series:
                      // Handle series view
                      break;
                  }
                }
              });
            }
          }
        },
        child: FocusableActionDetector(
          autofocus: true,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyR, control: true):
                RefreshIntent(),
            SingleActivator(LogicalKeyboardKey.f5): RefreshIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): NavigateIntent('up'),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                NavigateIntent('down'),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                NavigateIntent('left'),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                NavigateIntent('right'),
          },
          actions: {
            RefreshIntent: CallbackAction<RefreshIntent>(
              onInvoke: (_) {
                if (!isLoading) {
                  _refreshEPGData();
                }
                return null;
              },
            ),
            NavigateIntent: CallbackAction<NavigateIntent>(
              onInvoke: (intent) => _handleNavigation(intent.direction),
            ),
            ShowInfoIntent: CallbackAction<ShowInfoIntent>(
              onInvoke: (_) => _showProgramInfo(),
            ),
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  Column(
                    children: [
                      _buildTimeHeader(),
                      Expanded(child: _buildProgramGuide()),
                    ],
                  ),
                _buildVideoPreview(), // Video preview overlay
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleNavigation(String direction) {
    if (_isFullScreen) {
      setState(() {
        _isFullScreen = false;
      });
      return;
    }

    if (_isScrolling) return;

    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final currentChannel = channelsBox.getAt(selectedChannelIndex);
    final programsBox = Hive.box<EPGProgram>('epg_programs');
    setState(() {
      _isFullScreen = false;
      switch (direction) {
        case 'up':
          if (selectedChannelIndex > 0) {
            selectedChannelIndex--;
            final newChannel = channelsBox.getAt(selectedChannelIndex);
            selectedProgramIndex = selectedProgramIndex.clamp(
                0, (newChannel?.programIds.length ?? 1) - 1);

            // Ensure selection is visible
            final selectedPosition = selectedChannelIndex * rowHeight;

            // If selection would be outside visible area, scroll to show it
            if (selectedPosition < _verticalController.offset) {
              _verticalController.jumpTo(
                math.max(selectedPosition, 0.0), // Don't scroll past the top
              );
            }
          }
          break;

        case 'down':
          if (selectedChannelIndex < channelsBox.length - 1) {
            selectedChannelIndex++;
            final newChannel = channelsBox.getAt(selectedChannelIndex);
            selectedProgramIndex = selectedProgramIndex.clamp(
                0, (newChannel?.programIds.length ?? 1) - 1);

            // Ensure selection is visible
            final viewportHeight =
                _verticalController.position.viewportDimension;
            final selectedPosition = selectedChannelIndex * rowHeight;
            if (selectedPosition >
                _verticalController.offset + viewportHeight - rowHeight * 2) {
              _verticalController.jumpTo(
                (selectedPosition - viewportHeight + rowHeight * 2).clamp(
                  0.0,
                  _verticalController.position.maxScrollExtent,
                ),
              );
            }
          }
          break;

        case 'left':
        case 'right':
          if (currentChannel == null) return;

          final newIndex = direction == 'left'
              ? selectedProgramIndex - 1
              : selectedProgramIndex + 1;

          if (newIndex >= 0 && newIndex < currentChannel.programIds.length) {
            selectedProgramIndex = newIndex;

            // Calculate scroll position based on program widths
            double offset = 0;
            for (int i = 0; i < selectedProgramIndex; i++) {
              final p = programsBox.get(currentChannel.programIds[i]);
              if (p != null) {
                final duration =
                    p.stop?.difference(p.start) ?? const Duration(minutes: 30);
                offset += (duration.inMinutes / 30) * timeSlotWidth;
              }
            }

            // Jump to position for immediate response
            _timelineController.jumpTo(offset.clamp(
              0.0,
              _timelineController.position.maxScrollExtent,
            ));

            // Sync all program rows
            for (var controller in _programControllers) {
              if (controller.hasClients) {
                controller.jumpTo(offset.clamp(
                  0.0,
                  controller.position.maxScrollExtent,
                ));
              }
            }
          }
          break;
      }

      // Update header info
      final channel = channelsBox.getAt(selectedChannelIndex);
      if (channel != null) {
        hoveredChannelName = channel.name;
        if (channel.programIds.isNotEmpty) {
          hoveredProgram =
              programsBox.get(channel.programIds[selectedProgramIndex]);
        }
      }
    });
  }

  Widget _buildTimeHeader() {
    // Get current time slots
    final now = DateTime.now();
    final timelineStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 30) * 30,
    );

    List<DateTime> timeSlots = [];
    var currentTime = timelineStart;
    for (int i = 0; i < 12; i++) {
      timeSlots.add(currentTime);
      currentTime = currentTime.add(const Duration(minutes: 30));
    }

    // Get current channel and program info from the visible grid
    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final programsBox = Hive.box<EPGProgram>('epg_programs');

    // Get all channels
    final channels = channelsBox.values.toList();

    // Get selected channel and program
    final selectedChannel =
        channels.isEmpty ? null : channels[selectedChannelIndex];
    EPGProgram? selectedProgram;

    if (selectedChannel != null && selectedChannel.programIds.isNotEmpty) {
      // Get programs for the selected channel
      final programs = selectedChannel.programIds
          .map((id) => programsBox.get(id))
          .where((program) => program != null)
          .toList()
          .cast<EPGProgram>();

      // Filter programs to get the currently selected one based on visible grid
      final visiblePrograms = _filterRelevantPrograms(
          programs, timelineStart, timelineStart.add(const Duration(hours: 6)));

      if (selectedProgramIndex < visiblePrograms.length) {
        selectedProgram = visiblePrograms[selectedProgramIndex];
        print("Selected program in header: ${selectedProgram.title}");
        print(
            "Time in header: ${selectedProgram.start} - ${selectedProgram.stop}");
      }
    }

    return Column(
      children: [
        // Program info header
        if (selectedChannel != null && selectedProgram != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      selectedChannel.name,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      selectedProgram.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (selectedProgram.description != null)
                  Text(
                    selectedProgram.description!,
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${DateFormat('h:mm a').format(selectedProgram.start.toLocal())} - ${DateFormat('h:mm a').format((selectedProgram.stop ?? selectedProgram.start.add(const Duration(minutes: 30))).toLocal())}',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                    if (selectedProgram.categories.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      Text(
                        selectedProgram.categories.join(', '),
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

        // Time slots header
        SizedBox(
          height: 50,
          child: Row(
            children: [
              Container(width: channelLogoWidth, color: Colors.black),
              Expanded(
                child: ListView.builder(
                  controller: _timelineController,
                  scrollDirection: Axis.horizontal,
                  itemCount: timeSlots.length,
                  itemBuilder: (context, index) {
                    final slotTime = timeSlots[index];
                    final bool isHourMark = slotTime.minute == 0;
                    return Container(
                      width: timeSlotWidth,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border(
                          left: BorderSide(color: Colors.grey.shade800),
                          bottom: BorderSide(color: Colors.grey.shade800),
                        ),
                      ),
                      child: Text(
                        DateFormat(isHourMark ? 'h:mm a' : 'h:mm')
                            .format(slotTime),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              isHourMark ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgramGuide() {
    final now = DateTime.now().toLocal();
    final timelineStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 30) * 30,
    );
    final timelineEnd = timelineStart.add(const Duration(hours: 6));

    return ValueListenableBuilder(
      valueListenable: Hive.box<EPGChannel>('epg_channels').listenable(),
      builder: (context, Box<EPGChannel> channelsBox, _) {
        if (channelsBox.isEmpty) {
          return const Center(
            child: Text(
              'No EPG data available',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        // Initialize controllers for all channels at once
        _programControllers.clear();
        for (int i = 0; i < channelsBox.length; i++) {
          _programControllers.add(ScrollController());
        }

        return ListView.builder(
          controller: _verticalController,
          itemCount: channelsBox.length,
          itemBuilder: (context, index) {
            final channel = channelsBox.getAt(index);
            if (channel == null) return const SizedBox.shrink();

            // Make sure we have a controller for this index
            while (_programControllers.length <= index) {
              _programControllers.add(ScrollController());
            }

            return _buildChannelRow(
              channel,
              _programControllers[index],
              timelineStart,
              timelineEnd,
              index == selectedChannelIndex,
            );
          },
        );
      },
    );
  }

  List<EPGProgram> _filterRelevantPrograms(
      List<EPGProgram> programs, DateTime timelineStart, DateTime timelineEnd) {
    final now = DateTime.now().toLocal();

    return programs.where((program) {
      final programEnd =
          program.stop ?? program.start.add(const Duration(minutes: 30));
      // Only include programs overlapping the timeline and not fully in the past
      return program.start.isBefore(timelineEnd) && programEnd.isAfter(now);
    }).map((program) {
      final adjustedStart =
          program.start.isBefore(timelineStart) ? timelineStart : program.start;

      final adjustedEnd =
          program.stop == null || program.stop!.isAfter(timelineEnd)
              ? timelineEnd
              : program.stop!;

      return EPGProgram(
        title: program.title,
        start: adjustedStart,
        stop: adjustedEnd,
        channelId: program.channelId,
        description: program.description,
        categories: program.categories,
        episodeNumbers: program.episodeNumbers,
        isNew: program.isNew,
        rating: program.rating,
      );
    }).toList();
  }

  Widget _buildChannelRow(
      EPGChannel channel,
      ScrollController programController,
      DateTime timelineStart,
      DateTime timelineEnd,
      bool isSelectedChannel) {
    final programsBox = Hive.box<EPGProgram>('epg_programs');
    final programs = channel.programIds
        .map((id) => programsBox.get(id))
        .where((program) => program != null)
        .toList()
        .cast<EPGProgram>();

    // Filter programs for the current timeline
    final filteredPrograms =
        _filterRelevantPrograms(programs, timelineStart, timelineEnd);

    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          Container(
            width: channelLogoWidth,
            decoration: BoxDecoration(
              color: isSelectedChannel ? Colors.blue.shade900 : Colors.black,
              border: Border(
                right: BorderSide(color: Colors.grey.shade800),
                bottom: BorderSide(color: Colors.grey.shade800),
              ),
            ),
            child: channel.iconUrl != null
                ? Image.network(
                    channel.iconUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.tv, color: Colors.white),
                  )
                : const Icon(Icons.tv, color: Colors.white),
          ),
          Expanded(
            child: ListView.builder(
              controller: programController,
              scrollDirection: Axis.horizontal,
              itemCount: filteredPrograms.length,
              itemBuilder: (context, index) {
                final program = filteredPrograms[index];
                final isSelectedProgram =
                    isSelectedChannel && index == selectedProgramIndex;
                return _buildProgramTile(program, isSelectedProgram);
              },
            ),
          ),
        ],
      ),
    );
  }

  double _calculateTileWidth(DateTime programStart, DateTime programStop) {
    final durationInMinutes = programStop.difference(programStart).inMinutes;
    // Ensure minimum width for very short programs
    return math.max((durationInMinutes / 30.0) * timeSlotWidth, 10.0);
  }

  Widget _buildProgramTile(EPGProgram program, bool isSelected) {
    final stopTime =
        program.stop ?? program.start.add(const Duration(minutes: 30));

    // Calculate the correct width based on the time range
    final width = _calculateTileWidth(program.start, stopTime);

    return Container(
      width: width, // Tile width based on time range
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade900 : Colors.grey.shade900,
        border: Border.all(
          color: isSelected ? Colors.blue.shade500 : Colors.grey.shade800,
          width: isSelected ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: 6, vertical: 4), // Padding for spacing
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title text
          Flexible(
            child: Text(
              program.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis, // Prevent overflow for title
            ),
          ),
          // Time range text with proper formatting
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Text(
              '${DateFormat('h:mm a').format(program.start)} - '
              '${DateFormat('h:mm a').format(stopTime)}',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis, // Prevent overflow for time range
            ),
          ),
        ],
      ),
    );
  }
}

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class NavigateIntent extends Intent {
  final String direction;
  const NavigateIntent(this.direction);
}

class ShowInfoIntent extends Intent {
  const ShowInfoIntent();
}

enum ViewSection { all, favorites, vod, series }

// Create a separate StatefulWidget for the dialog
class _SectionMenuDialog extends StatefulWidget {
  @override
  State<_SectionMenuDialog> createState() => _SectionMenuDialogState();
}

class _SectionMenuDialogState extends State<_SectionMenuDialog> {
  int selectedRow = 0;
  int selectedCol = 0;
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    focusNode.requestFocus();
  }

  @override
  void dispose() {
    focusNode.dispose();
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
          case 458792: // Enter
          case 458840: // Keypad Enter
            final sections = [
              [ViewSection.all, ViewSection.favorites],
              [ViewSection.vod, ViewSection.series]
            ];
            Navigator.of(context).pop(sections[selectedRow][selectedCol]);
            break;
          case 786980: // Escape/Back
            Navigator.of(context).pop();
            break;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: focusNode,
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _buildSectionButton(
                        ViewSection.all,
                        'All',
                        Icons.grid_view_rounded,
                        selectedRow == 0 && selectedCol == 0,
                      ),
                      const SizedBox(width: 16),
                      _buildSectionButton(
                        ViewSection.favorites,
                        'Favorites',
                        Icons.star_rounded,
                        selectedRow == 0 && selectedCol == 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    children: [
                      _buildSectionButton(
                        ViewSection.vod,
                        'VOD',
                        Icons.video_library_rounded,
                        selectedRow == 1 && selectedCol == 0,
                      ),
                      const SizedBox(width: 16),
                      _buildSectionButton(
                        ViewSection.series,
                        'TV',
                        Icons.tv_rounded,
                        selectedRow == 1 && selectedCol == 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionButton(
    ViewSection section,
    String label,
    IconData icon,
    bool isSelected,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade700 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade700,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop(section);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
