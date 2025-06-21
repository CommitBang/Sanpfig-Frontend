import 'package:flutter/material.dart';
import 'package:snapfig/shared/services/pdf_core/pdf_core.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class FigureSidebar extends StatelessWidget {
  final List<BaseLayout> figures;
  final Function(BaseLayout) onFigureSelected;

  const FigureSidebar({
    super.key,
    required this.figures,
    required this.onFigureSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: figures.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: _buildThumbnail(figures[index], context: context),
          title: GptMarkdown(figures[index].text ?? '', maxLines: 2),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onFigureSelected(figures[index]),
        );
      },
    );
  }

  Widget _buildThumbnail(BaseLayout figures, {required BuildContext context}) {
    final theme = Theme.of(context);
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(
        Icons.picture_as_pdf,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }
}
