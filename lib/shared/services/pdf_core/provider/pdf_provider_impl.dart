import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:snapfig/shared/services/ocr_core/ocr_core.dart';
import 'package:snapfig/shared/services/pdf_core/models/models.dart';
import 'package:snapfig/shared/services/pdf_core/provider/pdf_provider.dart';
import 'package:path/path.dart' as path_lib;
import 'package:pdfrx/pdfrx.dart';
import 'package:logging/logging.dart';
import 'dart:isolate';

class _PDFInfo {
  final int totalPages;
  final List<int>? thumbnail;

  _PDFInfo({required this.totalPages, this.thumbnail});
}

class PDFProviderImpl<OCR extends OCRProvider> extends PDFProvider {
  late final Isar _isar;
  final OCR _ocrProvider;
  final String _dbPath;
  final Set<Id> _processing = {};
  late final StreamSubscription<void> _databaseSubscription;
  List<PDFModel> _pdfs = [];
  final Logger _logger = Logger('PDFProviderImpl');

  @override
  List<BasePdf> get pdfs => _pdfs;

  PDFProviderImpl._({required OCR ocrProvider, required String dbPath})
    : _ocrProvider = ocrProvider,
      _dbPath = dbPath;

  // 데이터베이스를 로드하고 프로바이더를 반환합니다.
  static Future<PDFProviderImpl<OCR>> load<OCR extends OCRProvider>({
    required OCR ocrProvider,
    required String dbPath,
  }) async {
    final provider = PDFProviderImpl<OCR>._(
      ocrProvider: ocrProvider,
      dbPath: dbPath,
    );
    await provider._initDatabase();
    return provider;
  }

  // 데이터베이스 초기화
  Future<void> _initDatabase() async {
    _isar = await Isar.open([
      PDFModelSchema,
      PageModelSchema,
      LayoutModelSchema,
    ], directory: _dbPath);
    _listenDatabase();
  }

  void _listenDatabase() {
    final stream = _isar.pDFModels.watchLazy(fireImmediately: true);
    _databaseSubscription = stream.listen((_) async {
      _pdfs = await _getAllPdfs();
      _logger.info('PDFs are changed.');
      notifyListeners();
    });
  }

  Future<List<PDFModel>> _getAllPdfs() async {
    return await _isar.pDFModels.where().sortByUpdatedAt().findAll();
  }

  Future<List<PDFModel>> _getPendingPdfs() async {
    return await _isar.pDFModels
        .filter()
        .statusEqualTo(PDFStatus.pending)
        .findAll();
  }

  // 주어진 PDF에 대한 OCR을 진행합니다. 이때 독립된 isolate로 변경이 되고,
  // 처리 결과는 주 스레드에서 처리됩니다.
  Future<void> _processPdfWithOcr(PDFModel pdf) async {
    _logger.severe('process OCR');
    await updatePDF(id: pdf.id, status: PDFStatus.processing);
    final receivePort = ReceivePort();
    await Isolate.spawn(_ocrProcess, [
      _ocrProvider,
      pdf.path,
      receivePort.sendPort,
    ]);
    receivePort.listen((ocrResult) async {
      try {
        await _updatePdfModelWithOcrResult(pdf, ocrResult);
      } catch (e) {
        await updatePDF(id: pdf.id, status: PDFStatus.failed);
        _logger.severe('OCR 처리 실패: $e');
      } finally {
        _processing.remove(pdf.id);
        receivePort.close();
      }
    });
  }

  /// Isolate에서 OCR 처리
  static void _ocrProcess(List args) async {
    final OCRProvider ocrProvider = args[0];
    final String pdfPath = args[1];
    final SendPort sendPort = args[2];
    try {
      final ocrResult = await ocrProvider.process(pdfPath);
      sendPort.send(ocrResult);
    } catch (e) {
      debugPrint('Fail: $e');
      sendPort.send(null);
    }
  }

