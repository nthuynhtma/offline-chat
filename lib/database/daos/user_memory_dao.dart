part of '../app_database.dart';

@DriftAccessor(tables: [UserMemory])
class UserMemoryDao extends DatabaseAccessor<AppDatabase>
    with _$UserMemoryDaoMixin {
  UserMemoryDao(super.db);

  Future<List<UserMemoryData>> getAll() =>
      (select(userMemory)).get();

  Future<List<UserMemoryData>> getByNamespace(String nspace) =>
      (select(userMemory)..where((t) => t.namespace.equals(nspace))).get();

  Future<UserMemoryData?> getNested(String nspace, String key) =>
      (select(userMemory)
            ..where((t) =>
                t.namespace.equals(nspace) & t.key.equals(key)))
          .getSingleOrNull();

  Future<void> upsertNested(String nspace, String key, String value) async {
    final existing = await getNested(nspace, key);
    if (existing != null) {
      await update(userMemory).replace(
        existing.copyWith(
          value: value,
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      await into(userMemory).insert(
        UserMemoryCompanion.insert(
          namespace: nspace,
          key: key,
          value: value,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> deleteNested(String nspace, String key) =>
      (delete(userMemory)
            ..where((t) =>
                t.namespace.equals(nspace) & t.key.equals(key)))
          .go();
}