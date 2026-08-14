// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_chat_room.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalChatRoomCollection on Isar {
  IsarCollection<LocalChatRoom> get localChatRooms => this.collection();
}

const LocalChatRoomSchema = CollectionSchema(
  name: r'LocalChatRoom',
  id: -7383583500428748710,
  properties: {
    r'lastMessageText': PropertySchema(
      id: 0,
      name: r'lastMessageText',
      type: IsarType.string,
    ),
    r'lastMessageTimestamp': PropertySchema(
      id: 1,
      name: r'lastMessageTimestamp',
      type: IsarType.dateTime,
    ),
    r'peerAvatarUrl': PropertySchema(
      id: 2,
      name: r'peerAvatarUrl',
      type: IsarType.string,
    ),
    r'peerDisplayName': PropertySchema(
      id: 3,
      name: r'peerDisplayName',
      type: IsarType.string,
    ),
    r'peerUserId': PropertySchema(
      id: 4,
      name: r'peerUserId',
      type: IsarType.string,
    ),
    r'roomId': PropertySchema(id: 5, name: r'roomId', type: IsarType.string),
    r'unreadCount': PropertySchema(
      id: 6,
      name: r'unreadCount',
      type: IsarType.long,
    ),
  },

  estimateSize: _localChatRoomEstimateSize,
  serialize: _localChatRoomSerialize,
  deserialize: _localChatRoomDeserialize,
  deserializeProp: _localChatRoomDeserializeProp,
  idName: r'id',
  indexes: {
    r'roomId': IndexSchema(
      id: -3609232324653216207,
      name: r'roomId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'roomId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _localChatRoomGetId,
  getLinks: _localChatRoomGetLinks,
  attach: _localChatRoomAttach,
  version: '3.3.2',
);

int _localChatRoomEstimateSize(
  LocalChatRoom object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.lastMessageText;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.peerAvatarUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.peerDisplayName.length * 3;
  bytesCount += 3 + object.peerUserId.length * 3;
  bytesCount += 3 + object.roomId.length * 3;
  return bytesCount;
}

void _localChatRoomSerialize(
  LocalChatRoom object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.lastMessageText);
  writer.writeDateTime(offsets[1], object.lastMessageTimestamp);
  writer.writeString(offsets[2], object.peerAvatarUrl);
  writer.writeString(offsets[3], object.peerDisplayName);
  writer.writeString(offsets[4], object.peerUserId);
  writer.writeString(offsets[5], object.roomId);
  writer.writeLong(offsets[6], object.unreadCount);
}

LocalChatRoom _localChatRoomDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalChatRoom();
  object.id = id;
  object.lastMessageText = reader.readStringOrNull(offsets[0]);
  object.lastMessageTimestamp = reader.readDateTime(offsets[1]);
  object.peerAvatarUrl = reader.readStringOrNull(offsets[2]);
  object.peerDisplayName = reader.readString(offsets[3]);
  object.peerUserId = reader.readString(offsets[4]);
  object.roomId = reader.readString(offsets[5]);
  object.unreadCount = reader.readLong(offsets[6]);
  return object;
}

P _localChatRoomDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localChatRoomGetId(LocalChatRoom object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _localChatRoomGetLinks(LocalChatRoom object) {
  return [];
}

void _localChatRoomAttach(
  IsarCollection<dynamic> col,
  Id id,
  LocalChatRoom object,
) {
  object.id = id;
}

extension LocalChatRoomByIndex on IsarCollection<LocalChatRoom> {
  Future<LocalChatRoom?> getByRoomId(String roomId) {
    return getByIndex(r'roomId', [roomId]);
  }

  LocalChatRoom? getByRoomIdSync(String roomId) {
    return getByIndexSync(r'roomId', [roomId]);
  }

  Future<bool> deleteByRoomId(String roomId) {
    return deleteByIndex(r'roomId', [roomId]);
  }

  bool deleteByRoomIdSync(String roomId) {
    return deleteByIndexSync(r'roomId', [roomId]);
  }

  Future<List<LocalChatRoom?>> getAllByRoomId(List<String> roomIdValues) {
    final values = roomIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'roomId', values);
  }

  List<LocalChatRoom?> getAllByRoomIdSync(List<String> roomIdValues) {
    final values = roomIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'roomId', values);
  }

  Future<int> deleteAllByRoomId(List<String> roomIdValues) {
    final values = roomIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'roomId', values);
  }

  int deleteAllByRoomIdSync(List<String> roomIdValues) {
    final values = roomIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'roomId', values);
  }

  Future<Id> putByRoomId(LocalChatRoom object) {
    return putByIndex(r'roomId', object);
  }

  Id putByRoomIdSync(LocalChatRoom object, {bool saveLinks = true}) {
    return putByIndexSync(r'roomId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByRoomId(List<LocalChatRoom> objects) {
    return putAllByIndex(r'roomId', objects);
  }

  List<Id> putAllByRoomIdSync(
    List<LocalChatRoom> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'roomId', objects, saveLinks: saveLinks);
  }
}

