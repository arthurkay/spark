import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const _invertMatrix = <double>[
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
];

class ThemedPdfView extends StatefulWidget {
  const ThemedPdfView({
    super.key,
    required this.data,
    required this.sourceName,
  });

  final Uint8List data;
  final String sourceName;

  @override
  State<ThemedPdfView> createState() => _ThemedPdfViewState();
}

class _ThemedPdfViewState extends State<ThemedPdfView> {
  bool? _invertOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final invert =
        _invertOverride ??
        (MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final viewer = PdfViewer.data(
      widget.data,
      sourceName: widget.sourceName,
      params: PdfViewerParams(backgroundColor: scheme.background),
    );
    return Stack(
      children: [
        if (invert)
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(_invertMatrix),
            child: viewer,
          )
        else
          viewer,
        Positioned(
          right: 12,
          bottom: 12,
          child: GestureDetector(
            onTap: () => setState(() => _invertOverride = !invert),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.card,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.border),
              ),
              child: Icon(
                LucideIcons.contrast,
                size: 18,
                color: invert ? scheme.primary : scheme.mutedForeground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
