// lib/shared/services/ocr_core/ocr_provider_impl.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:snapfig/shared/services/ocr_core/ocr_core.dart';
import 'package:snapfig/shared/services/ocr_core/ocr_provider.dart';
import 'package:snapfig/shared/services/ocr_core/models/ocr_result.dart';

import 'package:path/path.dart' as path_lib;

class OCRProviderImpl extends OCRProvider {
  final String baseUrl;
  final http.Client httpClient;

  OCRProviderImpl({required this.baseUrl, http.Client? httpClient})
    : httpClient = httpClient ?? _createHttpClient();

  static http.Client _createHttpClient() {
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (cert, host, port) => true;

    // 연결 안정성을 위한 설정
    httpClient.connectionTimeout = const Duration(seconds: 30);
    httpClient.idleTimeout = const Duration(seconds: 60);

    // User-Agent 설정
    httpClient.userAgent = 'Snapfig/1.0';

    return IOClient(httpClient);
  }

  @override
  Future<OCRResult> process(String pdfPath) async {
    debugPrint('OCR 처리 시작: $pdfPath');
    debugPrint('OCR API URL: $baseUrl/analyze');

    try {
      // 1) 분석 요청
      final analyzeUri = Uri.parse('$baseUrl/analyze');
      final pdfBytes = await File(pdfPath).readAsBytes();
      debugPrint('PDF 파일 크기: ${pdfBytes.length} bytes');

      final request =
          http.MultipartRequest('POST', analyzeUri)
            ..headers['Accept'] = 'text/event-stream'
            ..headers['Cache-Control'] = 'no-cache'
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                pdfBytes,
                filename: path_lib.basename(pdfPath),
              ),
            );

      debugPrint('OCR API 요청 전송 중...');
      final response = await httpClient.send(request);

      debugPrint('OCR API 응답 상태: ${response.statusCode}');
      debugPrint('OCR API 응답 헤더: ${response.headers}');

      if (response.statusCode != 200) {
        debugPrint('OCR API 요청 실패: ${response.statusCode}');
        throw Exception('OCR API 요청 실패: HTTP ${response.statusCode}');
      }

      debugPrint('OCR Stream 수신 시작');

      String buffer = '';
      int chunkCount = 0;

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        chunkCount++;
        debugPrint('청크 #$chunkCount 수신: ${chunk.length} characters');
        debugPrint('청크 내용: "$chunk"');

        buffer += chunk;

        // 줄바꿈으로 분리하여 각 메시지 처리
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // 마지막 불완전한 라인은 버퍼에 보관

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            debugPrint('빈 라인 건너뛰기');
            continue;
          }

          debugPrint('라인 처리: "$trimmed"');

          if (!trimmed.startsWith('data: ')) {
            debugPrint('올바르지 않은 메시지 형식: $trimmed');
            continue;
          }

          final jsonStr = trimmed.substring(6);
          if (jsonStr.isEmpty) {
            debugPrint('빈 JSON 문자열 건너뛰기');
            continue;
          }

          debugPrint('JSON 파싱 시도: $jsonStr');

          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final status = json['status'] as String;

            debugPrint('JSON 파싱 성공, 상태: $status');

            if (status == 'completed') {
              final data = json['data'] as Map<String, dynamic>;
              debugPrint('OCR 처리 완료');
              final result = OCRResult.fromJson(data);
              return result;
            } else if (status == 'error') {
              final message = json['message'] as String? ?? '알 수 없는 오류';
              debugPrint('OCR 처리 실패: $message');
              throw Exception('OCR 처리 실패: $message');
            } else {
              debugPrint('OCR 진행 중: $status');
            }
          } catch (e) {
            debugPrint('JSON 파싱 오류: $e');
            debugPrint('문제가 된 데이터: "$jsonStr"');
            // JSON 파싱 오류가 있어도 계속 진행
            continue;
          }
        }
      }

      debugPrint('스트림 처리 완료, 총 $chunkCount 개 청크 처리');
      return const OCRResult(
        metadata: Metadata(title: '', pages: 0),
        pages: [],
        figures: [],
      );
    } catch (e) {
      debugPrint('OCR 처리 중 오류 발생: $e');
      if (e.toString().contains('Connection closed')) {
        throw Exception('서버 연결이 끊어졌습니다. 서버 상태를 확인해주세요.');
      }
      rethrow;
    }
  }
}
