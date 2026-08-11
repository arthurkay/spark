import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;
import 'package:url_launcher/url_launcher.dart';

import '../data_uri_cache.dart';
import 'code_highlight_view.dart';

/// A fresh Document per parse.
///
/// `md.Document` accumulates link-reference definitions as it parses, so a
/// single shared instance leaked references between unrelated messages.
md.Document _newMarkdownDoc() => md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );

class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.textStyle});

  final String data;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final baseStyle = textStyle ?? const TextStyle(fontSize: 15, height: 1.6);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final styleKey =
        '${baseStyle.fontSize}|${baseStyle.height}|${baseStyle.fontFamily}';
    final cacheKey = '$isDark|$styleKey|$devicePixelRatio|$data';
    final cached = _renderCache[cacheKey];
    if (cached != null) {
      _renderCacheOrder.remove(cacheKey);
      _renderCacheOrder.add(cacheKey);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cached,
      );
    }
    final renderer = _MarkdownRenderer(
      isDark: isDark,
      baseStyle: baseStyle,
      devicePixelRatio: devicePixelRatio,
    );
    final nodes = _parse(data);
    final widgets = renderer.render(nodes);
    _renderCache[cacheKey] = widgets;
    _renderCacheOrder.add(cacheKey);
    while (_renderCacheOrder.length > _renderCacheMax) {
      _renderCache.remove(_renderCacheOrder.removeAt(0));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}

const _renderCacheMax = 200;
final Map<String, List<Widget>> _renderCache = {};
final List<String> _renderCacheOrder = [];

final Map<String, List<md.Node>> _parseCache = {};

List<md.Node> _parse(String data) {
  final cached = _parseCache[data];
  if (cached != null) return cached;
  final lines = data.replaceAll('\r\n', '\n').split('\n');
  final nodes = _newMarkdownDoc().parseLines(lines);
  // Evict the oldest entry instead of clearing everything: a wholesale clear
  // meant periodically re-parsing every message still on screen.
  if (_parseCache.length >= 200) _parseCache.remove(_parseCache.keys.first);
  _parseCache[data] = nodes;
  return nodes;
}

/// Inline markdown images render at a fixed logical width.
const _mdImageWidth = 300.0;

class _MarkdownRenderer {
  _MarkdownRenderer({
    required this.isDark,
    required this.baseStyle,
    required this.devicePixelRatio,
  });

  final bool isDark;
  final TextStyle baseStyle;
  final double devicePixelRatio;

  /// Physical-pixel decode width, so images aren't decoded at full source
  /// resolution just to be drawn 300px wide.
  int get _mdDecodeWidth => decodeWidthFor(_mdImageWidth, devicePixelRatio);

