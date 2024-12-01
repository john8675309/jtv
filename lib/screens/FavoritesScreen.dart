import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:jtv/epg_models.dart';
import 'package:jtv/screens/PickerScreen.dart';
import 'package:jtv/screens/SearchDialog.dart';
import 'package:jtv/screens/VodScreen.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class FavoritesScreen extends StatefulWidget {
  final dynamic client;

  const FavoritesScreen({super.key, required this.client});

  @override
  _FavoritesScreenState createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
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
  bool _isFullScreen = false;
  bool _isLongPress = false;
  Timer? _longPressTimer;
  final FocusNode _mainFocusNode = FocusNode();
  late final player = Player();
  late final _videoController = VideoController(player);
  bool _shouldAutoPlay = false;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _initializeData();
    _timelineController.addListener(_synchronizeScroll);

    // Request focus after a short delay to ensure widget is built
    Future.delayed(Duration(milliseconds: 100), () {
      if (mounted) {
        _mainFocusNode.requestFocus();
      }
    });
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
    if (player.state.playing) {
      player.stop();
    }
    player.dispose();
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
      await Hive.openBox<FavoriteChannel>('favorites');
      await Hive.openBox<EPGChannel>('epg_channels');
      await Hive.openBox<EPGProgram>('epg_programs');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _handleNavigation(String direction) {
    print("Handling navigation: $direction"); // Debug print

    if (_isFullScreen) {
      setState(() {
        _isFullScreen = false;
      });
      return;
    }

    final favoritesBox = Hive.box<FavoriteChannel>('favorites');
    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final favoriteChannels = channelsBox.values
        .where(
            (channel) => favoritesBox.values.any((fav) => fav.id == channel.id))
        .toList();

    print(
        "Number of favorite channels: ${favoriteChannels.length}"); // Debug print
    print("Current selectedChannelIndex: $selectedChannelIndex"); // Debug print

    if (favoriteChannels.isEmpty) {
      print("No favorite channels found");
      return;
    }

    setState(() {
      switch (direction) {
        case 'up':
          if (selectedChannelIndex > 0) {
            selectedChannelIndex--;
            print("Moving up to index: $selectedChannelIndex"); // Debug print
          }
          break;

        case 'down':
          if (selectedChannelIndex < favoriteChannels.length - 1) {
            selectedChannelIndex++;
            print("Moving down to index: $selectedChannelIndex"); // Debug print
          }
          break;

        case 'left':
        case 'right':
          final currentChannel = favoriteChannels[selectedChannelIndex];
          final programsBox = Hive.box<EPGProgram>('epg_programs');

          final newIndex = direction == 'left'
              ? selectedProgramIndex - 1
              : selectedProgramIndex + 1;

          if (newIndex >= 0 && newIndex < currentChannel.programIds.length) {
            selectedProgramIndex = newIndex;
            print(
                "Moving ${direction} to program index: $selectedProgramIndex"); // Debug print
          }
          break;
      }

      // Ensure the selected channel is visible after navigation
      _ensureChannelVisible();
    });
  }

  void _ensureChannelVisible() {
    final selectedPosition = selectedChannelIndex * rowHeight;
    final viewportHeight = _verticalController.position.viewportDimension;

    if (selectedPosition < _verticalController.offset) {
      _verticalController.jumpTo(selectedPosition);
    } else if (selectedPosition + rowHeight >
        _verticalController.offset + viewportHeight) {
      _verticalController.jumpTo(
        selectedPosition - viewportHeight + rowHeight,
      );
    }
  }

  void _ensureProgramVisible(EPGChannel channel, Box<EPGProgram> programsBox) {
    double offset = 0;
    for (int i = 0; i < selectedProgramIndex; i++) {
      final program = programsBox.get(channel.programIds[i]);
      if (program != null) {
        final duration =
            program.stop?.difference(program.start) ?? Duration(minutes: 30);
        offset += (duration.inMinutes / 30) * timeSlotWidth;
      }
    }

    _timelineController.jumpTo(
      offset.clamp(0.0, _timelineController.position.maxScrollExtent),
    );

    for (var controller in _programControllers) {
      if (controller.hasClients) {
        controller.jumpTo(
          offset.clamp(0.0, controller.position.maxScrollExtent),
        );
      }
    }
  }

  void _showProgramInfo() {
    if (!_shouldAutoPlay) {
      _shouldAutoPlay = true;
      return;
    }
    if (_isFullScreen) {
      setState(() {
        _isFullScreen = false;
      });
      return;
    }

    final favoritesBox = Hive.box<FavoriteChannel>('favorites');
    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final favoriteChannels = channelsBox.values
        .where(
            (channel) => favoritesBox.values.any((fav) => fav.id == channel.id))
        .toList();

    if (favoriteChannels.isEmpty) return;

    final channel = favoriteChannels[selectedChannelIndex];
    if (channel.streamId != null) {
      try {
        final url = widget.client.streamUrl(channel.streamId!, ["ts"]);
        final baseUrl = url.substring(0, url.lastIndexOf('.ts'));
        player.open(Media(baseUrl));
        setState(() {
          _isFullScreen = true;
        });
      } catch (e) {
        print('Error getting stream URL: $e');
      }
    }
  }

  Future<void> _removeFavorite(EPGChannel channel) async {
    final favoritesBox = Hive.box<FavoriteChannel>('favorites');
    final favoriteToRemove =
        favoritesBox.values.firstWhere((fav) => fav.id == channel.id);
    await favoriteToRemove.delete();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${channel.name} removed from favorites'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _removeFromFavorites(EPGChannel channel) async {
    final favoritesBox = Hive.box<FavoriteChannel>('favorites');

    try {
      final favoriteToRemove = favoritesBox.values.firstWhere(
        (fav) => fav.id == channel.id,
      );

      await favoriteToRemove.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${channel.name} removed from favorites'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Channel not found in favorites: ${e.toString()}');
      // Optionally show an error message to the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing channel from favorites'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _showRemoveFromFavoritesDialog(EPGChannel channel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: Text(
          'Remove from Favorites',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Would you like to remove "${channel.name}" from your favorites?',
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
      await _removeFromFavorites(channel);
    }
  }

  void _handleLongPress() {
    _isLongPress = true;
    final favoritesBox = Hive.box<FavoriteChannel>('favorites');
    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final favoriteChannels = channelsBox.values
        .where(
            (channel) => favoritesBox.values.any((fav) => fav.id == channel.id))
        .toList();

    if (favoriteChannels.isNotEmpty) {
      final channel = favoriteChannels[selectedChannelIndex];
      _showRemoveFromFavoritesDialog(channel);
    }
  }

  Future<ViewSection?> _showSectionMenu() async {
    final result = await showDialog<ViewSection>(
      context: context,
      builder: (BuildContext context) => _SectionMenuDialog(),
    );
    if (result != null && mounted) {
      switch (result) {
        case ViewSection.all:
          if (player.state.playing) {
            player.stop();
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PickerScreen(client: widget.client),
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
              builder: (context) => VodScreen(client: widget.client),
            ),
          );
          break;
        case ViewSection.series:
          if (player.state.playing) {
            player.stop();
          }
          // Once SeriesScreen is implemented, add navigation here
          // Navigator.pushReplacement(
          //   context,
          //   MaterialPageRoute(
          //     builder: (context) => SeriesScreen(client: widget.client),
          //   ),
          // );
          break;
        case ViewSection.favorites:
          // We're already in favorites, so no need to navigate
          break;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _mainFocusNode,
      onKeyEvent: (KeyEvent event) {
        print("Key event: ${event.physicalKey.usbHidUsage}"); // Debug print
        if (event is KeyDownEvent) {
          switch (event.physicalKey.usbHidUsage) {
            case 458834: // Up
              _handleNavigation('up');
              break;
            case 458833: // Down
              _handleNavigation('down');
              break;
            case 458831: // Right
              _handleNavigation('right');
              break;
            case 458832: // Left
              _handleNavigation('left');
              break;
            case 458792: // Enter key down
              _longPressTimer?.cancel();
              _longPressTimer = Timer(const Duration(seconds: 1), () {
                _handleLongPress();
              });
              break;
            case 786979: // Menu
              _showSectionMenu();
              break;
          }
        } else if (event is KeyUpEvent &&
            event.physicalKey.usbHidUsage == 458792) {
          // Enter key up
          _longPressTimer?.cancel();
          if (!_isLongPress) {
            _showProgramInfo(); // Play the channel
          }
          _isLongPress = false;
        }
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
            if (player.state.playing) _buildVideoPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (_isFullScreen) {
      return Positioned.fill(
        child: Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(
              controller: _videoController,
              controls: AdaptiveVideoControls,
            ),
          ),
        ),
      );
    } else {
      return Positioned(
        top: 16,
        right: 16,
        width: 240,
        height: 135,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
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
    final favoritesBox = Hive.box<FavoriteChannel>('favorites');
    final channelsBox = Hive.box<EPGChannel>('epg_channels');
    final programsBox = Hive.box<EPGProgram>('epg_programs');

    // Get favorite channels
    final favoriteChannels = channelsBox.values
        .where(
            (channel) => favoritesBox.values.any((fav) => fav.id == channel.id))
        .toList();

    // Get selected channel and program
    final selectedChannel = favoriteChannels.isEmpty
        ? null
        : favoriteChannels[selectedChannelIndex];
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
                    Expanded(
                      child: Text(
                        selectedProgram.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
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
                      Expanded(
                        child: Text(
                          selectedProgram.categories.join(', '),
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
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

  Widget _buildProgramList(
    EPGChannel channel,
    ScrollController programController,
    DateTime timelineStart,
    DateTime timelineEnd,
    bool isSelectedChannel,
  ) {
    final programsBox = Hive.box<EPGProgram>('epg_programs');
    final programs = channel.programIds
        .map((id) => programsBox.get(id))
        .where((program) => program != null)
        .toList()
        .cast<EPGProgram>();

    final filteredPrograms =
        _filterRelevantPrograms(programs, timelineStart, timelineEnd);

    return ListView.builder(
      controller: programController,
      scrollDirection: Axis.horizontal,
      itemCount: filteredPrograms.length,
      itemBuilder: (context, index) {
        final program = filteredPrograms[index];
        final isSelectedProgram =
            isSelectedChannel && index == selectedProgramIndex;

        print(
            "Building program: ${program.title}, isSelected: $isSelectedProgram"); // Debug print

        return _buildProgramTile(program, isSelectedProgram);
      },
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
      valueListenable: Hive.box<FavoriteChannel>('favorites').listenable(),
      builder: (context, Box<FavoriteChannel> favoritesBox, _) {
        final channelsBox = Hive.box<EPGChannel>('epg_channels');
        final favoriteChannels = channelsBox.values
            .where((channel) =>
                favoritesBox.values.any((fav) => fav.id == channel.id))
            .toList();

        print(
            "Building guide with ${favoriteChannels.length} channels"); // Debug print
        print("Selected channel index: $selectedChannelIndex"); // Debug print

        if (favoriteChannels.isEmpty) {
          return const Center(
            child: Text(
              'No favorite channels yet',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          );
        }

        // Reset selected index if it's out of bounds
        if (selectedChannelIndex >= favoriteChannels.length) {
          selectedChannelIndex = favoriteChannels.length - 1;
        }

        // Initialize controllers for all channels
        _programControllers.clear();
        for (int i = 0; i < favoriteChannels.length; i++) {
          _programControllers.add(ScrollController());
        }

        return ListView.builder(
          controller: _verticalController,
          itemCount: favoriteChannels.length,
          itemBuilder: (context, index) {
            final channel = favoriteChannels[index];
            final isSelected = index == selectedChannelIndex;

            print(
                "Building channel $index, isSelected: $isSelected"); // Debug print

            return _buildChannelRow(
              channel,
              _programControllers[index],
              timelineStart,
              timelineEnd,
              isSelected,
            );
          },
        );
      },
    );
  }

  Widget _buildChannelRow(
    EPGChannel channel,
    ScrollController programController,
    DateTime timelineStart,
    DateTime timelineEnd,
    bool isSelectedChannel,
  ) {
    print(
        "Building channel row: ${channel.name}, isSelected: $isSelectedChannel"); // Debug print

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
            child: _buildProgramList(
              channel,
              programController,
              timelineStart,
              timelineEnd,
              isSelectedChannel,
            ),
          ),
        ],
      ),
    );
  }

  List<EPGProgram> _filterRelevantPrograms(
    List<EPGProgram> programs,
    DateTime timelineStart,
    DateTime timelineEnd,
  ) {
    final now = DateTime.now().toLocal();

    return programs.where((program) {
      final programEnd =
          program.stop ?? program.start.add(const Duration(minutes: 30));
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

  Widget _buildProgramTile(EPGProgram program, bool isSelected) {
    final stopTime =
        program.stop ?? program.start.add(const Duration(minutes: 30));
    final width = _calculateTileWidth(program.start, stopTime);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade900 : Colors.grey.shade900,
        border: Border.all(
          color: isSelected ? Colors.blue.shade500 : Colors.grey.shade800,
          width: isSelected ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              program.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateTileWidth(DateTime programStart, DateTime programStop) {
    final durationInMinutes = programStop.difference(programStart).inMinutes;
    return math.max((durationInMinutes / 30.0) * timeSlotWidth, 10.0);
  }
}

class _SectionMenuDialog extends StatefulWidget {
  @override
  State<_SectionMenuDialog> createState() => _SectionMenuDialogState();
}

class _SectionMenuDialogState extends State<_SectionMenuDialog> {
  int selectedRow = 0;
  int selectedCol = 1;
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
}

// Add this enum at the top of your file
enum ViewSection { all, favorites, vod, series }
