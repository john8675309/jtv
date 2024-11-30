// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'epg_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EPGChannelAdapter extends TypeAdapter<EPGChannel> {
  @override
  final int typeId = 0;

  @override
  EPGChannel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EPGChannel(
      id: fields[0] as String,
      name: fields[1] as String,
      iconUrl: fields[2] as String?,
      displayNames: (fields[3] as List?)?.cast<String>(),
      programIds: (fields[4] as List?)?.cast<int>(),
      streamId: fields[5] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, EPGChannel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.iconUrl)
      ..writeByte(3)
      ..write(obj.displayNames)
      ..writeByte(4)
      ..write(obj.programIds)
      ..writeByte(5)
      ..write(obj.streamId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EPGChannelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class EPGProgramAdapter extends TypeAdapter<EPGProgram> {
  @override
  final int typeId = 1;

  @override
  EPGProgram read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EPGProgram(
      title: fields[0] as String,
      start: fields[1] as DateTime,
      channelId: fields[4] as String,
      stop: fields[2] as DateTime?,
      description: fields[3] as String?,
      categories: (fields[5] as List?)?.cast<String>(),
      episodeNumbers: (fields[6] as List?)?.cast<String>(),
      isNew: fields[7] as bool,
      rating: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, EPGProgram obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.start)
      ..writeByte(2)
      ..write(obj.stop)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.channelId)
      ..writeByte(5)
      ..write(obj.categories)
      ..writeByte(6)
      ..write(obj.episodeNumbers)
      ..writeByte(7)
      ..write(obj.isNew)
      ..writeByte(8)
      ..write(obj.rating);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EPGProgramAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FavoriteChannelAdapter extends TypeAdapter<FavoriteChannel> {
  @override
  final int typeId = 2;

  @override
  FavoriteChannel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FavoriteChannel(
      id: fields[0] as String,
      name: fields[1] as String,
      iconUrl: fields[2] as String?,
      streamId: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, FavoriteChannel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.iconUrl)
      ..writeByte(3)
      ..write(obj.streamId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteChannelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