  List<Widget> render(List<md.Node> nodes) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      final w = _visit(node);
      if (w != null) widgets.add(w);
    }
    return widgets;
  }

  Widget? _visit(md.Node node) {
    if (node is md.Text) return _text(node.textContent, baseStyle);
    if (node is! md.Element) return null;
    return _visitElement(node);
  }

  Widget? _visitElement(md.Element element) {
    switch (element.tag) {
      case 'h1':
        return _block(
          _spans(
            element,
            baseStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          top: 12,
          bottom: 6,
        );
      case 'h2':
        return _block(
          _spans(
            element,
            baseStyle.copyWith(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          top: 10,
          bottom: 5,
        );
      case 'h3':
        return _block(
          _spans(
            element,
            baseStyle.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          top: 8,
          bottom: 4,
        );
      case 'h4':
      case 'h5':
      case 'h6':
        return _block(
          _spans(
            element,
            baseStyle.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          top: 8,
          bottom: 4,
        );
      case 'p':
        return _block(_spans(element, baseStyle));
      case 'blockquote':
        return _block(
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isDark
                      ? const Color(0xff3f4451)
                      : const Color(0xffe2e8f0),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children:
                  element.children?.map(_visit).whereType<Widget>().toList() ??
                      [],
            ),
          ),
          top: 4,
          bottom: 4,
        );
      case 'hr':
        return _block(
          Container(
            height: 1,
            color: isDark ? const Color(0xff3f4451) : const Color(0xffe2e8f0),
          ),
          top: 8,
          bottom: 8,
        );
      case 'pre':
        return _codeBlock(element);
      case 'ul':
        return _list(element, false);
      case 'ol':
        return _list(element, true);
      case 'table':
        return _block(_table(element), top: 6, bottom: 6);
      case 'img':
        return _image(element);
      default:
        final inner =
            element.children?.map(_visit).whereType<Widget>().toList();
        if (inner == null || inner.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: inner,
        );
    }
  }

  Widget _block(Widget child, {double top = 2, double bottom = 2}) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: child,
    );
  }

  Widget _spans(md.Element element, TextStyle style) {
    final spans = <InlineSpan>[];
    for (final child in element.children ?? const <md.Node>[]) {
      spans.add(_inline(child, style));
    }
    return Text.rich(TextSpan(children: spans, style: style));
  }

  InlineSpan _inline(md.Node node, TextStyle style) {
    if (node is md.Text) {
      return TextSpan(text: node.textContent, style: style);
    }
    if (node is! md.Element) {
      return TextSpan(text: node.textContent, style: style);
    }
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        return TextSpan(
          children: children.map((c) => _inline(c, _bold(style))).toList(),
          style: _bold(style),
        );
      case 'em':
        return TextSpan(
          children: children
              .map(
                (c) => _inline(c, style.copyWith(fontStyle: FontStyle.italic)),
              )
              .toList(),
          style: style.copyWith(fontStyle: FontStyle.italic),
        );
      case 'del':
        return TextSpan(
          children: children
              .map(
                (c) => _inline(
                  c,
                  style.copyWith(decoration: TextDecoration.lineThrough),
                ),
              )
              .toList(),
          style: style.copyWith(decoration: TextDecoration.lineThrough),
        );
      case 'a':
        final href = node.attributes['href'] ?? '';
        return WidgetSpan(
          child: GestureDetector(
            onTap: () => _openLink(href),
            child: Text.rich(
              TextSpan(
                children: children.map((c) => _inline(c, style)).toList(),
                style: style.copyWith(
                  color: isDark
                      ? const Color(0xff7aa2f7)
                      : const Color(0xff2563eb),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        );
      case 'code':
        return TextSpan(
          text: children.whereType<md.Text>().map((t) => t.textContent).join(),
          style: style.copyWith(
            fontFamily: CodeHighlightView.monoFamilies.first,
            fontFamilyFallback: CodeHighlightView.monoFamilies.skip(1).toList(),
            backgroundColor:
                isDark ? const Color(0xff2b303b) : const Color(0xffeef1f5),
            fontSize: (style.fontSize ?? 14) * 0.92,
          ),
        );
      case 'img':
        return TextSpan(text: node.attributes['alt'] ?? '');
      default:
        return TextSpan(
          children: children.map((c) => _inline(c, style)).toList(),
        );
    }
  }

  TextStyle _bold(TextStyle style) =>
      style.copyWith(fontWeight: FontWeight.bold);

  Widget _codeBlock(md.Element element) {
    String code = '';
    String? language;
    final child = element.children?.first;
    if (child is md.Element && child.tag == 'code') {
      code = child.textContent;
      final cls = child.attributes['class'] ?? '';
      final match = RegExp(r'language-(\w+)').firstMatch(cls);
      if (match != null) language = match.group(1);
    }
    final cleaned = code.replaceAll(RegExp(r'\n$'), '');
    return _block(
      _CopyableCode(code: cleaned, language: language),
      top: 4,
      bottom: 4,
    );
  }

  Widget _list(md.Element element, bool ordered) {
    final items = element.children ?? [];
    final widgets = <Widget>[];
    var index = 1;
    for (final item in items) {
      if (item is! md.Element || item.tag != 'li') continue;
      final marker = ordered ? '$index.' : '•';
      index++;
      final content =
          item.children?.map(_visit).whereType<Widget>().toList() ?? [];
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Text(marker, style: baseStyle)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _block(Column(children: widgets), top: 2, bottom: 2);
  }

  Widget _table(md.Element element) {
    final rawRows = <({bool isHeader, List<String> textCells})>[];
    for (final section in element.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      final isSectionHeader = section.tag == 'thead';
      for (final tr in section.children ?? const <md.Node>[]) {
        if (tr is! md.Element) continue;
        final cells = tr.children ?? [];
        final textCells = cells.map((c) {
          if (c is! md.Element) return '';
          return c.textContent.trim();
        }).toList();
        rawRows.add((isHeader: isSectionHeader, textCells: textCells));
      }
    }
    if (rawRows.isEmpty) return const SizedBox.shrink();

    final headerRow = rawRows.firstWhere(
      (r) => r.isHeader,
      orElse: () => rawRows.first,
    );
    final bodyRows = rawRows.where((r) => !r.isHeader).toList();
    final bodyColumnCount = bodyRows.isNotEmpty
        ? bodyRows
            .map((r) => r.textCells.length)
            .reduce((a, b) => a > b ? a : b)
        : headerRow.textCells.length;

    List<String> headerLabels = headerRow.textCells;
    if (headerLabels.length < bodyColumnCount && bodyColumnCount > 1) {
      headerLabels = _splitTransposedHeader(headerLabels, bodyColumnCount);
    }

    final columnCount = headerLabels.length > bodyColumnCount
        ? headerLabels.length
        : bodyColumnCount;

    Widget makeCell(String text, {bool isHeader = false, bool isBold = false}) {
      final style = baseStyle.copyWith(
        fontSize: 13,
        fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(text, style: style, maxLines: 10),
      );
    }

    final headerWidgets =
        headerLabels.map((t) => makeCell(t, isHeader: true)).toList();
    while (headerWidgets.length < columnCount) {
      headerWidgets.add(makeCell(''));
    }

    final dataRows = bodyRows.map((r) {
      final cells = r.textCells.map((t) => makeCell(t)).toList();
      while (cells.length < columnCount) {
        cells.add(makeCell(''));
      }
      return cells;
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            border: TableBorder.all(
              color: isDark ? const Color(0xff3f4451) : const Color(0xffe2e8f0),
              width: 1,
            ),
            columnWidths: {
              for (var i = 0; i < columnCount; i++)
                i: const IntrinsicColumnWidth(),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xff2b303b)
                      : const Color(0xfff1f5f9),
                ),
                children: headerWidgets,
              ),
              for (final row in dataRows) TableRow(children: row),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _splitTransposedHeader(List<String> cells, int targetCount) {
    if (cells.isEmpty) return cells;
    final first = cells.first;
    if (cells.length == 1 && first.contains(RegExp(r'\s{2,}|\n'))) {
      return first
          .split(RegExp(r'\s{2,}|\n'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (cells.length == 1) {
      final words =
          first.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (words.length >= targetCount) return words.sublist(0, targetCount);
      if (words.length > 1) return words;
    }
    return cells;
  }

  Widget _image(md.Element element) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    if (src.isEmpty) {
      return _block(
        Text(alt, style: baseStyle.copyWith(fontStyle: FontStyle.italic)),
        top: 4,
        bottom: 4,
      );
    }
    return _block(
      _buildImage(src, alt),
      top: 4,
      bottom: 4,
    );
  }

  Widget _buildImage(String src, String alt) {
    if (src.startsWith('data:image/svg') || src.endsWith('.svg')) {
      return _buildSvg(src, alt);
    }
    if (src.startsWith('data:')) {
      return _buildDataImage(src, alt);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        src,
        fit: BoxFit.contain,
        width: _mdImageWidth,
        cacheWidth: _mdDecodeWidth,
        errorBuilder: (_, __, ___) => Text(
          alt.isNotEmpty ? alt : 'Image failed to load',
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  Widget _buildSvg(String src, String alt) {
    if (src.startsWith('data:')) {
      final decoded = DataUriCache.textOf(src);
      if (decoded == null) {
        return Text(
          alt.isNotEmpty ? alt : 'Image failed to load',
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        );
      }
      return SvgPicture.string(
        decoded,
        width: _mdImageWidth,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Text(
          alt.isNotEmpty ? alt : 'Loading SVG...',
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    return SvgPicture.network(
      src,
      width: _mdImageWidth,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => Text(
        alt.isNotEmpty ? alt : 'Loading SVG...',
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildDataImage(String src, String alt) {
    // Cached bytes: handing the same list instance to Image.memory on every
    // build is what lets the image cache hit instead of re-decoding.
    final bytes = DataUriCache.bytesOf(src);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          width: _mdImageWidth,
          cacheWidth: _mdDecodeWidth,
          errorBuilder: (_, __, ___) => Text(
            alt.isNotEmpty ? alt : 'Image failed to load',
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      );
    } else {
      return Text(
        alt.isNotEmpty ? alt : 'Invalid image data',
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      );
    }
  }

  Widget _text(String text, TextStyle style) => Text(text, style: style);

  void _openLink(String href) {
    if (href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _CopyableCode extends StatefulWidget {
  const _CopyableCode({required this.code, this.language});

  final String code;
  final String? language;

  @override
  State<_CopyableCode> createState() => _CopyableCodeState();
}

class _CopyableCodeState extends State<_CopyableCode> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Stack(
      children: [
        CodeHighlightView(
          code: widget.code,
          language: widget.language,
          lineNumbers: false,
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: _copy,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xff3f4451).withAlpha(180)
                    : const Color(0xffe2e8f0).withAlpha(180),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _copied ? LucideIcons.check : LucideIcons.copy,
                size: 12,
                color:
                    isDark ? const Color(0xffa0aec0) : const Color(0xff64748b),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