  // OCR 결과를 데이터베이스에 저장합니다.
  Future<void> _updatePdfModelWithOcrResult(
    PDFModel pdf,
    OCRResult? ocrResult,
  ) async {
    if (ocrResult == null) throw Exception('OCR 결과 없음');

    try {
      final pages = ocrResult.pages;
      final figures = ocrResult.figures;

      // Save to Isar database
      await _isar.writeTxn(() async {
        // Mapping OCRResult to PageModel and LayoutModel
        final pageModels = <PageModel>[];
        final allLayoutModels = <LayoutModel>[];

        for (final page in pages) {
          final pageModel = PageModel.create(
            pageIndex: page.index,
            fullText: page.blocks.map((block) => block.text).join('\n'),
            size: Size(page.pageSize[0], page.pageSize[1]),
          );

          // PDF와 PageModel 관계 설정
          pageModel.pdf.value = pdf;

          final layoutModels = <LayoutModel>[];
          // 텍스트 블록 처리
          for (final textBlock in page.blocks) {
            layoutModels.add(
              LayoutModel.create(
                type: LayoutType.text,
                content: textBlock.text,
                text: textBlock.text,
                latex: '',
                box: Rect.fromLTWH(
                  textBlock.bbox.x,
                  textBlock.bbox.y,
                  textBlock.bbox.width,
                  textBlock.bbox.height,
                ),
              ),
            );
          }

          // Reference 처리
          for (final ref in page.references) {
            if (ref.notMatched) continue;
            layoutModels.add(
              LayoutModel.create(
                type: LayoutType.figureReference,
                content: ref.text,
                text: ref.text,
                latex: '',
                box: Rect.fromLTWH(
                  ref.bbox.x,
                  ref.bbox.y,
                  ref.bbox.width,
                  ref.bbox.height,
                ),
                referencedFigureId: ref.figureId,
              ),
            );
          }

          // Figure 처리 (해당 page에 속한 figure만)
          for (final figure in figures.where((f) => f.pageIdx == page.index)) {
            layoutModels.add(
              LayoutModel.create(
                type: LayoutType.figure,
                content: figure.text,
                text: figure.text,
                latex: '',
                box: Rect.fromLTWH(
                  figure.bbox.x,
                  figure.bbox.y,
                  figure.bbox.width,
                  figure.bbox.height,
                ),
                figureId: figure.figureId,
              ),
            );
          }

          // PageModel과 LayoutModel 관계 설정
          for (final layoutModel in layoutModels) {
            layoutModel.page.value = pageModel;
          }

          allLayoutModels.addAll(layoutModels);
          pageModels.add(pageModel);
        }

        // 1. 먼저 PageModel들을 저장
        await _isar.pageModels.putAll(pageModels);

        // 2. LayoutModel들을 저장
        await _isar.layoutModels.putAll(allLayoutModels);

        // 3. PDF 모델 저장 및 관계 설정
        await _isar.pDFModels.put(pdf);

        // 4. 관계 링크들을 저장
        for (final pageModel in pageModels) {
          await pageModel.pdf.save();
        }

        for (final layoutModel in allLayoutModels) {
          await layoutModel.page.save();
        }
      });

      await updatePDF(
        id: pdf.id,
        status: PDFStatus.completed,
        updatedAt: DateTime.now(),
      );

      _logger.info('PDF OCR 결과 저장 완료: ${pdf.name}');
    } catch (e) {
      _logger.severe('OCR 결과 저장 중 오류 발생: $e');
      // 오류 발생 시 상태를 failed로 업데이트
      await updatePDF(
        id: pdf.id,
        status: PDFStatus.failed,
        updatedAt: DateTime.now(),
      );
      rethrow;
    }
  }

  Future<_PDFInfo> _getPDFInfo(String filePath) async {
    final data = await PdfDocument.openFile(filePath);
    try {
      final thumbnail = await renderPageToPngBytes(data.pages.first);
      return _PDFInfo(totalPages: data.pages.length, thumbnail: thumbnail);
    } catch (e) {
      _logger.severe('Failed to get PDF info: $e');
      return _PDFInfo(totalPages: 0, thumbnail: null);
    } finally {
      await data.dispose();
    }
  }

  Future<Uint8List?> renderPageToPngBytes(PdfPage page) async {
    final thumbnailData = await page.render(
      width: page.width.toInt(),
      height: page.height.toInt(),
    );
    final thumbnailImg = await thumbnailData?.createImage();
    final thumbnailBytes = await thumbnailImg?.toByteData(
      format: ImageByteFormat.png,
    );
    return thumbnailBytes?.buffer.asUint8List();
  }

  @override
  Future<void> addPDF(String filePath) async {
    try {
      final pdf = PDFModel.create(
        name: path_lib.basenameWithoutExtension(filePath),
        path: filePath,
        createdAt: DateTime.now(),
        totalPages: 0,
        status: PDFStatus.pending,
        thumbnail: null,
      );
      await _isar.writeTxn(() async {
        await _isar.pDFModels.put(pdf);
      });
      final pdfInfo = await _getPDFInfo(filePath);
      pdf.thumbnail = pdfInfo.thumbnail;
      await updatePDF(
        id: pdf.id,
        thumbnail: pdfInfo.thumbnail,
        totalPages: pdfInfo.totalPages,
      );
      _processPdfWithOcr(pdf);
    } catch (e) {
      _logger.severe('Failed to add PDF: $e');
    }
  }

  @override
  Future<void> deletePDF(List<BasePdf> pdfs) async {
    await _isar.writeTxn(() async {
      await _isar.pDFModels.deleteAll(pdfs.map((e) => e.id).toList());
    });
  }

  @override
  Future<void> updatePDF({
    required Id id,
    String? name,
    DateTime? updatedAt,
    PDFStatus? status,
    List<int>? thumbnail,
    int? totalPages,
  }) async {
    await _isar.writeTxn(() async {
      try {
        final pdf = await _isar.pDFModels.get(id);
        if (pdf == null) {
          _logger.severe('PDF not found: $id');
          return;
        }
        pdf.update(
          name: name,
          updatedAt: updatedAt,
          status: status,
          thumbnail: thumbnail,
          totalPages: totalPages,
        );
        await _isar.pDFModels.put(pdf);
      } catch (e) {
        _logger.severe('Failed to update PDF: $e');
      }
    });
  }

  @override
  Future<List<BasePdf>> queryPDFs({
    String? keyword,
    PDFStatus? status,
    int? limit,
  }) async {
    var query = _isar.pDFModels
        .filter()
        .optional(keyword != null, (q) => q.nameContains(keyword!))
        .optional(status != null, (q) => q.statusEqualTo(status!))
        .sortByUpdatedAt()
        .optional(limit != null, (q) => q.limit(limit!));
    return await query.findAll();
  }

  @override
  Future<BasePdf?> getPDF(String path) async {
    return await _isar.pDFModels.filter().pathEqualTo(path).findFirst();
  }

  @override
  void dispose() {
    _databaseSubscription.cancel();
    _isar.close();
    super.dispose();
  }
}
