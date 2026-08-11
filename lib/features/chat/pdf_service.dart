import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/models/message.dart';

Future<Uint8List> buildMessagePdf(MessageWithParts message) async {
  final doc = pw.Document();
  final font = await PdfGoogleFonts.nunitoRegular();
  final boldFont = await PdfGoogleFonts.nunitoBold();
  final italicFont = await PdfGoogleFonts.nunitoItalic();
  final monoFont = await PdfGoogleFonts.firaCodeRegular();

  final text = message.parts
      .where((p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
      .map((p) => p.text!)
      .join('\n\n');

  final role = message.info.role == 'user' ? 'You' : 'Assistant';
  final timestamp = message.info.timeCreated != null
      ? DateFormat.yMMMd().add_jm().format(
          DateTime.fromMillisecondsSinceEpoch(message.info.timeCreated!))
      : '';

  final elements = <pw.Widget>[
    pw.Header(
      level: 0,
      child: pw.Text(
        'SparkCode Export',
        style: pw.TextStyle(
            font: boldFont, fontSize: 18, color: PdfColors.grey700),
      ),
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      '$role${timestamp.isNotEmpty ? ' · $timestamp' : ''}',
      style:
          pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.grey500),
    ),
    pw.Divider(color: PdfColors.grey300),
    pw.SizedBox(height: 12),
  ];

  final ast = md.Document().parse(text);
  elements.addAll(_renderAst(ast, font, boldFont, italicFont, monoFont));

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => elements,
    ),
  );

  return doc.save();
}

List<pw.Widget> _renderAst(
  List<md.Node> nodes,
  pw.Font font,
  pw.Font boldFont,
  pw.Font italicFont,
  pw.Font monoFont,
) {
  final widgets = <pw.Widget>[];
  for (final node in nodes) {
    widgets.addAll(_renderNode(node, font, boldFont, italicFont, monoFont));
  }
  return widgets;
}

List<pw.Widget> _renderNode(
  md.Node node,
  pw.Font font,
  pw.Font boldFont,
  pw.Font italicFont,
  pw.Font monoFont,
) {
  if (node is md.Element) {
    return _renderElement(node, font, boldFont, italicFont, monoFont);
  }
  if (node is md.Text) {
    return [
      pw.Paragraph(
          text: node.textContent,
          style: pw.TextStyle(font: font, fontSize: 11, lineSpacing: 5))
    ];
  }
  return [];
}

List<pw.Widget> _renderElement(
  md.Element element,
  pw.Font font,
  pw.Font boldFont,
  pw.Font italicFont,
  pw.Font monoFont,
) {
  switch (element.tag) {
    case 'h1':
      return [_heading(element, 20, boldFont)];
    case 'h2':
      return [_heading(element, 17, boldFont)];
    case 'h3':
      return [_heading(element, 14, boldFont)];
    case 'h4':
    case 'h5':
    case 'h6':
      return [_heading(element, 12, boldFont)];
    case 'p':
      return [_paragraph(element, font, boldFont, italicFont, monoFont)];
    case 'pre':
      return [_codeBlock(element, monoFont)];
    case 'code':
      return [_inlineCode(element, monoFont)];
    case 'ul':
      return _list(element, false, font, boldFont, italicFont, monoFont);
    case 'ol':
      return _list(element, true, font, boldFont, italicFont, monoFont);
    case 'blockquote':
      return [_blockquote(element, font, boldFont, italicFont, monoFont)];
    case 'hr':
      return [pw.Divider(color: PdfColors.grey300), pw.SizedBox(height: 8)];
    case 'table':
      return [_table(element, font, boldFont)];
    case 'a':
      return [_link(element, font)];
    case 'strong':
      return [_styledText(element, boldFont)];
    case 'em':
      return [_styledText(element, italicFont)];
    case 'del':
      return [_styledText(element, font)];
    case 'img':
      return [
        pw.Paragraph(
            text: '[image]',
            style: pw.TextStyle(
                font: font, fontSize: 11, color: PdfColors.grey500))
      ];
    case 'br':
      return [pw.SizedBox(height: 8)];
    default:
      if (element.children != null && element.children!.isNotEmpty) {
        return _renderAst(
            element.children!, font, boldFont, italicFont, monoFont);
      }
      return [];
  }
}

