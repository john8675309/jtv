import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:jtv/epg_models.dart';
import 'package:flutter/services.dart'; // For RawKeyEvent and LogicalKeyboardKey

class SearchDialog extends StatefulWidget {
  final Box<EPGChannel> channelsBox;
  final Box<EPGProgram> programsBox;

  const SearchDialog({
    super.key,
    required this.channelsBox,
    required this.programsBox,
  });

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  late TextEditingController _searchController;
  final FocusNode _keyboardListenerFocusNode = FocusNode();
  final FocusNode _resultsListFocusNode = FocusNode();
  List<SearchResult> _searchResults = [];
  int _selectedResultIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFieldFocusNode = FocusNode();

  final List<List<String>> _customLayout = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M', 'DEL'],
    ['SPACE']
  ];

  int _currentRow = 0;
  int _currentCol = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFieldFocusNode.requestFocus(); // Focus the text field first
    });
    print("SearchDialog initState called");
    _searchController.addListener(() {
      print("Here");
      _performSearch(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _keyboardListenerFocusNode.dispose();
    _resultsListFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
    _textFieldFocusNode.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event.runtimeType.toString() == "KeyDownEvent") {
      if (event.physicalKey.usbHidUsage == 786980) {
        Navigator.of(context).pop(); // Close the dialog
      } else if (event.physicalKey.usbHidUsage == 458831) {
        _moveFocus(Direction.right);
      } else if (event.physicalKey.usbHidUsage == 458832) {
        _moveFocus(Direction.left);
      } else if (event.physicalKey.usbHidUsage == 458833) {
        if (_resultsListFocusNode.hasFocus) {
          if (_selectedResultIndex < _searchResults.length - 1) {
            setState(() {
              _selectedResultIndex++;
            });
            _ensureItemVisible(); // Add this call
          }
        } else {
          _moveFocus(Direction.down);
        }
      } else if (event.physicalKey.usbHidUsage == 458834) {
        if (_resultsListFocusNode.hasFocus) {
          if (_selectedResultIndex > 0) {
            setState(() {
              _selectedResultIndex--;
            });
            _ensureItemVisible(); // Add this call
          }
        } else {
          _moveFocus(Direction.up);
        }
      } else if (event.physicalKey.usbHidUsage == 458792) {
        // Enter key
        if (_resultsListFocusNode.hasFocus) {
          if (_searchResults.isNotEmpty) {
            final result = _searchResults[_selectedResultIndex];
            Navigator.pop(
                context,
                SearchResult(
                    type: result.type,
                    channelId: result.channelId,
                    programId: result.programId,
                    title: result.title,
                    subtitle: result.subtitle,
                    streamId: result.streamId, // Add this
                    shouldChangeSelection: true));
          }
        } else {
          _selectKey();
        }
      }
    }
  }

  void _moveFocus(Direction direction) {
    setState(() {
      if (direction == Direction.up) {
        if (_currentRow == 0) {
          print("Moving Focus");
          // Move focus to the results list popup when at the top of the keyboard
          _resultsListFocusNode.requestFocus();
        } else {
          _currentRow--;
          if (_currentCol >= _customLayout[_currentRow].length) {
            _currentCol = _customLayout[_currentRow].length - 1;
          }
        }
      } else if (direction == Direction.down) {
        if (_resultsListFocusNode.hasFocus) {
          // If focused on results list, move focus back to the keyboard
          _keyboardListenerFocusNode.requestFocus();
        } else if (_currentRow < _customLayout.length - 1) {
          _currentRow++;
          if (_currentCol >= _customLayout[_currentRow].length) {
            _currentCol = _customLayout[_currentRow].length - 1;
          }
        }
      } else if (direction == Direction.left) {
        if (_currentCol > 0) {
          _currentCol--;
        }
      } else if (direction == Direction.right) {
        if (_currentCol < _customLayout[_currentRow].length - 1) {
          _currentCol++;
        }
      }
    });
  }

  void _ensureItemVisible() {
    if (!_scrollController.hasClients) return;

    final itemHeight = 60.0; // Adjusted for actual item height
    final searchBarHeight = 80.0; // TextField + padding
    final keyboardHeight = 300.0; // Keyboard + padding
    final viewportHeight = _scrollController.position.viewportDimension;
    final availableHeight = viewportHeight - keyboardHeight;

    final itemTopPosition =
        (_selectedResultIndex * itemHeight) + searchBarHeight;

    // If the item is above the current viewport
    if (itemTopPosition < _scrollController.offset + searchBarHeight) {
      _scrollController.animateTo(
        itemTopPosition - searchBarHeight,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
    // If the item is below the visible area
    else if (itemTopPosition + itemHeight >
        _scrollController.offset + availableHeight) {
      _scrollController.animateTo(
        (itemTopPosition - availableHeight + itemHeight),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _selectKey() {
    final selectedKey = _customLayout[_currentRow][_currentCol];
    setState(() {
      if (selectedKey == 'DEL') {
        if (_searchController.text.isNotEmpty) {
          _searchController.text = _searchController.text
              .substring(0, _searchController.text.length - 1);
        }
      } else if (selectedKey == 'SPACE') {
        _searchController.text += ' ';
      } else {
        _searchController.text += selectedKey;
      }
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = <SearchResult>[];
    final lowercaseQuery = query.toLowerCase();
    final currentTime = DateTime.now();

    // Filter channels by name
    for (var channel in widget.channelsBox.values) {
      if (channel.name.toLowerCase().contains(lowercaseQuery)) {
        results.add(SearchResult(
          type: 'channel',
          channelId: channel.id,
          title: channel.name,
          subtitle: 'Channel',
          streamId: channel.streamId,
        ));
      }
    }

    // Filter currently airing programs by title/description
    for (var program in widget.programsBox.values) {
      // Convert UTC times to local
      final localStart = program.start?.toLocal();
      final localStop = program.stop?.toLocal();

      if (localStart != null &&
          localStop != null &&
          localStart.isBefore(currentTime) &&
          localStop.isAfter(currentTime) &&
          (program.title.toLowerCase().contains(lowercaseQuery) ||
              (program.description?.toLowerCase().contains(lowercaseQuery) ??
                  false))) {
        final channel = widget.channelsBox.values.firstWhere(
          (c) => c.id == program.channelId,
          orElse: () => EPGChannel(
            id: 'unknown',
            name: 'Unknown Channel',
          ),
        );

        results.add(SearchResult(
          type: 'program',
          channelId: program.channelId,
          programId: program.key as int,
          title: program.title,
          subtitle:
              '${channel.name} - ${DateFormat('h:mm a').format(localStart)}',
          streamId: channel.streamId, // Add this
        ));
      }
    }

    setState(() {
      _searchResults = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double dialogPadding = 16 * 2; // Left and right padding
    final double dialogWidth =
        MediaQuery.of(context).size.width * 0.8 - dialogPadding;
    final int maxKeysInRow =
        _customLayout.map((row) => row.length).reduce((a, b) => a > b ? a : b);
    final double keyWidth =
        dialogWidth / maxKeysInRow; // Dynamically calculate width per key
    final double keyHeight = 60; // Fixed height for all keys

    return KeyboardListener(
      focusNode: _keyboardListenerFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.grey.shade900,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search Bar
              TextField(
                focusNode: _textFieldFocusNode,
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  _performSearch(value); // Perform search as text changes
                },
                decoration: InputDecoration(
                  hintText: 'Search channels and programs...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: const Icon(Icons.search, color: Colors.white),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  fillColor: Colors.grey.shade800,
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
// Replace the Expanded results list section with:

// Results List
              Expanded(
                child: Focus(
                  focusNode: _resultsListFocusNode,
                  onKey: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.physicalKey == PhysicalKeyboardKey.arrowUp) {
                        if (_selectedResultIndex > 0) {
                          setState(() {
                            _selectedResultIndex--;
                          });
                          _ensureItemVisible(); // Add this
                        }
                        return KeyEventResult.handled;
                      } else if (event.physicalKey ==
                          PhysicalKeyboardKey.arrowDown) {
                        if (_selectedResultIndex < _searchResults.length - 1) {
                          setState(() {
                            _selectedResultIndex++;
                          });
                          _ensureItemVisible(); // Add this
                        }
                        return KeyEventResult.handled;
                      } else if (event.physicalKey ==
                          PhysicalKeyboardKey.enter) {
                        if (_searchResults.isNotEmpty) {
                          Navigator.pop(
                              context, _searchResults[_selectedResultIndex]);
                        }
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ListView.builder(
                    controller: _scrollController, // Add this line
                    itemCount: _searchResults.length,
                    padding: EdgeInsets.only(bottom: 300),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedResultIndex == index;
                      return MouseRegion(
                        hitTestBehavior: HitTestBehavior.translucent,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _selectedResultIndex = index;
                            });
                            Navigator.pop(context, _searchResults[index]);
                          },
                          child: Container(
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _searchResults[index].title,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey.shade400,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _searchResults[index].subtitle,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Keyboard
              SizedBox(
                height: keyHeight * 5, // Fixed height for the keyboard
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _customLayout.map((rowKeys) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: rowKeys.map((keyLabel) {
                        final isFocused =
                            _customLayout[_currentRow][_currentCol] == keyLabel;

                        // Dynamically adjust the size for 'SPACE'
                        if (keyLabel == 'SPACE') {
                          return SizedBox(
                            width: keyWidth * 2, // Make 'SPACE' twice as wide
                            height: keyHeight,
                            child: Container(
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: isFocused
                                    ? Colors.blue.shade100
                                    : Colors.grey.shade800,
                                border: Border.all(
                                  color: isFocused
                                      ? Colors.blue
                                      : Colors.grey.shade700,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                keyLabel,
                                style: TextStyle(
                                  color: isFocused
                                      ? Colors.blue.shade800
                                      : Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }

                        // Render other keys normally
                        return SizedBox(
                          width: keyWidth,
                          height: keyHeight,
                          child: Container(
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              color: isFocused
                                  ? Colors.blue.shade100
                                  : Colors.grey.shade800,
                              border: Border.all(
                                color: isFocused
                                    ? Colors.blue
                                    : Colors.grey.shade700,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              keyLabel,
                              style: TextStyle(
                                color: isFocused
                                    ? Colors.blue.shade800
                                    : Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum Direction { up, down, left, right }

class SearchResult {
  final String type;
  final String channelId;
  final int? programId;
  final String title;
  final String subtitle;
  final bool shouldChangeSelection;
  final int? streamId; // Add this

  SearchResult({
    required this.type,
    required this.channelId,
    this.programId,
    required this.title,
    required this.subtitle,
    this.shouldChangeSelection = false,
    this.streamId, // Add this
  });
}