extension LocalChatRoomQueryWhereSort
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QWhere> {
  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension LocalChatRoomQueryWhere
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QWhereClause> {
  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhereClause> roomIdEqualTo(
    String roomId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'roomId', value: [roomId]),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterWhereClause>
  roomIdNotEqualTo(String roomId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'roomId',
                lower: [],
                upper: [roomId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'roomId',
                lower: [roomId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'roomId',
                lower: [roomId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'roomId',
                lower: [],
                upper: [roomId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension LocalChatRoomQueryFilter
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QFilterCondition> {
  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastMessageText'),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastMessageText'),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lastMessageText',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastMessageText',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastMessageText',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastMessageText',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'lastMessageText',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'lastMessageText',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'lastMessageText',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'lastMessageText',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastMessageText', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'lastMessageText', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTimestampEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lastMessageTimestamp',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTimestampGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastMessageTimestamp',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTimestampLessThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastMessageTimestamp',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  lastMessageTimestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastMessageTimestamp',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'peerAvatarUrl'),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'peerAvatarUrl'),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'peerAvatarUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'peerAvatarUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'peerAvatarUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'peerAvatarUrl',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'peerAvatarUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'peerAvatarUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'peerAvatarUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'peerAvatarUrl',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'peerAvatarUrl', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerAvatarUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'peerAvatarUrl', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'peerDisplayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'peerDisplayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'peerDisplayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'peerDisplayName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'peerDisplayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'peerDisplayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'peerDisplayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'peerDisplayName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'peerDisplayName', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerDisplayNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'peerDisplayName', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'peerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'peerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'peerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'peerUserId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'peerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'peerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'peerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'peerUserId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'peerUserId', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  peerUserIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'peerUserId', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'roomId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'roomId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'roomId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'roomId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'roomId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'roomId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'roomId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'roomId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'roomId', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  roomIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'roomId', value: ''),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  unreadCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'unreadCount', value: value),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  unreadCountGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'unreadCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  unreadCountLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'unreadCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterFilterCondition>
  unreadCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'unreadCount',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension LocalChatRoomQueryObject
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QFilterCondition> {}

extension LocalChatRoomQueryLinks
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QFilterCondition> {}

extension LocalChatRoomQuerySortBy
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QSortBy> {
  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByLastMessageText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageText', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByLastMessageTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageText', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByLastMessageTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTimestamp', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByLastMessageTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTimestamp', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByPeerAvatarUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerAvatarUrl', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByPeerAvatarUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerAvatarUrl', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByPeerDisplayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerDisplayName', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByPeerDisplayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerDisplayName', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> sortByPeerUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByPeerUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> sortByRoomId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> sortByRoomIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> sortByUnreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  sortByUnreadCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.desc);
    });
  }
}

extension LocalChatRoomQuerySortThenBy
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QSortThenBy> {
  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByLastMessageText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageText', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByLastMessageTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageText', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByLastMessageTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTimestamp', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByLastMessageTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTimestamp', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByPeerAvatarUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerAvatarUrl', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByPeerAvatarUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerAvatarUrl', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByPeerDisplayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerDisplayName', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByPeerDisplayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerDisplayName', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> thenByPeerUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByPeerUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> thenByRoomId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> thenByRoomIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roomId', Sort.desc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy> thenByUnreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.asc);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QAfterSortBy>
  thenByUnreadCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.desc);
    });
  }
}

extension LocalChatRoomQueryWhereDistinct
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct> {
  QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct>
  distinctByLastMessageText({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'lastMessageText',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct>
  distinctByLastMessageTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessageTimestamp');
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct>
  distinctByPeerAvatarUrl({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'peerAvatarUrl',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct>
  distinctByPeerDisplayName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'peerDisplayName',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct> distinctByPeerUserId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'peerUserId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct> distinctByRoomId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'roomId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalChatRoom, LocalChatRoom, QDistinct>
  distinctByUnreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'unreadCount');
    });
  }
}

extension LocalChatRoomQueryProperty
    on QueryBuilder<LocalChatRoom, LocalChatRoom, QQueryProperty> {
  QueryBuilder<LocalChatRoom, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LocalChatRoom, String?, QQueryOperations>
  lastMessageTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageText');
    });
  }

  QueryBuilder<LocalChatRoom, DateTime, QQueryOperations>
  lastMessageTimestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageTimestamp');
    });
  }

  QueryBuilder<LocalChatRoom, String?, QQueryOperations>
  peerAvatarUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'peerAvatarUrl');
    });
  }

  QueryBuilder<LocalChatRoom, String, QQueryOperations>
  peerDisplayNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'peerDisplayName');
    });
  }

  QueryBuilder<LocalChatRoom, String, QQueryOperations> peerUserIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'peerUserId');
    });
  }

  QueryBuilder<LocalChatRoom, String, QQueryOperations> roomIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'roomId');
    });
  }

  QueryBuilder<LocalChatRoom, int, QQueryOperations> unreadCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'unreadCount');
    });
  }
}
