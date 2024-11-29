import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:jtv/epg_models.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart'; // Provides [Player], [Media], [Playlist] etc.
import 'package:media_kit_video/media_kit_video.dart';

class PickerScreen extends StatefulWidget {
  final dynamic client;

  const PickerScreen({super.key, required this.client});

  @override
  // ignore: library_private_types_in_public_api
  _PickerScreenState createState() => _PickerScreenState();
}

class _PickerScreenState extends State<PickerScreen> {
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

  late final player = Player();
  late final _videoController = VideoController(player);
  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
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

      if (Hive.box<EPGChannel>('epg_channels').isEmpty) {
        await _refreshEPGData();
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _refreshEPGData() async {
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
  }

  Widget _buildVideoPreview() {
    if (!player.state.playing) {
      return const SizedBox.shrink();
    }

    if (_isFullScreen) {
      return Positioned.fill(
        child: Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(
              controller: _videoController,
              controls: AdaptiveVideoControls, // Use the default controls
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
            child: Video(
              controller: _videoController,
              controls: AdaptiveVideoControls,
            ),
          ),
        ),
      );
    }
  }

  void _showProgramInfo() {
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

      player.open(Media(baseUrl));

      // Enter full-screen mode
      setState(() {
        _isFullScreen = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {}
      },
      child: FocusableActionDetector(
        autofocus: true,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyR, control: true):
              RefreshIntent(),
          SingleActivator(LogicalKeyboardKey.f5): RefreshIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): NavigateIntent('up'),
          SingleActivator(LogicalKeyboardKey.arrowDown): NavigateIntent('down'),
          SingleActivator(LogicalKeyboardKey.arrowLeft): NavigateIntent('left'),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              NavigateIntent('right'),
          SingleActivator(LogicalKeyboardKey.enter): ShowInfoIntent(),
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
    // Get the current time and round down to the nearest half hour
    final now = DateTime.now();
    final timelineStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 30) * 30, // Round to nearest 30 min
    );

    List<DateTime> timeSlots = [];
    var currentTime = timelineStart;

    // Generate time slots
    for (int i = 0; i < 12; i++) {
      // 6 hours worth of 30-min slots
      timeSlots.add(currentTime);
      currentTime = currentTime.add(const Duration(minutes: 30));
    }

    return SizedBox(
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
                    DateFormat(isHourMark ? 'h:mm a' : 'h:mm').format(slotTime),
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
