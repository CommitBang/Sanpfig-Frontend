import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:snapfig/features/pdf_viewer/models/pdf_data_viewmodel.dart';
import 'package:snapfig/features/pdf_viewer/widgets/sidebar/figure_sidebar.dart';
import 'package:snapfig/features/pdf_viewer/widgets/sidebar/outline_sidebar.dart';
import 'package:snapfig/shared/services/pdf_core/pdf_core.dart';

class PDFSideBar extends StatefulWidget {
  final PDFDataViewModel viewModel;
  final Function(PdfOutlineNode) onPageSelected;
  final Function(BaseLayout) onFigureSelected;

  const PDFSideBar({
    super.key,
    required this.viewModel,
    required this.onPageSelected,
    required this.onFigureSelected,
  });

  @override
  State<PDFSideBar> createState() => _PDFSideBarState();
}

enum _PDFSideBarTab { page, figure }

class _PDFSideBarState extends State<PDFSideBar> {
  final double _sidebarWidth = 300;
  _PDFSideBarTab _selectedTab = _PDFSideBarTab.page;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _sidebarWidth,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Column(
        children: [
          SegmentedButton<_PDFSideBarTab>(
            showSelectedIcon: true,
            segments: [
              if (widget.viewModel.outlines.isNotEmpty)
                const ButtonSegment(
                  value: _PDFSideBarTab.page,
                  label: Text('Outline'),
                ),
              const ButtonSegment(
                value: _PDFSideBarTab.figure,
                label: Text('Figure'),
              ),
            ],
            selected: {_selectedTab},
            onSelectionChanged: (value) {
              setState(() {
                _selectedTab = value.first;
              });
            },
          ),
          if (_selectedTab == _PDFSideBarTab.page)
            Expanded(
              child: OutlineSidebar(
                outlines: widget.viewModel.outlines,
                onOutlineSelected: widget.onPageSelected,
              ),
            ),
          if (_selectedTab == _PDFSideBarTab.figure)
            Expanded(
              child: FigureSidebar(
                figures: widget.viewModel.figures,
                onFigureSelected: widget.onFigureSelected,
              ),
            ),
        ],
      ),
    );
  }
}
