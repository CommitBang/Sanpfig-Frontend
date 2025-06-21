import 'package:snapfig/shared/services/ocr_core/models/bounding_box.dart';
import 'package:snapfig/shared/services/ocr_core/models/metadata.dart';

class OCRResult {
  final Metadata metadata;
  final List<PageResult> pages;
  final List<Figure> figures;

  const OCRResult({
    required this.metadata,
    required this.pages,
    required this.figures,
  });

  factory OCRResult.fromJson(Map<String, dynamic> json) {
    return OCRResult(
      metadata: Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
      pages:
          (json['pages'] as List<dynamic>)
              .map((e) => PageResult.fromJson(e as Map<String, dynamic>))
              .toList(),
      figures:
          (json['figures'] as List<dynamic>)
              .map((e) => Figure.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metadata': metadata.toJson(),
      'pages': pages.map((e) => e.toJson()).toList(),
      'figures': figures.map((e) => e.toJson()).toList(),
    };
  }
}

class PageResult {
  final int index;
  final List<double> pageSize;
  final List<TextResult> blocks;
  final List<Reference> references;

  const PageResult({
    required this.index,
    required this.pageSize,
    required this.blocks,
    required this.references,
  });

  factory PageResult.fromJson(Map<String, dynamic> json) {
    return PageResult(
      index: (json['index'] as num).toInt(),
      pageSize:
          (json['page_size'] as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList(),
      blocks:
          (json['blocks'] as List<dynamic>)
              .map((e) => TextResult.fromJson(e as Map<String, dynamic>))
              .toList(),
      references:
          (json['references'] as List<dynamic>)
              .map((e) => Reference.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'page_size': pageSize,
      'blocks': blocks.map((e) => e.toJson()).toList(),
      'references': references.map((e) => e.toJson()).toList(),
    };
  }
}

class TextResult {
  final String text;
  final BBox bbox;

  const TextResult({required this.text, required this.bbox});

  factory TextResult.fromJson(Map<String, dynamic> json) {
    return TextResult(
      text: json['text'] as String,
      bbox: BBox.fromJson(json['bbox'] as List<dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {'text': text, 'bbox': bbox.toJson()};
  }
}

class Reference {
  final BBox bbox;
  final String text;
  final String figureId;
  final bool notMatched;

  const Reference({
    required this.bbox,
    required this.text,
    required this.figureId,
    required this.notMatched,
  });

  factory Reference.fromJson(Map<String, dynamic> json) {
    return Reference(
      bbox: BBox.fromJson(json['bbox'] as List<dynamic>),
      text: json['text'] as String,
      figureId: json['figure_id'] as String? ?? '',
      notMatched: json['not_matched'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bbox': bbox.toJson(),
      'text': text,
      'figure_id': figureId,
      'not_matched': notMatched,
    };
  }
}

class Figure {
  final BBox bbox;
  final int pageIdx;
  final String figureId;
  final String type;
  final String text;

  const Figure({
    required this.bbox,
    required this.pageIdx,
    required this.figureId,
    required this.type,
    required this.text,
  });

  factory Figure.fromJson(Map<String, dynamic> json) {
    return Figure(
      bbox: BBox.fromJson(json['bbox'] as List<dynamic>),
      pageIdx: (json['page_idx'] as num).toInt(),
      figureId: json['id'] as String? ?? '',
      type: json['block_type'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bbox': bbox.toJson(),
      'page_idx': pageIdx,
      'id': figureId,
      'block_type': type,
      'text': text,
    };
  }
}
