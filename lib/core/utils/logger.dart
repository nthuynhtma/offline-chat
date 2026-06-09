import 'package:logger/logger.dart';

/// Logger utility cho toàn bộ app.
/// Sử dụng: `log.i('message')`, `log.d('debug')`, `log.e('error')`, v.v.
final log = Logger(
  printer: PrettyPrinter(
    methodCount: 1,
    errorMethodCount: 5,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);
