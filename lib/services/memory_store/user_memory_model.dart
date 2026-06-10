/// Một user memory entry lưu trong UserMemory table.
///
/// namespace.key = value (e.g. "preference.crop_type = lúa").
class UserMemory {
  final String namespace;
  final String key;
  final String value;

  const UserMemory({
    required this.namespace,
    required this.key,
    required this.value,
  });
}