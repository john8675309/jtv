import 'package:hive/hive.dart';

part 'epg_models.g.dart';

@HiveType(typeId: 0)
class EPGChannel extends HiveObject {
  @HiveField(0)
  final String id; // This is the EPG channel ID (like "cinemax.us")

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? iconUrl;

  @HiveField(3)
  final List<String> displayNames;

  @HiveField(4)
  final List<int> programIds;

  @HiveField(5)
  final int? streamId; // This will store the IPTV stream ID (like "50")

  EPGChannel({
    required this.id,
    required this.name,
    this.iconUrl,
    List<String>? displayNames,
    List<int>? programIds,
    this.streamId,
  })  : this.displayNames = displayNames ?? [],
        this.programIds = programIds ?? [];
}

@HiveType(typeId: 1)
class EPGProgram extends HiveObject {
  @HiveField(0)
  final String title;

  @HiveField(1)
  final DateTime start;

  @HiveField(2)
  final DateTime? stop;

  @HiveField(3)
  final String? description;

  @HiveField(4)
  final String channelId;

  @HiveField(5)
  List<String> categories;

  @HiveField(6)
  List<String>? episodeNumbers;

  @HiveField(7)
  final bool isNew;

  @HiveField(8)
  final String? rating;

  EPGProgram({
    required this.title,
    required this.start,
    required this.channelId,
    this.stop,
    this.description,
    List<String>? categories,
    List<String>? episodeNumbers,
    this.isNew = false,
    this.rating,
  })  : this.categories = List<String>.from(categories ?? []),
        this.episodeNumbers =
            episodeNumbers != null ? List<String>.from(episodeNumbers) : null;
}

@HiveType(typeId: 2)
class FavoriteChannel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? iconUrl;

  @HiveField(3)
  final int streamId;

  FavoriteChannel({
    required this.id,
    required this.name,
    this.iconUrl,
    required this.streamId,
  });
}
