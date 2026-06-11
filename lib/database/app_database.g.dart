// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _knowledgeScopeMeta =
      const VerificationMeta('knowledgeScope');
  @override
  late final GeneratedColumn<int> knowledgeScope = GeneratedColumn<int>(
      'knowledge_scope', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(2));
  @override
  List<GeneratedColumn> get $columns =>
      [id, title, createdAt, updatedAt, knowledgeScope];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(Insertable<Session> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('knowledge_scope')) {
      context.handle(
          _knowledgeScopeMeta,
          knowledgeScope.isAcceptableOrUnknown(
              data['knowledge_scope']!, _knowledgeScopeMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      knowledgeScope: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}knowledge_scope'])!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// KnowledgeScope enum: 0=sessionOnly, 1=globalOnly, 2=globalAndSession (default)
  final int knowledgeScope;
  const Session(
      {required this.id,
      required this.title,
      required this.createdAt,
      required this.updatedAt,
      required this.knowledgeScope});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['knowledge_scope'] = Variable<int>(knowledgeScope);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      knowledgeScope: Value(knowledgeScope),
    );
  }

  factory Session.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      knowledgeScope: serializer.fromJson<int>(json['knowledgeScope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'knowledgeScope': serializer.toJson<int>(knowledgeScope),
    };
  }

  Session copyWith(
          {String? id,
          String? title,
          DateTime? createdAt,
          DateTime? updatedAt,
          int? knowledgeScope}) =>
      Session(
        id: id ?? this.id,
        title: title ?? this.title,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        knowledgeScope: knowledgeScope ?? this.knowledgeScope,
      );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      knowledgeScope: data.knowledgeScope.present
          ? data.knowledgeScope.value
          : this.knowledgeScope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('knowledgeScope: $knowledgeScope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, createdAt, updatedAt, knowledgeScope);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.knowledgeScope == this.knowledgeScope);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<String> title;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> knowledgeScope;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.knowledgeScope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.knowledgeScope = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? knowledgeScope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (knowledgeScope != null) 'knowledge_scope': knowledgeScope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? knowledgeScope,
      Value<int>? rowid}) {
    return SessionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      knowledgeScope: knowledgeScope ?? this.knowledgeScope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (knowledgeScope.present) {
      map['knowledge_scope'] = Variable<int>(knowledgeScope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('knowledgeScope: $knowledgeScope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sessions (id)'));
  @override
  late final GeneratedColumnWithTypeConverter<MessageRole, String> role =
      GeneratedColumn<String>('role', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<MessageRole>($MessagesTable.$converterrole);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sessionId, role, content, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id'])!,
      role: $MessagesTable.$converterrole.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!),
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MessageRole, String, String> $converterrole =
      const EnumNameConverter<MessageRole>(MessageRole.values);
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  const Message(
      {required this.id,
      required this.sessionId,
      required this.role,
      required this.content,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    {
      map['role'] = Variable<String>($MessagesTable.$converterrole.toSql(role));
    }
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      role: $MessagesTable.$converterrole
          .fromJson(serializer.fromJson<String>(json['role'])),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'role':
          serializer.toJson<String>($MessagesTable.$converterrole.toJson(role)),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith(
          {String? id,
          String? sessionId,
          MessageRole? role,
          String? content,
          DateTime? createdAt}) =>
      Message(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        role: role ?? this.role,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, role, content, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.content == this.content &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<MessageRole> role;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String sessionId,
    required MessageRole role,
    required String content,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        sessionId = Value(sessionId),
        role = Value(role),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? sessionId,
      Value<MessageRole>? role,
      Value<String>? content,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return MessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (role.present) {
      map['role'] =
          Variable<String>($MessagesTable.$converterrole.toSql(role.value));
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, Document> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sizeBytesMeta =
      const VerificationMeta('sizeBytes');
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
      'size_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _chunkCountMeta =
      const VerificationMeta('chunkCount');
  @override
  late final GeneratedColumn<int> chunkCount = GeneratedColumn<int>(
      'chunk_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _mimeTypeMeta =
      const VerificationMeta('mimeType');
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
      'mime_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES sessions (id) ON DELETE CASCADE'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _progressMeta =
      const VerificationMeta('progress');
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
      'progress', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        path,
        sizeBytes,
        chunkCount,
        mimeType,
        createdAt,
        sessionId,
        status,
        progress,
        errorMessage
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(Insertable<Document> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(_sizeBytesMeta,
          sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta));
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('chunk_count')) {
      context.handle(
          _chunkCountMeta,
          chunkCount.isAcceptableOrUnknown(
              data['chunk_count']!, _chunkCountMeta));
    }
    if (data.containsKey('mime_type')) {
      context.handle(_mimeTypeMeta,
          mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta));
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('progress')) {
      context.handle(_progressMeta,
          progress.isAcceptableOrUnknown(data['progress']!, _progressMeta));
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Document map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Document(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      sizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size_bytes'])!,
      chunkCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chunk_count'])!,
      mimeType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mime_type'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      progress: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}progress'])!,
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class Document extends DataClass implements Insertable<Document> {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final int chunkCount;
  final String mimeType;
  final DateTime createdAt;

  /// null = Global KB, non-null = Session-specific document
  final String? sessionId;

  /// IndexStatus enum: 0=pending, 1=processing, 2=completed, 3=failed
  final int status;

  /// Progress 0.0 → 1.0 trong pipeline indexing
  final double progress;

  /// Thông báo lỗi nếu status=failed
  final String? errorMessage;
  const Document(
      {required this.id,
      required this.name,
      required this.path,
      required this.sizeBytes,
      required this.chunkCount,
      required this.mimeType,
      required this.createdAt,
      this.sessionId,
      required this.status,
      required this.progress,
      this.errorMessage});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['path'] = Variable<String>(path);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['chunk_count'] = Variable<int>(chunkCount);
    map['mime_type'] = Variable<String>(mimeType);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['status'] = Variable<int>(status);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      name: Value(name),
      path: Value(path),
      sizeBytes: Value(sizeBytes),
      chunkCount: Value(chunkCount),
      mimeType: Value(mimeType),
      createdAt: Value(createdAt),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      status: Value(status),
      progress: Value(progress),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
    );
  }

  factory Document.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Document(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      path: serializer.fromJson<String>(json['path']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      chunkCount: serializer.fromJson<int>(json['chunkCount']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      status: serializer.fromJson<int>(json['status']),
      progress: serializer.fromJson<double>(json['progress']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'path': serializer.toJson<String>(path),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'chunkCount': serializer.toJson<int>(chunkCount),
      'mimeType': serializer.toJson<String>(mimeType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sessionId': serializer.toJson<String?>(sessionId),
      'status': serializer.toJson<int>(status),
      'progress': serializer.toJson<double>(progress),
      'errorMessage': serializer.toJson<String?>(errorMessage),
    };
  }

  Document copyWith(
          {String? id,
          String? name,
          String? path,
          int? sizeBytes,
          int? chunkCount,
          String? mimeType,
          DateTime? createdAt,
          Value<String?> sessionId = const Value.absent(),
          int? status,
          double? progress,
          Value<String?> errorMessage = const Value.absent()}) =>
      Document(
        id: id ?? this.id,
        name: name ?? this.name,
        path: path ?? this.path,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        chunkCount: chunkCount ?? this.chunkCount,
        mimeType: mimeType ?? this.mimeType,
        createdAt: createdAt ?? this.createdAt,
        sessionId: sessionId.present ? sessionId.value : this.sessionId,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
      );
  Document copyWithCompanion(DocumentsCompanion data) {
    return Document(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      path: data.path.present ? data.path.value : this.path,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      chunkCount:
          data.chunkCount.present ? data.chunkCount.value : this.chunkCount,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      status: data.status.present ? data.status.value : this.status,
      progress: data.progress.present ? data.progress.value : this.progress,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Document(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('path: $path, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('mimeType: $mimeType, ')
          ..write('createdAt: $createdAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, path, sizeBytes, chunkCount,
      mimeType, createdAt, sessionId, status, progress, errorMessage);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Document &&
          other.id == this.id &&
          other.name == this.name &&
          other.path == this.path &&
          other.sizeBytes == this.sizeBytes &&
          other.chunkCount == this.chunkCount &&
          other.mimeType == this.mimeType &&
          other.createdAt == this.createdAt &&
          other.sessionId == this.sessionId &&
          other.status == this.status &&
          other.progress == this.progress &&
          other.errorMessage == this.errorMessage);
}

class DocumentsCompanion extends UpdateCompanion<Document> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> path;
  final Value<int> sizeBytes;
  final Value<int> chunkCount;
  final Value<String> mimeType;
  final Value<DateTime> createdAt;
  final Value<String?> sessionId;
  final Value<int> status;
  final Value<double> progress;
  final Value<String?> errorMessage;
  final Value<int> rowid;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.path = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentsCompanion.insert({
    required String id,
    required String name,
    required String path,
    required int sizeBytes,
    this.chunkCount = const Value.absent(),
    required String mimeType,
    required DateTime createdAt,
    this.sessionId = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        path = Value(path),
        sizeBytes = Value(sizeBytes),
        mimeType = Value(mimeType),
        createdAt = Value(createdAt);
  static Insertable<Document> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? path,
    Expression<int>? sizeBytes,
    Expression<int>? chunkCount,
    Expression<String>? mimeType,
    Expression<DateTime>? createdAt,
    Expression<String>? sessionId,
    Expression<int>? status,
    Expression<double>? progress,
    Expression<String>? errorMessage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (path != null) 'path': path,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (mimeType != null) 'mime_type': mimeType,
      if (createdAt != null) 'created_at': createdAt,
      if (sessionId != null) 'session_id': sessionId,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (errorMessage != null) 'error_message': errorMessage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? path,
      Value<int>? sizeBytes,
      Value<int>? chunkCount,
      Value<String>? mimeType,
      Value<DateTime>? createdAt,
      Value<String?>? sessionId,
      Value<int>? status,
      Value<double>? progress,
      Value<String?>? errorMessage,
      Value<int>? rowid}) {
    return DocumentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      chunkCount: chunkCount ?? this.chunkCount,
      mimeType: mimeType ?? this.mimeType,
      createdAt: createdAt ?? this.createdAt,
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (chunkCount.present) {
      map['chunk_count'] = Variable<int>(chunkCount.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('path: $path, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('mimeType: $mimeType, ')
          ..write('createdAt: $createdAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChunksTable extends Chunks with TableInfo<$ChunksTable, Chunk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _documentIdMeta =
      const VerificationMeta('documentId');
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
      'document_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES documents (id) ON DELETE CASCADE'));
  static const VerificationMeta _chunkTextMeta =
      const VerificationMeta('chunkText');
  @override
  late final GeneratedColumn<String> chunkText = GeneratedColumn<String>(
      'chunk_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _chunkIndexMeta =
      const VerificationMeta('chunkIndex');
  @override
  late final GeneratedColumn<int> chunkIndex = GeneratedColumn<int>(
      'chunk_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _tokenCountMeta =
      const VerificationMeta('tokenCount');
  @override
  late final GeneratedColumn<int> tokenCount = GeneratedColumn<int>(
      'token_count', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, documentId, chunkText, chunkIndex, tokenCount, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chunks';
  @override
  VerificationContext validateIntegrity(Insertable<Chunk> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
          _documentIdMeta,
          documentId.isAcceptableOrUnknown(
              data['document_id']!, _documentIdMeta));
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('chunk_text')) {
      context.handle(_chunkTextMeta,
          chunkText.isAcceptableOrUnknown(data['chunk_text']!, _chunkTextMeta));
    } else if (isInserting) {
      context.missing(_chunkTextMeta);
    }
    if (data.containsKey('chunk_index')) {
      context.handle(
          _chunkIndexMeta,
          chunkIndex.isAcceptableOrUnknown(
              data['chunk_index']!, _chunkIndexMeta));
    } else if (isInserting) {
      context.missing(_chunkIndexMeta);
    }
    if (data.containsKey('token_count')) {
      context.handle(
          _tokenCountMeta,
          tokenCount.isAcceptableOrUnknown(
              data['token_count']!, _tokenCountMeta));
    } else if (isInserting) {
      context.missing(_tokenCountMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chunk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chunk(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      documentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}document_id'])!,
      chunkText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chunk_text'])!,
      chunkIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chunk_index'])!,
      tokenCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}token_count'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ChunksTable createAlias(String alias) {
    return $ChunksTable(attachedDatabase, alias);
  }
}

class Chunk extends DataClass implements Insertable<Chunk> {
  final String id;
  final String documentId;
  final String chunkText;
  final int chunkIndex;
  final int tokenCount;
  final DateTime createdAt;
  const Chunk(
      {required this.id,
      required this.documentId,
      required this.chunkText,
      required this.chunkIndex,
      required this.tokenCount,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['document_id'] = Variable<String>(documentId);
    map['chunk_text'] = Variable<String>(chunkText);
    map['chunk_index'] = Variable<int>(chunkIndex);
    map['token_count'] = Variable<int>(tokenCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChunksCompanion toCompanion(bool nullToAbsent) {
    return ChunksCompanion(
      id: Value(id),
      documentId: Value(documentId),
      chunkText: Value(chunkText),
      chunkIndex: Value(chunkIndex),
      tokenCount: Value(tokenCount),
      createdAt: Value(createdAt),
    );
  }

  factory Chunk.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chunk(
      id: serializer.fromJson<String>(json['id']),
      documentId: serializer.fromJson<String>(json['documentId']),
      chunkText: serializer.fromJson<String>(json['chunkText']),
      chunkIndex: serializer.fromJson<int>(json['chunkIndex']),
      tokenCount: serializer.fromJson<int>(json['tokenCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'documentId': serializer.toJson<String>(documentId),
      'chunkText': serializer.toJson<String>(chunkText),
      'chunkIndex': serializer.toJson<int>(chunkIndex),
      'tokenCount': serializer.toJson<int>(tokenCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Chunk copyWith(
          {String? id,
          String? documentId,
          String? chunkText,
          int? chunkIndex,
          int? tokenCount,
          DateTime? createdAt}) =>
      Chunk(
        id: id ?? this.id,
        documentId: documentId ?? this.documentId,
        chunkText: chunkText ?? this.chunkText,
        chunkIndex: chunkIndex ?? this.chunkIndex,
        tokenCount: tokenCount ?? this.tokenCount,
        createdAt: createdAt ?? this.createdAt,
      );
  Chunk copyWithCompanion(ChunksCompanion data) {
    return Chunk(
      id: data.id.present ? data.id.value : this.id,
      documentId:
          data.documentId.present ? data.documentId.value : this.documentId,
      chunkText: data.chunkText.present ? data.chunkText.value : this.chunkText,
      chunkIndex:
          data.chunkIndex.present ? data.chunkIndex.value : this.chunkIndex,
      tokenCount:
          data.tokenCount.present ? data.tokenCount.value : this.tokenCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chunk(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('chunkText: $chunkText, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('tokenCount: $tokenCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, documentId, chunkText, chunkIndex, tokenCount, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chunk &&
          other.id == this.id &&
          other.documentId == this.documentId &&
          other.chunkText == this.chunkText &&
          other.chunkIndex == this.chunkIndex &&
          other.tokenCount == this.tokenCount &&
          other.createdAt == this.createdAt);
}

class ChunksCompanion extends UpdateCompanion<Chunk> {
  final Value<String> id;
  final Value<String> documentId;
  final Value<String> chunkText;
  final Value<int> chunkIndex;
  final Value<int> tokenCount;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ChunksCompanion({
    this.id = const Value.absent(),
    this.documentId = const Value.absent(),
    this.chunkText = const Value.absent(),
    this.chunkIndex = const Value.absent(),
    this.tokenCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChunksCompanion.insert({
    required String id,
    required String documentId,
    required String chunkText,
    required int chunkIndex,
    required int tokenCount,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        documentId = Value(documentId),
        chunkText = Value(chunkText),
        chunkIndex = Value(chunkIndex),
        tokenCount = Value(tokenCount),
        createdAt = Value(createdAt);
  static Insertable<Chunk> custom({
    Expression<String>? id,
    Expression<String>? documentId,
    Expression<String>? chunkText,
    Expression<int>? chunkIndex,
    Expression<int>? tokenCount,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (documentId != null) 'document_id': documentId,
      if (chunkText != null) 'chunk_text': chunkText,
      if (chunkIndex != null) 'chunk_index': chunkIndex,
      if (tokenCount != null) 'token_count': tokenCount,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChunksCompanion copyWith(
      {Value<String>? id,
      Value<String>? documentId,
      Value<String>? chunkText,
      Value<int>? chunkIndex,
      Value<int>? tokenCount,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ChunksCompanion(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      chunkText: chunkText ?? this.chunkText,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      tokenCount: tokenCount ?? this.tokenCount,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (chunkText.present) {
      map['chunk_text'] = Variable<String>(chunkText.value);
    }
    if (chunkIndex.present) {
      map['chunk_index'] = Variable<int>(chunkIndex.value);
    }
    if (tokenCount.present) {
      map['token_count'] = Variable<int>(tokenCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChunksCompanion(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('chunkText: $chunkText, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('tokenCount: $tokenCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VectorsTable extends Vectors with TableInfo<$VectorsTable, Vector> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VectorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _chunkIdMeta =
      const VerificationMeta('chunkId');
  @override
  late final GeneratedColumn<String> chunkId = GeneratedColumn<String>(
      'chunk_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES chunks (id) ON DELETE CASCADE'));
  static const VerificationMeta _embeddingMeta =
      const VerificationMeta('embedding');
  @override
  late final GeneratedColumn<Uint8List> embedding = GeneratedColumn<Uint8List>(
      'embedding', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, chunkId, embedding, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vectors';
  @override
  VerificationContext validateIntegrity(Insertable<Vector> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chunk_id')) {
      context.handle(_chunkIdMeta,
          chunkId.isAcceptableOrUnknown(data['chunk_id']!, _chunkIdMeta));
    } else if (isInserting) {
      context.missing(_chunkIdMeta);
    }
    if (data.containsKey('embedding')) {
      context.handle(_embeddingMeta,
          embedding.isAcceptableOrUnknown(data['embedding']!, _embeddingMeta));
    } else if (isInserting) {
      context.missing(_embeddingMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Vector map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Vector(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      chunkId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chunk_id'])!,
      embedding: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}embedding'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $VectorsTable createAlias(String alias) {
    return $VectorsTable(attachedDatabase, alias);
  }
}

class Vector extends DataClass implements Insertable<Vector> {
  final String id;
  final String chunkId;
  final Uint8List embedding;
  final DateTime createdAt;
  const Vector(
      {required this.id,
      required this.chunkId,
      required this.embedding,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['chunk_id'] = Variable<String>(chunkId);
    map['embedding'] = Variable<Uint8List>(embedding);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  VectorsCompanion toCompanion(bool nullToAbsent) {
    return VectorsCompanion(
      id: Value(id),
      chunkId: Value(chunkId),
      embedding: Value(embedding),
      createdAt: Value(createdAt),
    );
  }

  factory Vector.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Vector(
      id: serializer.fromJson<String>(json['id']),
      chunkId: serializer.fromJson<String>(json['chunkId']),
      embedding: serializer.fromJson<Uint8List>(json['embedding']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'chunkId': serializer.toJson<String>(chunkId),
      'embedding': serializer.toJson<Uint8List>(embedding),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Vector copyWith(
          {String? id,
          String? chunkId,
          Uint8List? embedding,
          DateTime? createdAt}) =>
      Vector(
        id: id ?? this.id,
        chunkId: chunkId ?? this.chunkId,
        embedding: embedding ?? this.embedding,
        createdAt: createdAt ?? this.createdAt,
      );
  Vector copyWithCompanion(VectorsCompanion data) {
    return Vector(
      id: data.id.present ? data.id.value : this.id,
      chunkId: data.chunkId.present ? data.chunkId.value : this.chunkId,
      embedding: data.embedding.present ? data.embedding.value : this.embedding,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Vector(')
          ..write('id: $id, ')
          ..write('chunkId: $chunkId, ')
          ..write('embedding: $embedding, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, chunkId, $driftBlobEquality.hash(embedding), createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Vector &&
          other.id == this.id &&
          other.chunkId == this.chunkId &&
          $driftBlobEquality.equals(other.embedding, this.embedding) &&
          other.createdAt == this.createdAt);
}

class VectorsCompanion extends UpdateCompanion<Vector> {
  final Value<String> id;
  final Value<String> chunkId;
  final Value<Uint8List> embedding;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const VectorsCompanion({
    this.id = const Value.absent(),
    this.chunkId = const Value.absent(),
    this.embedding = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VectorsCompanion.insert({
    required String id,
    required String chunkId,
    required Uint8List embedding,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        chunkId = Value(chunkId),
        embedding = Value(embedding),
        createdAt = Value(createdAt);
  static Insertable<Vector> custom({
    Expression<String>? id,
    Expression<String>? chunkId,
    Expression<Uint8List>? embedding,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (chunkId != null) 'chunk_id': chunkId,
      if (embedding != null) 'embedding': embedding,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VectorsCompanion copyWith(
      {Value<String>? id,
      Value<String>? chunkId,
      Value<Uint8List>? embedding,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return VectorsCompanion(
      id: id ?? this.id,
      chunkId: chunkId ?? this.chunkId,
      embedding: embedding ?? this.embedding,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (chunkId.present) {
      map['chunk_id'] = Variable<String>(chunkId.value);
    }
    if (embedding.present) {
      map['embedding'] = Variable<Uint8List>(embedding.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VectorsCompanion(')
          ..write('id: $id, ')
          ..write('chunkId: $chunkId, ')
          ..write('embedding: $embedding, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionMemoryTable extends SessionMemory
    with TableInfo<$SessionMemoryTable, SessionMemoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionMemoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES sessions (id) ON UPDATE CASCADE ON DELETE CASCADE'));
  static const VerificationMeta _summaryMeta =
      const VerificationMeta('summary');
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
      'summary', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _summaryVersionMeta =
      const VerificationMeta('summaryVersion');
  @override
  late final GeneratedColumn<int> summaryVersion = GeneratedColumn<int>(
      'summary_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _msgCountMeta =
      const VerificationMeta('msgCount');
  @override
  late final GeneratedColumn<int> msgCount = GeneratedColumn<int>(
      'msg_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _estTokensMeta =
      const VerificationMeta('estTokens');
  @override
  late final GeneratedColumn<int> estTokens = GeneratedColumn<int>(
      'est_tokens', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _runningTokenCountMeta =
      const VerificationMeta('runningTokenCount');
  @override
  late final GeneratedColumn<int> runningTokenCount = GeneratedColumn<int>(
      'running_token_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        sessionId,
        summary,
        summaryVersion,
        msgCount,
        estTokens,
        runningTokenCount,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_memory';
  @override
  VerificationContext validateIntegrity(Insertable<SessionMemoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(_summaryMeta,
          summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta));
    }
    if (data.containsKey('summary_version')) {
      context.handle(
          _summaryVersionMeta,
          summaryVersion.isAcceptableOrUnknown(
              data['summary_version']!, _summaryVersionMeta));
    }
    if (data.containsKey('msg_count')) {
      context.handle(_msgCountMeta,
          msgCount.isAcceptableOrUnknown(data['msg_count']!, _msgCountMeta));
    }
    if (data.containsKey('est_tokens')) {
      context.handle(_estTokensMeta,
          estTokens.isAcceptableOrUnknown(data['est_tokens']!, _estTokensMeta));
    }
    if (data.containsKey('running_token_count')) {
      context.handle(
          _runningTokenCountMeta,
          runningTokenCount.isAcceptableOrUnknown(
              data['running_token_count']!, _runningTokenCountMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  SessionMemoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionMemoryData(
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id'])!,
      summary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary']),
      summaryVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}summary_version'])!,
      msgCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}msg_count'])!,
      estTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}est_tokens'])!,
      runningTokenCount: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}running_token_count'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SessionMemoryTable createAlias(String alias) {
    return $SessionMemoryTable(attachedDatabase, alias);
  }
}

class SessionMemoryData extends DataClass
    implements Insertable<SessionMemoryData> {
  final String sessionId;
  final String? summary;
  final int summaryVersion;
  final int msgCount;
  final int estTokens;
  final int runningTokenCount;
  final DateTime updatedAt;
  const SessionMemoryData(
      {required this.sessionId,
      this.summary,
      required this.summaryVersion,
      required this.msgCount,
      required this.estTokens,
      required this.runningTokenCount,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    map['summary_version'] = Variable<int>(summaryVersion);
    map['msg_count'] = Variable<int>(msgCount);
    map['est_tokens'] = Variable<int>(estTokens);
    map['running_token_count'] = Variable<int>(runningTokenCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SessionMemoryCompanion toCompanion(bool nullToAbsent) {
    return SessionMemoryCompanion(
      sessionId: Value(sessionId),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      summaryVersion: Value(summaryVersion),
      msgCount: Value(msgCount),
      estTokens: Value(estTokens),
      runningTokenCount: Value(runningTokenCount),
      updatedAt: Value(updatedAt),
    );
  }

  factory SessionMemoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionMemoryData(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      summary: serializer.fromJson<String?>(json['summary']),
      summaryVersion: serializer.fromJson<int>(json['summaryVersion']),
      msgCount: serializer.fromJson<int>(json['msgCount']),
      estTokens: serializer.fromJson<int>(json['estTokens']),
      runningTokenCount: serializer.fromJson<int>(json['runningTokenCount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'summary': serializer.toJson<String?>(summary),
      'summaryVersion': serializer.toJson<int>(summaryVersion),
      'msgCount': serializer.toJson<int>(msgCount),
      'estTokens': serializer.toJson<int>(estTokens),
      'runningTokenCount': serializer.toJson<int>(runningTokenCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SessionMemoryData copyWith(
          {String? sessionId,
          Value<String?> summary = const Value.absent(),
          int? summaryVersion,
          int? msgCount,
          int? estTokens,
          int? runningTokenCount,
          DateTime? updatedAt}) =>
      SessionMemoryData(
        sessionId: sessionId ?? this.sessionId,
        summary: summary.present ? summary.value : this.summary,
        summaryVersion: summaryVersion ?? this.summaryVersion,
        msgCount: msgCount ?? this.msgCount,
        estTokens: estTokens ?? this.estTokens,
        runningTokenCount: runningTokenCount ?? this.runningTokenCount,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SessionMemoryData copyWithCompanion(SessionMemoryCompanion data) {
    return SessionMemoryData(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      summary: data.summary.present ? data.summary.value : this.summary,
      summaryVersion: data.summaryVersion.present
          ? data.summaryVersion.value
          : this.summaryVersion,
      msgCount: data.msgCount.present ? data.msgCount.value : this.msgCount,
      estTokens: data.estTokens.present ? data.estTokens.value : this.estTokens,
      runningTokenCount: data.runningTokenCount.present
          ? data.runningTokenCount.value
          : this.runningTokenCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionMemoryData(')
          ..write('sessionId: $sessionId, ')
          ..write('summary: $summary, ')
          ..write('summaryVersion: $summaryVersion, ')
          ..write('msgCount: $msgCount, ')
          ..write('estTokens: $estTokens, ')
          ..write('runningTokenCount: $runningTokenCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, summary, summaryVersion, msgCount,
      estTokens, runningTokenCount, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionMemoryData &&
          other.sessionId == this.sessionId &&
          other.summary == this.summary &&
          other.summaryVersion == this.summaryVersion &&
          other.msgCount == this.msgCount &&
          other.estTokens == this.estTokens &&
          other.runningTokenCount == this.runningTokenCount &&
          other.updatedAt == this.updatedAt);
}

class SessionMemoryCompanion extends UpdateCompanion<SessionMemoryData> {
  final Value<String> sessionId;
  final Value<String?> summary;
  final Value<int> summaryVersion;
  final Value<int> msgCount;
  final Value<int> estTokens;
  final Value<int> runningTokenCount;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SessionMemoryCompanion({
    this.sessionId = const Value.absent(),
    this.summary = const Value.absent(),
    this.summaryVersion = const Value.absent(),
    this.msgCount = const Value.absent(),
    this.estTokens = const Value.absent(),
    this.runningTokenCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionMemoryCompanion.insert({
    required String sessionId,
    this.summary = const Value.absent(),
    this.summaryVersion = const Value.absent(),
    this.msgCount = const Value.absent(),
    this.estTokens = const Value.absent(),
    this.runningTokenCount = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : sessionId = Value(sessionId),
        updatedAt = Value(updatedAt);
  static Insertable<SessionMemoryData> custom({
    Expression<String>? sessionId,
    Expression<String>? summary,
    Expression<int>? summaryVersion,
    Expression<int>? msgCount,
    Expression<int>? estTokens,
    Expression<int>? runningTokenCount,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (summary != null) 'summary': summary,
      if (summaryVersion != null) 'summary_version': summaryVersion,
      if (msgCount != null) 'msg_count': msgCount,
      if (estTokens != null) 'est_tokens': estTokens,
      if (runningTokenCount != null) 'running_token_count': runningTokenCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionMemoryCompanion copyWith(
      {Value<String>? sessionId,
      Value<String?>? summary,
      Value<int>? summaryVersion,
      Value<int>? msgCount,
      Value<int>? estTokens,
      Value<int>? runningTokenCount,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SessionMemoryCompanion(
      sessionId: sessionId ?? this.sessionId,
      summary: summary ?? this.summary,
      summaryVersion: summaryVersion ?? this.summaryVersion,
      msgCount: msgCount ?? this.msgCount,
      estTokens: estTokens ?? this.estTokens,
      runningTokenCount: runningTokenCount ?? this.runningTokenCount,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (summaryVersion.present) {
      map['summary_version'] = Variable<int>(summaryVersion.value);
    }
    if (msgCount.present) {
      map['msg_count'] = Variable<int>(msgCount.value);
    }
    if (estTokens.present) {
      map['est_tokens'] = Variable<int>(estTokens.value);
    }
    if (runningTokenCount.present) {
      map['running_token_count'] = Variable<int>(runningTokenCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionMemoryCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('summary: $summary, ')
          ..write('summaryVersion: $summaryVersion, ')
          ..write('msgCount: $msgCount, ')
          ..write('estTokens: $estTokens, ')
          ..write('runningTokenCount: $runningTokenCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserMemoryTable extends UserMemory
    with TableInfo<$UserMemoryTable, UserMemoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserMemoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _namespaceMeta =
      const VerificationMeta('namespace');
  @override
  late final GeneratedColumn<String> namespace = GeneratedColumn<String>(
      'namespace', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [namespace, key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_memory';
  @override
  VerificationContext validateIntegrity(Insertable<UserMemoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('namespace')) {
      context.handle(_namespaceMeta,
          namespace.isAcceptableOrUnknown(data['namespace']!, _namespaceMeta));
    } else if (isInserting) {
      context.missing(_namespaceMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {namespace, key};
  @override
  UserMemoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserMemoryData(
      namespace: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}namespace'])!,
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $UserMemoryTable createAlias(String alias) {
    return $UserMemoryTable(attachedDatabase, alias);
  }
}

class UserMemoryData extends DataClass implements Insertable<UserMemoryData> {
  final String namespace;
  final String key;
  final String value;
  final DateTime updatedAt;
  const UserMemoryData(
      {required this.namespace,
      required this.key,
      required this.value,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['namespace'] = Variable<String>(namespace);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UserMemoryCompanion toCompanion(bool nullToAbsent) {
    return UserMemoryCompanion(
      namespace: Value(namespace),
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory UserMemoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserMemoryData(
      namespace: serializer.fromJson<String>(json['namespace']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'namespace': serializer.toJson<String>(namespace),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  UserMemoryData copyWith(
          {String? namespace,
          String? key,
          String? value,
          DateTime? updatedAt}) =>
      UserMemoryData(
        namespace: namespace ?? this.namespace,
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  UserMemoryData copyWithCompanion(UserMemoryCompanion data) {
    return UserMemoryData(
      namespace: data.namespace.present ? data.namespace.value : this.namespace,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserMemoryData(')
          ..write('namespace: $namespace, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(namespace, key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserMemoryData &&
          other.namespace == this.namespace &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class UserMemoryCompanion extends UpdateCompanion<UserMemoryData> {
  final Value<String> namespace;
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UserMemoryCompanion({
    this.namespace = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserMemoryCompanion.insert({
    required String namespace,
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : namespace = Value(namespace),
        key = Value(key),
        value = Value(value),
        updatedAt = Value(updatedAt);
  static Insertable<UserMemoryData> custom({
    Expression<String>? namespace,
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (namespace != null) 'namespace': namespace,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserMemoryCompanion copyWith(
      {Value<String>? namespace,
      Value<String>? key,
      Value<String>? value,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return UserMemoryCompanion(
      namespace: namespace ?? this.namespace,
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (namespace.present) {
      map['namespace'] = Variable<String>(namespace.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserMemoryCompanion(')
          ..write('namespace: $namespace, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $ChunksTable chunks = $ChunksTable(this);
  late final $VectorsTable vectors = $VectorsTable(this);
  late final $SessionMemoryTable sessionMemory = $SessionMemoryTable(this);
  late final $UserMemoryTable userMemory = $UserMemoryTable(this);
  late final SessionsDao sessionsDao = SessionsDao(this as AppDatabase);
  late final MessagesDao messagesDao = MessagesDao(this as AppDatabase);
  late final DocumentsDao documentsDao = DocumentsDao(this as AppDatabase);
  late final ChunksDao chunksDao = ChunksDao(this as AppDatabase);
  late final VectorsDao vectorsDao = VectorsDao(this as AppDatabase);
  late final SessionMemoryDao sessionMemoryDao =
      SessionMemoryDao(this as AppDatabase);
  late final UserMemoryDao userMemoryDao = UserMemoryDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        sessions,
        messages,
        documents,
        chunks,
        vectors,
        sessionMemory,
        userMemory
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('sessions',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('documents', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('documents',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('chunks', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('chunks',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('vectors', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('sessions',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('session_memory', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('sessions',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('session_memory', kind: UpdateKind.update),
            ],
          ),
        ],
      );
}

typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  required String id,
  required String title,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> knowledgeScope,
  Value<int> rowid,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> knowledgeScope,
  Value<int> rowid,
});

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.messages,
          aliasName:
              $_aliasNameGenerator(db.sessions.id, db.messages.sessionId));

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager($_db, $_db.messages)
        .filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$DocumentsTable, List<Document>>
      _documentsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.documents,
              aliasName:
                  $_aliasNameGenerator(db.sessions.id, db.documents.sessionId));

  $$DocumentsTableProcessedTableManager get documentsRefs {
    final manager = $$DocumentsTableTableManager($_db, $_db.documents)
        .filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_documentsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SessionMemoryTable, List<SessionMemoryData>>
      _sessionMemoryRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.sessionMemory,
              aliasName: $_aliasNameGenerator(
                  db.sessions.id, db.sessionMemory.sessionId));

  $$SessionMemoryTableProcessedTableManager get sessionMemoryRefs {
    final manager = $$SessionMemoryTableTableManager($_db, $_db.sessionMemory)
        .filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionMemoryRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get knowledgeScope => $composableBuilder(
      column: $table.knowledgeScope,
      builder: (column) => ColumnFilters(column));

  Expression<bool> messagesRefs(
      Expression<bool> Function($$MessagesTableFilterComposer f) f) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableFilterComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> documentsRefs(
      Expression<bool> Function($$DocumentsTableFilterComposer f) f) {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.documents,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocumentsTableFilterComposer(
              $db: $db,
              $table: $db.documents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> sessionMemoryRefs(
      Expression<bool> Function($$SessionMemoryTableFilterComposer f) f) {
    final $$SessionMemoryTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sessionMemory,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionMemoryTableFilterComposer(
              $db: $db,
              $table: $db.sessionMemory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get knowledgeScope => $composableBuilder(
      column: $table.knowledgeScope,
      builder: (column) => ColumnOrderings(column));
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get knowledgeScope => $composableBuilder(
      column: $table.knowledgeScope, builder: (column) => column);

  Expression<T> messagesRefs<T extends Object>(
      Expression<T> Function($$MessagesTableAnnotationComposer a) f) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableAnnotationComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> documentsRefs<T extends Object>(
      Expression<T> Function($$DocumentsTableAnnotationComposer a) f) {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.documents,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocumentsTableAnnotationComposer(
              $db: $db,
              $table: $db.documents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> sessionMemoryRefs<T extends Object>(
      Expression<T> Function($$SessionMemoryTableAnnotationComposer a) f) {
    final $$SessionMemoryTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sessionMemory,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionMemoryTableAnnotationComposer(
              $db: $db,
              $table: $db.sessionMemory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SessionsTable,
    Session,
    $$SessionsTableFilterComposer,
    $$SessionsTableOrderingComposer,
    $$SessionsTableAnnotationComposer,
    $$SessionsTableCreateCompanionBuilder,
    $$SessionsTableUpdateCompanionBuilder,
    (Session, $$SessionsTableReferences),
    Session,
    PrefetchHooks Function(
        {bool messagesRefs, bool documentsRefs, bool sessionMemoryRefs})> {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> knowledgeScope = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SessionsCompanion(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            knowledgeScope: knowledgeScope,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> knowledgeScope = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SessionsCompanion.insert(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            knowledgeScope: knowledgeScope,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SessionsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {messagesRefs = false,
              documentsRefs = false,
              sessionMemoryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (messagesRefs) db.messages,
                if (documentsRefs) db.documents,
                if (sessionMemoryRefs) db.sessionMemory
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedData<Session, $SessionsTable, Message>(
                        currentTable: table,
                        referencedTable:
                            $$SessionsTableReferences._messagesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SessionsTableReferences(db, table, p0)
                                .messagesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sessionId == item.id),
                        typedResults: items),
                  if (documentsRefs)
                    await $_getPrefetchedData<Session, $SessionsTable,
                            Document>(
                        currentTable: table,
                        referencedTable:
                            $$SessionsTableReferences._documentsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SessionsTableReferences(db, table, p0)
                                .documentsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sessionId == item.id),
                        typedResults: items),
                  if (sessionMemoryRefs)
                    await $_getPrefetchedData<Session, $SessionsTable,
                            SessionMemoryData>(
                        currentTable: table,
                        referencedTable: $$SessionsTableReferences
                            ._sessionMemoryRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SessionsTableReferences(db, table, p0)
                                .sessionMemoryRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sessionId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SessionsTable,
    Session,
    $$SessionsTableFilterComposer,
    $$SessionsTableOrderingComposer,
    $$SessionsTableAnnotationComposer,
    $$SessionsTableCreateCompanionBuilder,
    $$SessionsTableUpdateCompanionBuilder,
    (Session, $$SessionsTableReferences),
    Session,
    PrefetchHooks Function(
        {bool messagesRefs, bool documentsRefs, bool sessionMemoryRefs})>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String sessionId,
  required MessageRole role,
  required String content,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> sessionId,
  Value<MessageRole> role,
  Value<String> content,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) => db.sessions
      .createAlias($_aliasNameGenerator(db.messages.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager($_db, $_db.sessions)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<MessageRole, MessageRole, String> get role =>
      $composableBuilder(
          column: $table.role,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableFilterComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableOrderingComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MessageRole, String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, $$MessagesTableReferences),
    Message,
    PrefetchHooks Function({bool sessionId})> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> sessionId = const Value.absent(),
            Value<MessageRole> role = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String sessionId,
            required MessageRole role,
            required String content,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$MessagesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$MessagesTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$MessagesTableReferences._sessionIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, $$MessagesTableReferences),
    Message,
    PrefetchHooks Function({bool sessionId})>;
typedef $$DocumentsTableCreateCompanionBuilder = DocumentsCompanion Function({
  required String id,
  required String name,
  required String path,
  required int sizeBytes,
  Value<int> chunkCount,
  required String mimeType,
  required DateTime createdAt,
  Value<String?> sessionId,
  Value<int> status,
  Value<double> progress,
  Value<String?> errorMessage,
  Value<int> rowid,
});
typedef $$DocumentsTableUpdateCompanionBuilder = DocumentsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> path,
  Value<int> sizeBytes,
  Value<int> chunkCount,
  Value<String> mimeType,
  Value<DateTime> createdAt,
  Value<String?> sessionId,
  Value<int> status,
  Value<double> progress,
  Value<String?> errorMessage,
  Value<int> rowid,
});

final class $$DocumentsTableReferences
    extends BaseReferences<_$AppDatabase, $DocumentsTable, Document> {
  $$DocumentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
          $_aliasNameGenerator(db.documents.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager? get sessionId {
    final $_column = $_itemColumn<String>('session_id');
    if ($_column == null) return null;
    final manager = $$SessionsTableTableManager($_db, $_db.sessions)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$ChunksTable, List<Chunk>> _chunksRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.chunks,
          aliasName:
              $_aliasNameGenerator(db.documents.id, db.chunks.documentId));

  $$ChunksTableProcessedTableManager get chunksRefs {
    final manager = $$ChunksTableTableManager($_db, $_db.chunks)
        .filter((f) => f.documentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chunksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$DocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get chunkCount => $composableBuilder(
      column: $table.chunkCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get progress => $composableBuilder(
      column: $table.progress, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableFilterComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> chunksRefs(
      Expression<bool> Function($$ChunksTableFilterComposer f) f) {
    final $$ChunksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.chunks,
        getReferencedColumn: (t) => t.documentId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChunksTableFilterComposer(
              $db: $db,
              $table: $db.chunks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get chunkCount => $composableBuilder(
      column: $table.chunkCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get progress => $composableBuilder(
      column: $table.progress, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableOrderingComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get chunkCount => $composableBuilder(
      column: $table.chunkCount, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> chunksRefs<T extends Object>(
      Expression<T> Function($$ChunksTableAnnotationComposer a) f) {
    final $$ChunksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.chunks,
        getReferencedColumn: (t) => t.documentId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChunksTableAnnotationComposer(
              $db: $db,
              $table: $db.chunks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DocumentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DocumentsTable,
    Document,
    $$DocumentsTableFilterComposer,
    $$DocumentsTableOrderingComposer,
    $$DocumentsTableAnnotationComposer,
    $$DocumentsTableCreateCompanionBuilder,
    $$DocumentsTableUpdateCompanionBuilder,
    (Document, $$DocumentsTableReferences),
    Document,
    PrefetchHooks Function({bool sessionId, bool chunksRefs})> {
  $$DocumentsTableTableManager(_$AppDatabase db, $DocumentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> path = const Value.absent(),
            Value<int> sizeBytes = const Value.absent(),
            Value<int> chunkCount = const Value.absent(),
            Value<String> mimeType = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> sessionId = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<double> progress = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DocumentsCompanion(
            id: id,
            name: name,
            path: path,
            sizeBytes: sizeBytes,
            chunkCount: chunkCount,
            mimeType: mimeType,
            createdAt: createdAt,
            sessionId: sessionId,
            status: status,
            progress: progress,
            errorMessage: errorMessage,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String path,
            required int sizeBytes,
            Value<int> chunkCount = const Value.absent(),
            required String mimeType,
            required DateTime createdAt,
            Value<String?> sessionId = const Value.absent(),
            Value<int> status = const Value.absent(),
            Value<double> progress = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DocumentsCompanion.insert(
            id: id,
            name: name,
            path: path,
            sizeBytes: sizeBytes,
            chunkCount: chunkCount,
            mimeType: mimeType,
            createdAt: createdAt,
            sessionId: sessionId,
            status: status,
            progress: progress,
            errorMessage: errorMessage,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DocumentsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({sessionId = false, chunksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (chunksRefs) db.chunks],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$DocumentsTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$DocumentsTableReferences._sessionIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (chunksRefs)
                    await $_getPrefetchedData<Document, $DocumentsTable, Chunk>(
                        currentTable: table,
                        referencedTable:
                            $$DocumentsTableReferences._chunksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$DocumentsTableReferences(db, table, p0)
                                .chunksRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.documentId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$DocumentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DocumentsTable,
    Document,
    $$DocumentsTableFilterComposer,
    $$DocumentsTableOrderingComposer,
    $$DocumentsTableAnnotationComposer,
    $$DocumentsTableCreateCompanionBuilder,
    $$DocumentsTableUpdateCompanionBuilder,
    (Document, $$DocumentsTableReferences),
    Document,
    PrefetchHooks Function({bool sessionId, bool chunksRefs})>;
typedef $$ChunksTableCreateCompanionBuilder = ChunksCompanion Function({
  required String id,
  required String documentId,
  required String chunkText,
  required int chunkIndex,
  required int tokenCount,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$ChunksTableUpdateCompanionBuilder = ChunksCompanion Function({
  Value<String> id,
  Value<String> documentId,
  Value<String> chunkText,
  Value<int> chunkIndex,
  Value<int> tokenCount,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$ChunksTableReferences
    extends BaseReferences<_$AppDatabase, $ChunksTable, Chunk> {
  $$ChunksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DocumentsTable _documentIdTable(_$AppDatabase db) => db.documents
      .createAlias($_aliasNameGenerator(db.chunks.documentId, db.documents.id));

  $$DocumentsTableProcessedTableManager get documentId {
    final $_column = $_itemColumn<String>('document_id')!;

    final manager = $$DocumentsTableTableManager($_db, $_db.documents)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_documentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$VectorsTable, List<Vector>> _vectorsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.vectors,
          aliasName: $_aliasNameGenerator(db.chunks.id, db.vectors.chunkId));

  $$VectorsTableProcessedTableManager get vectorsRefs {
    final manager = $$VectorsTableTableManager($_db, $_db.vectors)
        .filter((f) => f.chunkId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_vectorsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ChunksTableFilterComposer
    extends Composer<_$AppDatabase, $ChunksTable> {
  $$ChunksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chunkText => $composableBuilder(
      column: $table.chunkText, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get chunkIndex => $composableBuilder(
      column: $table.chunkIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get tokenCount => $composableBuilder(
      column: $table.tokenCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$DocumentsTableFilterComposer get documentId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentId,
        referencedTable: $db.documents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocumentsTableFilterComposer(
              $db: $db,
              $table: $db.documents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> vectorsRefs(
      Expression<bool> Function($$VectorsTableFilterComposer f) f) {
    final $$VectorsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.vectors,
        getReferencedColumn: (t) => t.chunkId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$VectorsTableFilterComposer(
              $db: $db,
              $table: $db.vectors,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ChunksTableOrderingComposer
    extends Composer<_$AppDatabase, $ChunksTable> {
  $$ChunksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chunkText => $composableBuilder(
      column: $table.chunkText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get chunkIndex => $composableBuilder(
      column: $table.chunkIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get tokenCount => $composableBuilder(
      column: $table.tokenCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$DocumentsTableOrderingComposer get documentId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentId,
        referencedTable: $db.documents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocumentsTableOrderingComposer(
              $db: $db,
              $table: $db.documents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ChunksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChunksTable> {
  $$ChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get chunkText =>
      $composableBuilder(column: $table.chunkText, builder: (column) => column);

  GeneratedColumn<int> get chunkIndex => $composableBuilder(
      column: $table.chunkIndex, builder: (column) => column);

  GeneratedColumn<int> get tokenCount => $composableBuilder(
      column: $table.tokenCount, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$DocumentsTableAnnotationComposer get documentId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.documentId,
        referencedTable: $db.documents,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocumentsTableAnnotationComposer(
              $db: $db,
              $table: $db.documents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> vectorsRefs<T extends Object>(
      Expression<T> Function($$VectorsTableAnnotationComposer a) f) {
    final $$VectorsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.vectors,
        getReferencedColumn: (t) => t.chunkId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$VectorsTableAnnotationComposer(
              $db: $db,
              $table: $db.vectors,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ChunksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChunksTable,
    Chunk,
    $$ChunksTableFilterComposer,
    $$ChunksTableOrderingComposer,
    $$ChunksTableAnnotationComposer,
    $$ChunksTableCreateCompanionBuilder,
    $$ChunksTableUpdateCompanionBuilder,
    (Chunk, $$ChunksTableReferences),
    Chunk,
    PrefetchHooks Function({bool documentId, bool vectorsRefs})> {
  $$ChunksTableTableManager(_$AppDatabase db, $ChunksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> documentId = const Value.absent(),
            Value<String> chunkText = const Value.absent(),
            Value<int> chunkIndex = const Value.absent(),
            Value<int> tokenCount = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChunksCompanion(
            id: id,
            documentId: documentId,
            chunkText: chunkText,
            chunkIndex: chunkIndex,
            tokenCount: tokenCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String documentId,
            required String chunkText,
            required int chunkIndex,
            required int tokenCount,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ChunksCompanion.insert(
            id: id,
            documentId: documentId,
            chunkText: chunkText,
            chunkIndex: chunkIndex,
            tokenCount: tokenCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ChunksTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({documentId = false, vectorsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (vectorsRefs) db.vectors],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (documentId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.documentId,
                    referencedTable:
                        $$ChunksTableReferences._documentIdTable(db),
                    referencedColumn:
                        $$ChunksTableReferences._documentIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (vectorsRefs)
                    await $_getPrefetchedData<Chunk, $ChunksTable, Vector>(
                        currentTable: table,
                        referencedTable:
                            $$ChunksTableReferences._vectorsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ChunksTableReferences(db, table, p0).vectorsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.chunkId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ChunksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChunksTable,
    Chunk,
    $$ChunksTableFilterComposer,
    $$ChunksTableOrderingComposer,
    $$ChunksTableAnnotationComposer,
    $$ChunksTableCreateCompanionBuilder,
    $$ChunksTableUpdateCompanionBuilder,
    (Chunk, $$ChunksTableReferences),
    Chunk,
    PrefetchHooks Function({bool documentId, bool vectorsRefs})>;
typedef $$VectorsTableCreateCompanionBuilder = VectorsCompanion Function({
  required String id,
  required String chunkId,
  required Uint8List embedding,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$VectorsTableUpdateCompanionBuilder = VectorsCompanion Function({
  Value<String> id,
  Value<String> chunkId,
  Value<Uint8List> embedding,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$VectorsTableReferences
    extends BaseReferences<_$AppDatabase, $VectorsTable, Vector> {
  $$VectorsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChunksTable _chunkIdTable(_$AppDatabase db) => db.chunks
      .createAlias($_aliasNameGenerator(db.vectors.chunkId, db.chunks.id));

  $$ChunksTableProcessedTableManager get chunkId {
    final $_column = $_itemColumn<String>('chunk_id')!;

    final manager = $$ChunksTableTableManager($_db, $_db.chunks)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chunkIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$VectorsTableFilterComposer
    extends Composer<_$AppDatabase, $VectorsTable> {
  $$VectorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get embedding => $composableBuilder(
      column: $table.embedding, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$ChunksTableFilterComposer get chunkId {
    final $$ChunksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.chunkId,
        referencedTable: $db.chunks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChunksTableFilterComposer(
              $db: $db,
              $table: $db.chunks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$VectorsTableOrderingComposer
    extends Composer<_$AppDatabase, $VectorsTable> {
  $$VectorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get embedding => $composableBuilder(
      column: $table.embedding, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$ChunksTableOrderingComposer get chunkId {
    final $$ChunksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.chunkId,
        referencedTable: $db.chunks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChunksTableOrderingComposer(
              $db: $db,
              $table: $db.chunks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$VectorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VectorsTable> {
  $$VectorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<Uint8List> get embedding =>
      $composableBuilder(column: $table.embedding, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ChunksTableAnnotationComposer get chunkId {
    final $$ChunksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.chunkId,
        referencedTable: $db.chunks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChunksTableAnnotationComposer(
              $db: $db,
              $table: $db.chunks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$VectorsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $VectorsTable,
    Vector,
    $$VectorsTableFilterComposer,
    $$VectorsTableOrderingComposer,
    $$VectorsTableAnnotationComposer,
    $$VectorsTableCreateCompanionBuilder,
    $$VectorsTableUpdateCompanionBuilder,
    (Vector, $$VectorsTableReferences),
    Vector,
    PrefetchHooks Function({bool chunkId})> {
  $$VectorsTableTableManager(_$AppDatabase db, $VectorsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VectorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VectorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VectorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> chunkId = const Value.absent(),
            Value<Uint8List> embedding = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              VectorsCompanion(
            id: id,
            chunkId: chunkId,
            embedding: embedding,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String chunkId,
            required Uint8List embedding,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              VectorsCompanion.insert(
            id: id,
            chunkId: chunkId,
            embedding: embedding,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$VectorsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({chunkId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (chunkId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.chunkId,
                    referencedTable: $$VectorsTableReferences._chunkIdTable(db),
                    referencedColumn:
                        $$VectorsTableReferences._chunkIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$VectorsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $VectorsTable,
    Vector,
    $$VectorsTableFilterComposer,
    $$VectorsTableOrderingComposer,
    $$VectorsTableAnnotationComposer,
    $$VectorsTableCreateCompanionBuilder,
    $$VectorsTableUpdateCompanionBuilder,
    (Vector, $$VectorsTableReferences),
    Vector,
    PrefetchHooks Function({bool chunkId})>;
typedef $$SessionMemoryTableCreateCompanionBuilder = SessionMemoryCompanion
    Function({
  required String sessionId,
  Value<String?> summary,
  Value<int> summaryVersion,
  Value<int> msgCount,
  Value<int> estTokens,
  Value<int> runningTokenCount,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SessionMemoryTableUpdateCompanionBuilder = SessionMemoryCompanion
    Function({
  Value<String> sessionId,
  Value<String?> summary,
  Value<int> summaryVersion,
  Value<int> msgCount,
  Value<int> estTokens,
  Value<int> runningTokenCount,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$SessionMemoryTableReferences extends BaseReferences<_$AppDatabase,
    $SessionMemoryTable, SessionMemoryData> {
  $$SessionMemoryTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
          $_aliasNameGenerator(db.sessionMemory.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager($_db, $_db.sessions)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SessionMemoryTableFilterComposer
    extends Composer<_$AppDatabase, $SessionMemoryTable> {
  $$SessionMemoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get summaryVersion => $composableBuilder(
      column: $table.summaryVersion,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get msgCount => $composableBuilder(
      column: $table.msgCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get estTokens => $composableBuilder(
      column: $table.estTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get runningTokenCount => $composableBuilder(
      column: $table.runningTokenCount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableFilterComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SessionMemoryTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionMemoryTable> {
  $$SessionMemoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get summaryVersion => $composableBuilder(
      column: $table.summaryVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get msgCount => $composableBuilder(
      column: $table.msgCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get estTokens => $composableBuilder(
      column: $table.estTokens, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get runningTokenCount => $composableBuilder(
      column: $table.runningTokenCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableOrderingComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SessionMemoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionMemoryTable> {
  $$SessionMemoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<int> get summaryVersion => $composableBuilder(
      column: $table.summaryVersion, builder: (column) => column);

  GeneratedColumn<int> get msgCount =>
      $composableBuilder(column: $table.msgCount, builder: (column) => column);

  GeneratedColumn<int> get estTokens =>
      $composableBuilder(column: $table.estTokens, builder: (column) => column);

  GeneratedColumn<int> get runningTokenCount => $composableBuilder(
      column: $table.runningTokenCount, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.sessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SessionMemoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SessionMemoryTable,
    SessionMemoryData,
    $$SessionMemoryTableFilterComposer,
    $$SessionMemoryTableOrderingComposer,
    $$SessionMemoryTableAnnotationComposer,
    $$SessionMemoryTableCreateCompanionBuilder,
    $$SessionMemoryTableUpdateCompanionBuilder,
    (SessionMemoryData, $$SessionMemoryTableReferences),
    SessionMemoryData,
    PrefetchHooks Function({bool sessionId})> {
  $$SessionMemoryTableTableManager(_$AppDatabase db, $SessionMemoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionMemoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionMemoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionMemoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> sessionId = const Value.absent(),
            Value<String?> summary = const Value.absent(),
            Value<int> summaryVersion = const Value.absent(),
            Value<int> msgCount = const Value.absent(),
            Value<int> estTokens = const Value.absent(),
            Value<int> runningTokenCount = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SessionMemoryCompanion(
            sessionId: sessionId,
            summary: summary,
            summaryVersion: summaryVersion,
            msgCount: msgCount,
            estTokens: estTokens,
            runningTokenCount: runningTokenCount,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String sessionId,
            Value<String?> summary = const Value.absent(),
            Value<int> summaryVersion = const Value.absent(),
            Value<int> msgCount = const Value.absent(),
            Value<int> estTokens = const Value.absent(),
            Value<int> runningTokenCount = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SessionMemoryCompanion.insert(
            sessionId: sessionId,
            summary: summary,
            summaryVersion: summaryVersion,
            msgCount: msgCount,
            estTokens: estTokens,
            runningTokenCount: runningTokenCount,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SessionMemoryTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$SessionMemoryTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$SessionMemoryTableReferences._sessionIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SessionMemoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SessionMemoryTable,
    SessionMemoryData,
    $$SessionMemoryTableFilterComposer,
    $$SessionMemoryTableOrderingComposer,
    $$SessionMemoryTableAnnotationComposer,
    $$SessionMemoryTableCreateCompanionBuilder,
    $$SessionMemoryTableUpdateCompanionBuilder,
    (SessionMemoryData, $$SessionMemoryTableReferences),
    SessionMemoryData,
    PrefetchHooks Function({bool sessionId})>;
typedef $$UserMemoryTableCreateCompanionBuilder = UserMemoryCompanion Function({
  required String namespace,
  required String key,
  required String value,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$UserMemoryTableUpdateCompanionBuilder = UserMemoryCompanion Function({
  Value<String> namespace,
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$UserMemoryTableFilterComposer
    extends Composer<_$AppDatabase, $UserMemoryTable> {
  $$UserMemoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get namespace => $composableBuilder(
      column: $table.namespace, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$UserMemoryTableOrderingComposer
    extends Composer<_$AppDatabase, $UserMemoryTable> {
  $$UserMemoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get namespace => $composableBuilder(
      column: $table.namespace, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$UserMemoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserMemoryTable> {
  $$UserMemoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get namespace =>
      $composableBuilder(column: $table.namespace, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$UserMemoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UserMemoryTable,
    UserMemoryData,
    $$UserMemoryTableFilterComposer,
    $$UserMemoryTableOrderingComposer,
    $$UserMemoryTableAnnotationComposer,
    $$UserMemoryTableCreateCompanionBuilder,
    $$UserMemoryTableUpdateCompanionBuilder,
    (
      UserMemoryData,
      BaseReferences<_$AppDatabase, $UserMemoryTable, UserMemoryData>
    ),
    UserMemoryData,
    PrefetchHooks Function()> {
  $$UserMemoryTableTableManager(_$AppDatabase db, $UserMemoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserMemoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserMemoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserMemoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> namespace = const Value.absent(),
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UserMemoryCompanion(
            namespace: namespace,
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String namespace,
            required String key,
            required String value,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              UserMemoryCompanion.insert(
            namespace: namespace,
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UserMemoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UserMemoryTable,
    UserMemoryData,
    $$UserMemoryTableFilterComposer,
    $$UserMemoryTableOrderingComposer,
    $$UserMemoryTableAnnotationComposer,
    $$UserMemoryTableCreateCompanionBuilder,
    $$UserMemoryTableUpdateCompanionBuilder,
    (
      UserMemoryData,
      BaseReferences<_$AppDatabase, $UserMemoryTable, UserMemoryData>
    ),
    UserMemoryData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$ChunksTableTableManager get chunks =>
      $$ChunksTableTableManager(_db, _db.chunks);
  $$VectorsTableTableManager get vectors =>
      $$VectorsTableTableManager(_db, _db.vectors);
  $$SessionMemoryTableTableManager get sessionMemory =>
      $$SessionMemoryTableTableManager(_db, _db.sessionMemory);
  $$UserMemoryTableTableManager get userMemory =>
      $$UserMemoryTableTableManager(_db, _db.userMemory);
}

mixin _$SessionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  SessionsDaoManager get managers => SessionsDaoManager(this);
}

class SessionsDaoManager {
  final _$SessionsDaoMixin _db;
  SessionsDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
}

mixin _$MessagesDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $MessagesTable get messages => attachedDatabase.messages;
  MessagesDaoManager get managers => MessagesDaoManager(this);
}

class MessagesDaoManager {
  final _$MessagesDaoMixin _db;
  MessagesDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db.attachedDatabase, _db.messages);
}

mixin _$DocumentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $DocumentsTable get documents => attachedDatabase.documents;
  DocumentsDaoManager get managers => DocumentsDaoManager(this);
}

class DocumentsDaoManager {
  final _$DocumentsDaoMixin _db;
  DocumentsDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db.attachedDatabase, _db.documents);
}

mixin _$ChunksDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $DocumentsTable get documents => attachedDatabase.documents;
  $ChunksTable get chunks => attachedDatabase.chunks;
  ChunksDaoManager get managers => ChunksDaoManager(this);
}

class ChunksDaoManager {
  final _$ChunksDaoMixin _db;
  ChunksDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db.attachedDatabase, _db.documents);
  $$ChunksTableTableManager get chunks =>
      $$ChunksTableTableManager(_db.attachedDatabase, _db.chunks);
}

mixin _$VectorsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $DocumentsTable get documents => attachedDatabase.documents;
  $ChunksTable get chunks => attachedDatabase.chunks;
  $VectorsTable get vectors => attachedDatabase.vectors;
  VectorsDaoManager get managers => VectorsDaoManager(this);
}

class VectorsDaoManager {
  final _$VectorsDaoMixin _db;
  VectorsDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db.attachedDatabase, _db.documents);
  $$ChunksTableTableManager get chunks =>
      $$ChunksTableTableManager(_db.attachedDatabase, _db.chunks);
  $$VectorsTableTableManager get vectors =>
      $$VectorsTableTableManager(_db.attachedDatabase, _db.vectors);
}

mixin _$SessionMemoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $SessionMemoryTable get sessionMemory => attachedDatabase.sessionMemory;
  SessionMemoryDaoManager get managers => SessionMemoryDaoManager(this);
}

class SessionMemoryDaoManager {
  final _$SessionMemoryDaoMixin _db;
  SessionMemoryDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$SessionMemoryTableTableManager get sessionMemory =>
      $$SessionMemoryTableTableManager(_db.attachedDatabase, _db.sessionMemory);
}

mixin _$UserMemoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $UserMemoryTable get userMemory => attachedDatabase.userMemory;
  UserMemoryDaoManager get managers => UserMemoryDaoManager(this);
}

class UserMemoryDaoManager {
  final _$UserMemoryDaoMixin _db;
  UserMemoryDaoManager(this._db);
  $$UserMemoryTableTableManager get userMemory =>
      $$UserMemoryTableTableManager(_db.attachedDatabase, _db.userMemory);
}
