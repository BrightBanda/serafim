// The schema LocalMessage had before the `forwarded` field was added.
//
// It is here so a test can open a database with the old layout, write a
// message, and then open it with the new layout to see what the migration
// does to the data that was already on the phone.
//
// Generated file, copied from git and renamed. Do not edit.
// ignore_for_file: constant_identifier_names
import 'package:isar_community/isar.dart';
import 'package:serafim/src/data/domain/local_chat_message.dart';

const OldLocalMessageSchema = CollectionSchema(
  name: r'LocalMessage',
  id: 1045835317208282169,
  properties: {
    r'durationMs': PropertySchema(
      id: 0,
      name: r'durationMs',
      type: IsarType.long,
    ),
    r'editedAt': PropertySchema(
      id: 1,
      name: r'editedAt',
      type: IsarType.dateTime,
    ),
    r'groupId': PropertySchema(id: 2, name: r'groupId', type: IsarType.string),
    r'isDeleted': PropertySchema(
      id: 3,
      name: r'isDeleted',
      type: IsarType.bool,
    ),
    r'isHiddenForMe': PropertySchema(
      id: 4,
      name: r'isHiddenForMe',
      type: IsarType.bool,
    ),
    r'localMediaPath': PropertySchema(
      id: 5,
      name: r'localMediaPath',
      type: IsarType.string,
    ),
    r'mediaRemoteId': PropertySchema(
      id: 6,
      name: r'mediaRemoteId',
      type: IsarType.string,
    ),
    r'messageId': PropertySchema(
      id: 7,
      name: r'messageId',
      type: IsarType.string,
    ),
    r'readAckPending': PropertySchema(
      id: 8,
      name: r'readAckPending',
      type: IsarType.bool,
    ),
    r'recipientId': PropertySchema(
      id: 9,
      name: r'recipientId',
      type: IsarType.string,
    ),
    r'replyToId': PropertySchema(
      id: 10,
      name: r'replyToId',
      type: IsarType.string,
    ),
    r'roomId': PropertySchema(id: 11, name: r'roomId', type: IsarType.string),
    r'senderId': PropertySchema(
      id: 12,
      name: r'senderId',
      type: IsarType.string,
    ),
    r'status': PropertySchema(
      id: 13,
      name: r'status',
      type: IsarType.byte,
      enumMap: _LocalMessagestatusEnumValueMap,
    ),
    r'textContent': PropertySchema(
      id: 14,
      name: r'textContent',
      type: IsarType.string,
    ),
    r'timestamp': PropertySchema(
      id: 15,
      name: r'timestamp',
      type: IsarType.dateTime,
    ),
    r'type': PropertySchema(
      id: 16,
      name: r'type',
      type: IsarType.byte,
      enumMap: _LocalMessagetypeEnumValueMap,
    ),
    r'waveform': PropertySchema(
      id: 17,
      name: r'waveform',
      type: IsarType.longList,
    ),
  },

  estimateSize: _oldLocalMessageEstimateSize,
  serialize: _oldLocalMessageSerialize,
  deserialize: _oldLocalMessageDeserialize,
  deserializeProp: _oldLocalMessageDeserializeProp,
  idName: r'id',
  indexes: {
    r'messageId': IndexSchema(
      id: -635287409172016016,
      name: r'messageId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'messageId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'roomId': IndexSchema(
      id: -3609232324653216207,
      name: r'roomId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'roomId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'groupId': IndexSchema(
      id: -8523216633229774932,
      name: r'groupId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'groupId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'timestamp': IndexSchema(
      id: 1852253767416892198,
      name: r'timestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'timestamp',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _oldLocalMessageGetId,
  getLinks: _oldLocalMessageGetLinks,
  attach: _oldLocalMessageAttach,
  version: '3.3.2',
);

int _oldLocalMessageEstimateSize(
  LocalMessage object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.groupId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.localMediaPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.mediaRemoteId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.messageId.length * 3;
  bytesCount += 3 + object.recipientId.length * 3;
  {
    final value = object.replyToId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.roomId.length * 3;
  bytesCount += 3 + object.senderId.length * 3;
  {
    final value = object.textContent;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.waveform;
    if (value != null) {
      bytesCount += 3 + value.length * 8;
    }
  }
  return bytesCount;
}

void _oldLocalMessageSerialize(
  LocalMessage object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.durationMs);
  writer.writeDateTime(offsets[1], object.editedAt);
  writer.writeString(offsets[2], object.groupId);
  writer.writeBool(offsets[3], object.isDeleted);
  writer.writeBool(offsets[4], object.isHiddenForMe);
  writer.writeString(offsets[5], object.localMediaPath);
  writer.writeString(offsets[6], object.mediaRemoteId);
  writer.writeString(offsets[7], object.messageId);
  writer.writeBool(offsets[8], object.readAckPending);
  writer.writeString(offsets[9], object.recipientId);
  writer.writeString(offsets[10], object.replyToId);
  writer.writeString(offsets[11], object.roomId);
  writer.writeString(offsets[12], object.senderId);
  writer.writeByte(offsets[13], object.status.index);
  writer.writeString(offsets[14], object.textContent);
  writer.writeDateTime(offsets[15], object.timestamp);
  writer.writeByte(offsets[16], object.type.index);
  writer.writeLongList(offsets[17], object.waveform);
}

LocalMessage _oldLocalMessageDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalMessage();
  object.durationMs = reader.readLongOrNull(offsets[0]);
  object.editedAt = reader.readDateTimeOrNull(offsets[1]);
  object.groupId = reader.readStringOrNull(offsets[2]);
  object.id = id;
  object.isDeleted = reader.readBool(offsets[3]);
  object.isHiddenForMe = reader.readBool(offsets[4]);
  object.localMediaPath = reader.readStringOrNull(offsets[5]);
  object.mediaRemoteId = reader.readStringOrNull(offsets[6]);
  object.messageId = reader.readString(offsets[7]);
  object.readAckPending = reader.readBool(offsets[8]);
  object.recipientId = reader.readString(offsets[9]);
  object.replyToId = reader.readStringOrNull(offsets[10]);
  object.roomId = reader.readString(offsets[11]);
  object.senderId = reader.readString(offsets[12]);
  object.status =
      _LocalMessagestatusValueEnumMap[reader.readByteOrNull(offsets[13])] ??
      MessageStatus.sending;
  object.textContent = reader.readStringOrNull(offsets[14]);
  object.timestamp = reader.readDateTime(offsets[15]);
  object.type =
      _LocalMessagetypeValueEnumMap[reader.readByteOrNull(offsets[16])] ??
      MessageType.text;
  object.waveform = reader.readLongList(offsets[17]);
  return object;
}

P _oldLocalMessageDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongOrNull(offset)) as P;
    case 1:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readBool(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    case 13:
      return (_LocalMessagestatusValueEnumMap[reader.readByteOrNull(offset)] ??
              MessageStatus.sending)
          as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readDateTime(offset)) as P;
    case 16:
      return (_LocalMessagetypeValueEnumMap[reader.readByteOrNull(offset)] ??
              MessageType.text)
          as P;
    case 17:
      return (reader.readLongList(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _LocalMessagestatusEnumValueMap = {
  'sending': 0,
  'sent': 1,
  'delivered': 2,
  'read': 3,
  'failed': 4,
};
const _LocalMessagestatusValueEnumMap = {
  0: MessageStatus.sending,
  1: MessageStatus.sent,
  2: MessageStatus.delivered,
  3: MessageStatus.read,
  4: MessageStatus.failed,
};
const _LocalMessagetypeEnumValueMap = {
  'text': 0,
  'image': 1,
  'video': 2,
  'audio': 3,
  'sticker': 4,
};
const _LocalMessagetypeValueEnumMap = {
  0: MessageType.text,
  1: MessageType.image,
  2: MessageType.video,
  3: MessageType.audio,
  4: MessageType.sticker,
};

Id _oldLocalMessageGetId(LocalMessage object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _oldLocalMessageGetLinks(LocalMessage object) {
  return [];
}

void _oldLocalMessageAttach(
  IsarCollection<dynamic> col,
  Id id,
  LocalMessage object,
) {
  object.id = id;
}

