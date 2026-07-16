import 'package:flutter/widgets.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart' as langs;
import 'package:re_highlight/styles/atom-one-dark.dart' as dark;
import 'package:re_highlight/styles/atom-one-light.dart' as light;

final _highlighter = Highlight()..registerLanguages(langs.builtinAllLanguages);

const _spanCacheMax = 300;
final _spanCache = <String, TextSpan>{};
final _spanCacheOrder = <String>[];

TextSpan _cachedHighlight({
  required String code,
  required String? language,
  required String? path,
  required bool followTheme,
  required Brightness brightness,
}) {
  final key =
      '$brightness|${followTheme ? 1 : 0}|${language ?? ''}|${path ?? ''}|$code';
  final cached = _spanCache[key];
  if (cached != null) {
    _spanCacheOrder.remove(key);
    _spanCacheOrder.add(key);
    return cached;
  }
  final span = _computeHighlight(
    code: code,
    language: language,
    path: path,
    followTheme: followTheme,
    brightness: brightness,
  );
  _spanCache[key] = span;
  _spanCacheOrder.add(key);
  while (_spanCacheOrder.length > _spanCacheMax) {
    final evicted = _spanCacheOrder.removeAt(0);
    _spanCache.remove(evicted);
  }
  return span;
}

TextSpan _computeHighlight({
  required String code,
  required String? language,
  required String? path,
  required bool followTheme,
  required Brightness brightness,
}) {
  final themeMap = followTheme
      ? (brightness == Brightness.dark
            ? dark.atomOneDarkTheme
            : light.atomOneLightTheme)
      : dark.atomOneDarkTheme;
  final baseStyle = themeMap['root'] ?? const TextStyle();
  final lang = CodeHighlightView.detectLanguage(language, path);

  final renderer = TextSpanRenderer(baseStyle, themeMap);
  if (lang != null && langs.builtinAllLanguages.containsKey(lang)) {
    try {
      _highlighter
          .highlight(code: code, language: lang, ignoreIllegals: true)
          .render(renderer);
    } catch (_) {
      renderer.span?.children?.clear();
    }
  } else {
    try {
      _highlighter.highlightAuto(code).render(renderer);
    } catch (_) {
      renderer.span?.children?.clear();
    }
  }
  return renderer.span ?? TextSpan(text: code, style: baseStyle);
}

class CodeHighlightView extends StatelessWidget {
  const CodeHighlightView({
    super.key,
    required this.code,
    this.language,
    this.path,
    this.constraints,
    this.followTheme = true,
    this.lineNumbers = false,
    this.fontSize = 13,
  });

  final String code;
  final String? language;
  final String? path;
  final BoxConstraints? constraints;
  final bool followTheme;
  final bool lineNumbers;
  final double fontSize;

  static const monoFamilies = [
    'SF Mono',
    'JetBrains Mono',
    'Menlo',
    'Monaco',
    'Consolas',
    'Liberation Mono',
    'Courier New',
  ];

  static String? detectLanguage(String? language, String? path) {
    if (language != null && language.isNotEmpty) {
      final lower = language.toLowerCase();
      return _aliases[lower] ?? lower;
    }
    if (path == null) return null;
    final name = path.split('/').last.toLowerCase();
    if (_filenames.containsKey(name)) return _filenames[name];
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = name.substring(dot + 1);
    return _extensions[ext] ?? _extensions[ext.toLowerCase()];
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final themeMap = followTheme
        ? (brightness == Brightness.dark
              ? dark.atomOneDarkTheme
              : light.atomOneLightTheme)
        : dark.atomOneDarkTheme;
    final baseStyle = themeMap['root'] ?? const TextStyle();
    final span = _applyFont(
      _cachedHighlight(
        code: code,
        language: language,
        path: path,
        followTheme: followTheme,
        brightness: brightness,
      ),
      _monoStyle(fontSize),
    );

    final content = lineNumbers
        ? _LineNumberedCode(span: span, fontSize: fontSize)
        : RichText(text: span, textDirection: TextDirection.ltr);

    return Container(
      constraints: constraints,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            baseStyle.backgroundColor ??
            (brightness == Brightness.dark
                ? const Color(0xff282c34)
                : const Color(0xfffafafa)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: content,
        ),
      ),
    );
  }

  TextSpan _applyFont(TextSpan span, TextStyle style) {
    return TextSpan(
      text: span.text,
      children: span.children
          ?.map((e) => e is TextSpan ? _applyFont(e, style) : e)
          .toList(),
      style: (span.style ?? style).copyWith(
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        fontSize: style.fontSize,
      ),
    );
  }

  static TextStyle _monoStyle(double fontSize) => TextStyle(
    fontFamily: monoFamilies.first,
    fontFamilyFallback: monoFamilies.skip(1).toList(),
    fontSize: fontSize,
    height: 1.5,
  );
}

class _LineNumberedCode extends StatelessWidget {
  const _LineNumberedCode({required this.span, required this.fontSize});

  final TextSpan span;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final plain = _toPlain(span);
    final lines = plain.split('\n');
    final gutterWidth = '${lines.length}'.length;
    final muted = MediaQuery.of(context).platformBrightness == Brightness.dark
        ? const Color(0xff7a8290)
        : const Color(0xff6b7280);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < lines.length; i++)
                Text(
                  '${i + 1}'.padLeft(gutterWidth),
                  style: TextStyle(
                    fontFamily: CodeHighlightView.monoFamilies.first,
                    fontFamilyFallback: CodeHighlightView.monoFamilies
                        .skip(1)
                        .toList(),
                    fontSize: fontSize,
                    height: 1.5,
                    color: muted,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RichText(text: span, textDirection: TextDirection.ltr),
        ),
      ],
    );
  }

  String _toPlain(TextSpan span) {
    final buffer = StringBuffer(span.text ?? '');
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) buffer.write(_toPlain(child));
    }
    return buffer.toString();
  }
}

const _aliases = <String, String>{
  'js': 'javascript',
  'ts': 'typescript',
  'sh': 'bash',
  'shell': 'bash',
  'py': 'python',
  'yml': 'yaml',
  'golang': 'go',
  'c++': 'cpp',
  'c#': 'csharp',
  'cs': 'csharp',
  'objectivec': 'objectivec',
  'md': 'markdown',
  'tex': 'latex',
};

const _filenames = <String, String>{
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  '.gitignore': 'gitignore',
  'gemfile': 'ruby',
  'rakefile': 'ruby',
};

const _extensions = <String, String>{
  'dart': 'dart',
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'rb': 'ruby',
  'go': 'go',
  'rs': 'rust',
  'java': 'java',
  'kt': 'kotlin',
  'swift': 'swift',
  'c': 'c',
  'h': 'c',
  'cpp': 'cpp',
  'cc': 'cpp',
  'hpp': 'cpp',
  'cs': 'csharp',
  'php': 'php',
  'html': 'xml',
  'htm': 'xml',
  'xml': 'xml',
  'svg': 'xml',
  'css': 'css',
  'scss': 'scss',
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'ini',
  'ini': 'ini',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'sql': 'sql',
  'md': 'markdown',
  'mk': 'makefile',
  'lua': 'lua',
  'ex': 'elixir',
  'exs': 'elixir',
  'erl': 'erlang',
  'hs': 'haskell',
  'scala': 'scala',
  'pl': 'perl',
  'r': 'r',
  'gradle': 'groovy',
  'tf': 'terraform',
  'vue': 'xml',
  'proto': 'protobuf',
  'tex': 'latex',
  'txt': 'plaintext',
};
