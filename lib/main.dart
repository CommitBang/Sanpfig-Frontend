// lib/main.dart

// lib/main.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:snapfig/features/home/screens/home_widget.dart';
import 'package:snapfig/features/settings/ai_settings_screen.dart';
import 'package:snapfig/shared/services/navigation_service/navigation_service.dart';
import 'package:snapfig/shared/services/ocr_core/ocr_core.dart';
import 'package:snapfig/shared/services/pdf_core/pdf_core.dart';
import 'core/theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      debugPrint(
        '(${record.time}) ${record.level.name} - ${record.loggerName}: ${record.message}',
      );
    });
  }
  await dotenv.load(fileName: '.env');
  final dir = await getApplicationCacheDirectory();
  final pdfProvider = await PDFProviderImpl.load(
    ocrProvider: OCRProviderImpl(baseUrl: dotenv.env['OCR_BASE_URL']!),
    dbPath: dir.path,
  );
  runApp(SnapfigApp(pdfProvider: pdfProvider));
}

class SnapfigApp extends StatelessWidget {
  final PDFProvider _pdfProvider;
  final NavigationService _navigationService = NavigationService();

  SnapfigApp({super.key, required PDFProvider pdfProvider})
    : _pdfProvider = pdfProvider;

  @override
  Widget build(BuildContext context) {
    return InheritedPDFProviderWidget(
      provider: _pdfProvider,
      child: MaterialApp(
        title: 'Snapfig',
        theme: lightTheme,
        darkTheme: darkTheme,
        navigatorKey: _navigationService.navigatorKey,
        home: const HomeWidget(),
        routes: {'/ai-settings': (context) => const AISettingsScreen()},
      ),
    );
  }
}
