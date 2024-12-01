import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jtv/screens/PickerScreen.dart';
import 'package:jtv/screens/FavoritesScreen.dart';

class VodScreen extends StatefulWidget {
  final dynamic client;

  const VodScreen({super.key, required this.client});

  @override
  _VodScreenState createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _movies = [];
  bool _isLoading = true;
  int _selectedIndex = 0;
  bool _isFullScreen = false;
  late final player = Player();
  late final _videoController = VideoController(player);
  final FocusNode _mainFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _loadMovies();
    _mainFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _mainFocusNode.dispose();
    if (player.state.playing) {
      player.stop();
    }
    player.dispose();
    super.dispose();
  }

  Future<void> _loadMovies() async {
    setState(() => _isLoading = true);
    try {
      final vodStreams = await widget.client.vodItems();
      setState(() {
        _movies = vodStreams;
        _isLoading = false;
      });
      print('Loaded ${_movies.length} movies');
    } catch (e) {
      print('Error loading VOD: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _playMovie(dynamic movie) async {
    try {
      if (movie.streamId != null) {
        final url = widget.client.movieUrl(movie.streamId, "ts");
        final baseUrl = url.substring(0, url.lastIndexOf('.ts'));
        //print('Playing movie: ${movie.name} at URL: $baseUrl $url');
        player.open(Media(url));
        setState(() {
          _isFullScreen = true;
        });
      }
    } catch (e) {
      print('Error playing movie: $e');
    }
  }

  Future<ViewSection?> _showSectionMenu() {
    return showDialog<ViewSection>(
      context: context,
      builder: (BuildContext context) => _SectionMenuDialog(),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.physicalKey.usbHidUsage) {
        case 458834: // Up
          if (_selectedIndex > 0) {
            setState(() => _selectedIndex--);
            _ensureItemVisible();
          }
          break;
        case 458833: // Down
          if (_selectedIndex < _movies.length - 1) {
            setState(() => _selectedIndex++);
            _ensureItemVisible();
          }
          break;
        case 458792: // Enter
          if (_isFullScreen) {
            setState(() => _isFullScreen = false);
            player.stop();
          } else if (_movies.isNotEmpty) {
            _playMovie(_movies[_selectedIndex]);
          }
          break;
        case 786979: // Menu
          if (_isFullScreen) {
            setState(() => _isFullScreen = false);
            player.stop();
          } else {
            _showSectionMenu().then((section) {
              if (section != null) {
                if (player.state.playing) {
                  player.stop();
                }
                switch (section) {
                  case ViewSection.all:
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            PickerScreen(client: widget.client),
                      ),
                    );
                    break;
                  case ViewSection.favorites:
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FavoritesScreen(client: widget.client),
                      ),
                    );
                    break;
                  default:
                    break;
                }
              }
            });
          }
          break;
      }
    }
  }

  void _ensureItemVisible() {
    if (!_scrollController.hasClients) return;

    const itemHeight = 100.0;
    final viewportHeight = _scrollController.position.viewportDimension;
    final offset = _selectedIndex * itemHeight;

    if (offset < _scrollController.offset ||
        offset > _scrollController.offset + viewportHeight - itemHeight) {
      _scrollController.jumpTo(
        (offset - (viewportHeight / 2) + (itemHeight / 2))
            .clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  Widget _buildVideoPreview() {
    if (!player.state.playing) return const SizedBox.shrink();

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
    }
    return const SizedBox.shrink();
  }

  Widget _buildMovieItem(dynamic movie, bool isSelected) {
    return Container(
      height: 100,
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade900 : Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 150,
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.grey.shade800,
            ),
            child: movie.streamIcon != null && movie.streamIcon.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      movie.streamIcon,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.movie,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.movie,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    movie.name ?? movie.title ?? 'Unknown Title',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (movie.year != null) ...[
                    SizedBox(height: 4),
                    Text(
                      'Year: ${movie.year}',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (movie.rating != null) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Rating: ',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                        ...List.generate(
                          5,
                          (index) => Icon(
                            Icons.star,
                            size: 16,
                            color: index < (movie.rating5based ?? 0)
                                ? Colors.amber
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (movie.added != null) ...[
                    SizedBox(height: 4),
                    Text(
                      'Added: ${DateFormat('MMM d, yyyy').format(movie.added)}',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _mainFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ListView.builder(
                controller: _scrollController,
                itemCount: _movies.length,
                itemBuilder: (context, index) {
                  final movie = _movies[index];
                  final isSelected = index == _selectedIndex;
                  return _buildMovieItem(movie, isSelected);
                },
              ),
            if (player.state.playing) _buildVideoPreview(),
          ],
        ),
      ),
    );
  }
}

class _SectionMenuDialog extends StatefulWidget {
  @override
  State<_SectionMenuDialog> createState() => _SectionMenuDialogState();
}

class _SectionMenuDialogState extends State<_SectionMenuDialog> {
  int selectedRow = 1;
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

// Also add this enum if not already present
enum ViewSection { all, favorites, vod, series }
