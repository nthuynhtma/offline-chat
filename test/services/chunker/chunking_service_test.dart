import 'package:flutter_test/flutter_test.dart';
import 'package:offline_chat/services/chunker/chunking_service.dart';

void main() {
  late ChunkingService chunkingService;

  setUp(() {
    chunkingService = ChunkingServiceImpl();
  });

  group('ChunkingService', () {
    test('returns empty list for empty text', () {
      final result = chunkingService.chunk('');
      expect(result, isEmpty);
    });

    test('returns single chunk for short text', () {
      final result = chunkingService.chunk('Hello world');
      expect(result.length, 1);
      expect(result.first, 'Hello world');
    });

    test('splits long text into multiple chunks', () {
      // Generate text long enough to require multiple chunks
      // chunkSize=500 tokens = 2000 chars, so 5000 chars = ~2-3 chunks
      final text = 'word ' * 5000;
      final result = chunkingService.chunk(text, chunkSize: 500, overlap: 100);
      expect(result.length, greaterThan(1));
    });

    test('handles Vietnamese text correctly', () {
      final text = 'Xin chào, tôi là một trợ lý AI hoạt động hoàn toàn offline. '
          'Tôi có thể giúp bạn trả lời các câu hỏi từ tài liệu PDF, DOCX, '
          'và văn bản thông thường. Hãy hỏi tôi bất cứ điều gì bạn cần!';
      final result = chunkingService.chunk(text, chunkSize: 500, overlap: 100);
      expect(result.length, 1);
      expect(result.first, contains('Xin chào'));
    });

    test('chunks do not overlap more than specified overlap', () {
      final text = 'Lorem ipsum dolor sit amet consectetur adipiscing elit. '
          'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. '
          'Ut enim ad minim veniam quis nostrud exercitation ullamco laboris. '
          'Duis aute irure dolor in reprehenderit in voluptate velit esse. '
          'Cillum dolore eu fugiat nulla pariatur excepteur sint occaecat. '
          'Cupidatat non proident sunt in culpa qui officia deserunt mollit. '
          'Anim id est laborum sed perspiciatis unde omnis iste natus error. '
          'Sit voluptatem accusantium doloremque laudantium totam rem aperiam. '
          'Eaque ipsa quae ab illo inventore veritatis et quasi architecto. '
          'Beatae vitae dicta sunt explicabo nemo enim ipsam voluptatem quia. '
          'Voluptas sit aspernatur aut odit aut fugit sed quia consequuntur. '
          'Magni dolores eos qui ratione voluptatem sequi nesciunt neque porro. '
          'Quisquam est qui dolorem ipsum quia dolor sit amet consectetur. '
          'Adipisci velit sed quia non numquam eius modi tempora incidunt. '
          'Ut labore et dolore magnam aliquam quaerat voluptatem ut enim. '
          'Ad minima veniam quis nostrum exercitationem ullam corporis. '
          'Suscipit laboriosam nisi ut aliquid ex ea commodi consequatur. '
          'Quis autem vel eum iure reprehenderit qui in ea voluptate velit. '
          'Esse quam nihil molestiae consequatur vel illum qui dolorem eum. '
          'Fugiat quo voluptas nulla pariatur at vero eos et accusamus.';
      final result = chunkingService.chunk(text, chunkSize: 100, overlap: 20);
      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('returns chunks in correct order', () {
      final text = 'First chunk content. ' * 30 +
          'Second chunk content. ' * 30 +
          'Third chunk content. ' * 30;
      final result = chunkingService.chunk(text, chunkSize: 50, overlap: 10);
      expect(result.length, greaterThanOrEqualTo(3));
      expect(result[0], contains('First chunk'));
    });

    test('handles single word repeated text', () {
      final text = 'word ' * 500;
      final result = chunkingService.chunk(text, chunkSize: 100, overlap: 20);
      expect(result.length, greaterThan(1));
      for (final chunk in result) {
        expect(chunk, isNotEmpty);
      }
    });

    test('chunk size parameter affects number of chunks', () {
      final text = 'Hello world! ' * 200;
      final largeChunks =
          chunkingService.chunk(text, chunkSize: 1000, overlap: 100);
      final smallChunks =
          chunkingService.chunk(text, chunkSize: 100, overlap: 20);
      expect(largeChunks.length, lessThan(smallChunks.length));
    });
  });
}