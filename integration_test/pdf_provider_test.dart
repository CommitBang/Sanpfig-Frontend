import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:snapfig/shared/services/ocr_core/ocr_core.dart';
import 'package:snapfig/shared/services/pdf_core/pdf_core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path_lib;

/// assetPath: 예) 'test/unit/assets/test.pdf'
/// 반환: 내부 저장소에 복사된 파일의 경로
Future<String> copyAssetToLocal(String assetPath) async {
  final byteData = await rootBundle.load(assetPath);
  final tempDir = await Directory.systemTemp.createTemp('test_pdf_');
  final fileName = path_lib.basename(assetPath);
  final file = File(path_lib.join(tempDir.path, fileName));
  await file.writeAsBytes(byteData.buffer.asUint8List());
  return file.path;
}

// 더미 OCR 서비스
class DummyOcrService implements OCRProvider {
  @override
  Future<OCRResult> process(String pdfPath) async {
    return const OCRResult(
      metadata: Metadata(title: 'test', pages: 0),
      pages: [],
      figures: [],
    );
  }
}

void main() {
  late PDFProvider provider;
  final String assetPath = 'integration_test/assets/test.pdf';
  late final String pdfPath;

  setUpAll(() async {
    // 임시 디렉토리 사용 (테스트 환경에 맞게 경로 조정)
    pdfPath = await copyAssetToLocal(assetPath);
    final dir = await Directory.systemTemp.createTemp('testdb');
    provider = await PDFProviderImpl.load(
      ocrProvider: DummyOcrService(),
      dbPath: dir.path,
    );
  });

  tearDownAll(() async {
    provider.dispose();
  });

  test('PDF 추가 및 조회', () async {
    await provider.addPDF(pdfPath);
    final pdfs = await provider.queryPDFs();
    expect(pdfs.length, greaterThan(0));
  });

  test('PDF 삭제', () async {
    await provider.addPDF(pdfPath);
    var pdfs = await provider.queryPDFs();
    await provider.deletePDF(pdfs);
    pdfs = await provider.queryPDFs();
    expect(pdfs.length, 0);
  });

  test('PDF 정보 업데이트', () async {
    await provider.addPDF(pdfPath);
    var pdfs = await provider.queryPDFs();
    final pdf = pdfs.first;
    await provider.updatePDF(id: pdf.id, name: 'newName');
    final updated = await provider.queryPDFs(keyword: 'newName');
    expect(updated.length, 1);
    expect(updated.first.name, 'newName');
  });
}
