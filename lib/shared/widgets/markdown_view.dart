import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_highlight_view.dart';

final _markdownDoc = md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
);

class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.textStyle});

  final String data;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final baseStyle = textStyle ?? const TextStyle(fontSize: 15, height: 1.6);
    final styleKey =
        '${baseStyle.fontSize}|${baseStyle.height}|${baseStyle.fontFamily}';
    final cacheKey = '$isDark|$styleKey|$data';
    final cached = _renderCache[cacheKey];
    if (cached != null) {
      _renderCacheOrder.remove(cacheKey);
      _renderCacheOrder.add(cacheKey);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cached,
      );
    }
    final renderer = _MarkdownRenderer(isDark: isDark, baseStyle: baseStyle);
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
  final nodes = _markdownDoc.parseLines(lines);
  if (_parseCache.length > 200) _parseCache.clear();
  _parseCache[data] = nodes;
  return nodes;
}

class _MarkdownRenderer {
  _MarkdownRenderer({required this.isDark, required this.baseStyle});

  final bool isDark;
  final TextStyle baseStyle;

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
        final inner = element.children
            ?.map(_visit)
            .whereType<Widget>()
            .toList();
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
            backgroundColor: isDark
                ? const Color(0xff2b303b)
                : const Color(0xffeef1f5),
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
    return _block(
      CodeHighlightView(
        code: code.replaceAll(RegExp(r'\n$'), ''),
        language: language,
        lineNumbers: false,
      ),
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
    final rawRows = <({bool isHeader, List<Widget> cells})>[];
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is! md.Element) continue;
      final cells = child.children ?? [];
      final isHeader = child.tag == 'thead';
      final rowChildren = cells.map((c) {
        if (c is! md.Element) return const SizedBox.shrink();
        final cellWidgets =
            c.children?.map(_visit).whereType<Widget>().toList() ?? [];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cellWidgets,
          ),
        );
      }).toList();
      rawRows.add((isHeader: isHeader, cells: rowChildren));
    }
    if (rawRows.isEmpty) return const SizedBox.shrink();

    final columnCount = rawRows
        .map((r) => r.cells.length)
        .reduce((a, b) => a > b ? a : b);

    final rows = rawRows.map((r) {
      final cells = <Widget>[...r.cells];
      while (cells.length < columnCount) {
        cells.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SizedBox.shrink(),
          ),
        );
      }
      return TableRow(
        decoration: r.isHeader
            ? BoxDecoration(
                color: isDark
                    ? const Color(0xff2b303b)
                    : const Color(0xfff1f5f9),
              )
            : null,
        children: cells,
      );
    }).toList();

    return Table(
      border: TableBorder.all(
        color: isDark ? const Color(0xff3f4451) : const Color(0xffe2e8f0),
        width: 1,
      ),
      columnWidths: {
        for (var i = 0; i < columnCount; i++) i: const FlexColumnWidth(),
      },
      children: rows,
    );
  }

  Widget _image(md.Element element) {
    final alt = element.attributes['alt'] ?? '';
    return _block(
      Text(alt, style: baseStyle.copyWith(fontStyle: FontStyle.italic)),
      top: 4,
      bottom: 4,
    );
  }

  Widget _text(String text, TextStyle style) => Text(text, style: style);

  void _openLink(String href) {
    if (href.isEmpty) return;
  }
}
