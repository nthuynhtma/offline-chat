import 'dart:io';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:offline_chat/core/errors/app_exception.dart';

/// Supported document types
enum DocumentType {
  pdf,
  docx,
  txt,
  markdown,
}

abstract interface class DocumentParserService {
  /// Parse file về raw text.
  /// Hỗ trợ: .pdf, .docx, .txt, .md
  /// Throws [DocumentParseException] nếu không parse được
  Future<String> parse(String filePath);

  /// Check file type có support không
  bool isSupported(String filePath);

  /// Xác định DocumentType từ file path
  DocumentType? detectType(String filePath);
}

/// Implementation of DocumentParserService.
///
/// Supports:
/// - .pdf via syncfusion_flutter_pdf (PdfTextExtractor)
/// - .docx via archive (ZIP) + XML parsing
/// - .txt, .md via direct file read
class DocumentParserServiceImpl implements DocumentParserService {
  @override
  bool isSupported(String filePath) {
    return detectType(filePath) != null;
  }

  @override
  DocumentType? detectType(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return DocumentType.pdf;
      case 'docx':
        return DocumentType.docx;
      case 'txt':
        return DocumentType.txt;
      case 'md':
        return DocumentType.markdown;
      default:
        return null;
    }
  }

  @override
  Future<String> parse(String filePath) async {
    final type = detectType(filePath);
    if (type == null) {
      throw DocumentParseException(
        'Unsupported file type: ${filePath.split('.').last}',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw DocumentParseException('File not found: $filePath');
    }

    try {
      switch (type) {
        case DocumentType.pdf:
          return await _parsePdf(filePath);
        case DocumentType.docx:
          return await _parseDocx(filePath);
        case DocumentType.txt:
        case DocumentType.markdown:
          return await file.readAsString();
      }
    } catch (e) {
      if (e is DocumentParseException) rethrow;
      throw DocumentParseException('Failed to parse file: $e');
    }
  }

  Future<String> _parsePdf(String filePath) async {
    PdfDocument? pdfDocument;
    try {
      final bytes = await File(filePath).readAsBytes();
      pdfDocument = PdfDocument(inputBytes: bytes);
      final textExtractor = PdfTextExtractor(pdfDocument);
      final text = textExtractor.extractText().trim();
      if (text.isEmpty) {
        throw const DocumentParseException('No text found in PDF');
      }
      return text;
    } catch (e, stackTrace) {
      if (e is DocumentParseException) {
        Error.throwWithStackTrace(e, stackTrace);
      }
      Error.throwWithStackTrace(
        DocumentParseException('PDF parsing failed: $e'),
        stackTrace,
      );
    } finally {
      pdfDocument?.dispose();
    }
  }

  Future<String> _parseDocx(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find word/document.xml
      final documentFile = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw const DocumentParseException(
          'Invalid DOCX: word/document.xml not found',
        ),
      );

      final content = String.fromCharCodes(documentFile.content);
      final text = _extractDocxText(content);
      if (text.isEmpty) {
        throw const DocumentParseException('No text found in DOCX');
      }
      return text;
    } catch (e, stackTrace) {
      if (e is DocumentParseException) {
        Error.throwWithStackTrace(e, stackTrace);
      }
      Error.throwWithStackTrace(
        DocumentParseException('DOCX parsing failed: $e'),
        stackTrace,
      );
    }
  }

  /// Extract text from DOCX XML by parsing <w:t> tags.
  String _extractDocxText(String xml) {
    final textParts = <String>[];
    final regex = RegExp(r'<w:t[^>]*>([^<]+)</w:t>');
    final matches = regex.allMatches(xml);

    for (final match in matches) {
      textParts.add(match.group(1)!);
    }

    if (textParts.isEmpty) {
      throw const DocumentParseException('No text found in DOCX');
    }

    return textParts.join(' ').trim();
  }
}