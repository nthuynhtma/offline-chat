import 'package:logger/logger.dart';

final log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 3,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    noBoxingByDefault: true, 
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);