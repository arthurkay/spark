import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../shared/widgets/themed_pdf_view.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  const PdfReaderScreen({
    super.key,
    required this.sessionId,
    required this.path,
    this.directory,
  });

  final String sessionId;
  final String path;
  final String? directory;

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  late Future<FileContent> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = _fetch();
  }

  Future<FileContent> _fetch() {
    final client = ref.read(opencodeClientProvider);
    if (client == null) {
      return Future.error(OpencodeApiException('Not connected'));
    }
    return client.readFile(widget.path, directory: widget.directory);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: Text(
            widget.path.split('/').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      child: FutureBuilder<FileContent>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                snapshot.error is OpencodeApiException
                    ? (snapshot.error as OpencodeApiException).message
                    : '${snapshot.error}',
              ).muted,
            );
          }
          final bytes = snapshot.data?.decodedBytes;
          if (bytes == null || bytes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.fileWarning,
                    size: 36,
                  ).iconMutedForeground,
                  const Gap(12),
                  const Text('Could not load PDF').muted,
                ],
              ),
            );
          }
          return ThemedPdfView(data: bytes, sourceName: widget.path);
        },
      ),
    );
  }
}