pw.Widget _heading(md.Element element, double fontSize, pw.Font font) {
  final text = _extractText(element);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
          font: font, fontSize: fontSize, color: PdfColors.grey800),
    ),
  );
}

pw.Widget _paragraph(
  md.Element element,
  pw.Font font,
  pw.Font boldFont,
  pw.Font italicFont,
  pw.Font monoFont,
) {
  final text = _extractText(element);
  return pw.Paragraph(
    style: pw.TextStyle(font: font, fontSize: 11, lineSpacing: 5),
    text: text,
  );
}

pw.Widget _codeBlock(md.Element element, pw.Font monoFont) {
  final code = _extractText(element);
  return pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 8),
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      code.trimRight(),
      style:
          pw.TextStyle(font: monoFont, fontSize: 10, color: PdfColors.grey800),
    ),
  );
}

pw.Widget _inlineCode(md.Element element, pw.Font monoFont) {
  final text = _extractText(element);
  return pw.Text(
    text,
    style: pw.TextStyle(font: monoFont, fontSize: 10, color: PdfColors.grey700),
  );
}

List<pw.Widget> _list(
  md.Element element,
  bool ordered,
  pw.Font font,
  pw.Font boldFont,
  pw.Font italicFont,
  pw.Font monoFont,
) {
  final items = <pw.Widget>[];
  var index = 1;
  for (final child in element.children ?? []) {
    if (child is md.Element && child.tag == 'li') {
      final bullet = ordered ? '$index.' : '•';
      final text = _extractText(child);
      items.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 20,
                child: pw.Text(
                  '$bullet ',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  text,
                  style: pw.TextStyle(font: font, fontSize: 11, lineSpacing: 5),
                ),
              ),
            ],
          ),
        ),
      );
      index++;
    }
  }
  return items;
}

pw.Widget _blockquote(
  md.Element element,
  pw.Font font,
  pw.Font boldFont,
  pw.Font italicFont,
  pw.Font monoFont,
) {
  final text = _extractText(element);
  return pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 8),
    padding: const pw.EdgeInsets.only(left: 12),
    decoration: pw.BoxDecoration(
      border:
          pw.Border(left: pw.BorderSide(color: PdfColors.grey400, width: 2)),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font: italicFont,
        fontSize: 11,
        color: PdfColors.grey600,
        fontStyle: pw.FontStyle.italic,
        lineSpacing: 5,
      ),
    ),
  );
}

pw.Widget _table(md.Element element, pw.Font font, pw.Font boldFont) {
  final rows = <List<String>>[];
  for (final row in element.children ?? []) {
    if (row is md.Element) {
      final cells = <String>[];
      for (final cell in row.children ?? []) {
        cells.add(_extractText(cell));
      }
      rows.add(cells);
    }
  }
  if (rows.isEmpty) return pw.SizedBox.shrink();

  return pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(font: boldFont, fontSize: 10),
    cellStyle: pw.TextStyle(font: font, fontSize: 10),
    cellPadding: const pw.EdgeInsets.all(4),
    headerPadding: const pw.EdgeInsets.all(4),
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    headers: rows.isNotEmpty ? rows.first : [],
    data: rows.length > 1 ? rows.sublist(1) : [],
  );
}

pw.Widget _link(md.Element element, pw.Font font) {
  final text = _extractText(element);
  final url = element.attributes['href'] ?? '';
  return pw.Text(
    '$text ($url)',
    style: pw.TextStyle(
      font: font,
      fontSize: 11,
      color: PdfColors.blue700,
      decoration: pw.TextDecoration.underline,
    ),
  );
}

pw.Widget _styledText(md.Element element, pw.Font font) {
  final text = _extractText(element);
  return pw.Text(
    text,
    style: pw.TextStyle(font: font, fontSize: 11),
  );
}

String _extractText(md.Element element) {
  final buffer = StringBuffer();
  for (final child in element.children ?? []) {
    if (child is md.Text) {
      buffer.write(child.textContent);
    } else if (child is md.Element) {
      buffer.write(_extractText(child));
    }
  }
  return buffer.toString();
}
