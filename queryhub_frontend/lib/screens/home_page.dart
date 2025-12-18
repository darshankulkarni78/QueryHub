import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../state/app_state.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final app = context.read<AppState>();
      app.loadDocuments();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload(AppState app) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        print('📁 File picker cancelled or no file selected');
        return;
      }

      final file = result.files.single;
      if (file.bytes == null) {
        print('❌ File bytes are null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to read file. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      print(
          '📁 Selected file: ${file.name}, size: ${file.bytes!.length} bytes');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploading ${file.name}...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await app.uploadDocument(
        filename: file.name,
        bytes: file.bytes!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Upload error in UI: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('About QueryHub'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QueryHub is a document-grounded AI assistant. '
                  'Upload PDFs, DOCX, or text files, then ask questions. '
                  'Answers are generated using a RAG (retrieval-augmented generation) backend.',
                ),
                SizedBox(height: 12),
                Text(
                  'How it works',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Your documents are chunked, embedded, and indexed in a vector database. '
                  'For each question, the most relevant chunks are retrieved and sent to the model as context.',
                ),
                SizedBox(height: 12),
                Text(
                  'Privacy',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Documents are used only for this local user. There is no multi-user account system yet.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<AppState>(
      builder: (context, app, _) {
        final hasSessions = app.sessions.isNotEmpty;
        final active = app.activeSession;

        if (!hasSessions && app.hasReadyDocuments) {
          // Schedule chat creation after this build frame to avoid
          // calling notifyListeners() during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final appAfterFrame = context.read<AppState>();
              if (appAfterFrame.sessions.isEmpty &&
                  appAfterFrame.hasReadyDocuments) {
                appAfterFrame.createNewChat();
              }
            }
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= 900;

            final sidebar = Container(
              width: isWide ? 320 : double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.9),
                borderRadius: isWide
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                      )
                    : const BorderRadius.vertical(top: Radius.circular(18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                gradient: LinearGradient(
                                  colors: [
                                    theme.colorScheme.primary,
                                    theme.colorScheme.secondary,
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.hub_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'QueryHub',
                              style: theme.textTheme.titleMedium!.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed:
                              app.hasReadyDocuments ? app.createNewChat : null,
                          icon:
                              const Icon(Icons.add_comment_outlined, size: 18),
                          label: const Text('New Chat'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Chat sessions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Chats',
                      style: theme.textTheme.labelSmall!
                          .copyWith(color: theme.hintColor),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: app.sessions.length,
                      itemBuilder: (context, index) {
                        final chat = app.sessions[index];
                        final isActive = app.activeSession?.id == chat.id;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Material(
                            color: isActive
                                ? theme.colorScheme.primary.withOpacity(0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => app.selectChat(chat.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 16,
                                      color: isActive
                                          ? theme.colorScheme.primary
                                          : theme.hintColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            chat.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium!
                                                .copyWith(
                                              fontWeight: isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                          Text(
                                            chat.humanCreatedAt,
                                            style: theme.textTheme.bodySmall!
                                                .copyWith(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      color: theme.colorScheme.error,
                                      tooltip: 'Delete chat',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Delete chat?'),
                                            content: const Text(
                                              'This will remove this chat session and its messages from this device.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx)
                                                        .pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          app.deleteChat(chat.id);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Documents
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: [
                        Text(
                          'Documents',
                          style: theme.textTheme.labelSmall!
                              .copyWith(color: theme.hintColor),
                        ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Upload'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          onPressed: () => _pickAndUpload(app),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 170,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 8,
                        right: 8,
                        bottom: 10,
                      ),
                      itemCount: app.documents.length,
                      itemBuilder: (context, index) {
                        final doc = app.documents[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  doc.filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _DocumentStatusChip(status: doc.status),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                color: theme.colorScheme.error,
                                tooltip: 'Delete document',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete document?'),
                                      content: const Text(
                                        'This will remove the document and its index from the workspace.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await app.deleteDocument(doc.id);
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );

            final chatArea = Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildMainArea(context, app, active),
                      ),
                    ),
                  ),
                ),
                _buildInputBar(app),
              ],
            );

            return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    const Icon(Icons.terminal_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text('QueryHub – RAG Workspace'),
                  ],
                ),
                elevation: 0,
                actions: [
                  TextButton.icon(
                    onPressed: () => _showAboutDialog(context),
                    icon: const Icon(Icons.info_outline, color: Colors.white),
                    label: const Text(
                      'About',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              body: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.surfaceVariant.withOpacity(0.6),
                      theme.colorScheme.background,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: isWide
                          ? Row(
                              children: [
                                sidebar,
                                const SizedBox(width: 12),
                                Expanded(child: chatArea),
                              ],
                            )
                          : Column(
                              children: [
                                sidebar,
                                const SizedBox(height: 12),
                                Expanded(child: chatArea),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMainArea(
    BuildContext context,
    AppState app,
    ChatSession? active,
  ) {
    final theme = Theme.of(context);
    if (!app.hasReadyDocuments) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_file, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Upload documents to start',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Once your documents are processed, you can start asking questions.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (active == null) {
      return Center(
        child: Text(
          'No active chat. Create a new chat from the sidebar.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    if (active.messages.isEmpty) {
      return Center(
        child: Text(
          'Ask your first question about your documents.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: active.messages.length,
      itemBuilder: (context, index) {
        final msg = active.messages[index];
        final isUser = msg.role == MessageRole.user;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? 'You' : 'Assistant',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceVariant
                              .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      msg.content,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  if (msg.contexts.isNotEmpty && !isUser)
                    TextButton(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (ctx) {
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: ListView.separated(
                                itemCount: msg.contexts.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (ctx, i) {
                                  final ctxChunk = msg.contexts[i];
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Score: ${ctxChunk.score.toStringAsFixed(3)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        ctxChunk.text,
                                        style: const TextStyle(
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                      child: const Text(
                        'View sources',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar(AppState app) {
    final canType = app.hasReadyDocuments;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        border: const Border(
          top: BorderSide(color: Colors.black12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              enabled: canType && !app.isAsking,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: canType
                    ? 'Ask a question about your documents...'
                    : 'Upload documents to start',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _onSend(app),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Send',
            onPressed: canType && !app.isAsking ? () => _onSend(app) : null,
            icon: app.isAsking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Future<void> _onSend(AppState app) async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();

    try {
      await app.sendMessage(text);
      // Scroll to bottom after message is added
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      // Show error snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get answer: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}

class _DocumentStatusChip extends StatelessWidget {
  final String status;

  const _DocumentStatusChip({required this.status});

  Color _color(BuildContext context) {
    switch (status) {
      case 'done':
        return Colors.green;
      case 'processing':
      case 'uploading':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Theme.of(context).disabledColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color(context).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          color: _color(context),
        ),
      ),
    );
  }
}
