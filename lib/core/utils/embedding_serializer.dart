import 'dart:typed_data';

class EmbeddingSerializer {
  /// Float32List → Uint8List để lưu vào SQLite BLOB
  static Uint8List serialize(List<double> embedding) {
    final float32 = Float32List.fromList(embedding);
    return float32.buffer.asUint8List();
  }

  /// Uint8List → List<double> khi đọc từ SQLite
  static List<double> deserialize(Uint8List bytes) {
    return Float32List.view(bytes.buffer).toList();
  }
}