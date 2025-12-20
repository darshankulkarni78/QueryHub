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
  final Set<String> _expandedDocuments = {}; // Track which documents are expanded

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final app = context.read<AppState>();
      await app.loadDocuments();
      // Auto-select and expand first ready document if none selected
      if (app.selectedDocumentId == null && app.documents.isNotEmpty) {
        final readyDocs = app.documents.where((d) => d.isReady).toList();
        if (readyDocs.isNotEmpty) {
          final firstDoc = readyDocs.first;
          setState(() {
            _expandedDocuments.add(firstDoc.id);
          });
          app.selectDocument(firstDoc.id);
        }
      }
      // Load all chat sessions
      await app.loadChatSessions();
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
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.hub_outlined,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Text('About QueryHub'),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'QueryHub is a RAG-powered document assistant. '
                  'Upload PDFs, DOCX, or text files, then ask questions. '
                  'Answers are generated using retrieval-augmented generation.',
                ),
                SizedBox(height: 16),
                Text(
                  '🔍 How it works',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SizedBox(height: 8),
                Text(
                  '1. Documents are uploaded to cloud storage\n'
                  '2. Text is extracted and chunked\n'
                  '3. Embeddings are generated and indexed\n'
                  '4. Questions retrieve relevant chunks\n'
                  '5. AI generates answers from context',
                  style: TextStyle(fontSize: 13),
                ),
                SizedBox(height: 16),
                Text(
                  '🛠️ Technology Stack',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SizedBox(height: 8),
                Text(
                  '• Backend: FastAPI + Python\n'
                  '• Storage: Supabase\n'
                  '• Vector DB: Qdrant\n'
                  '• AI: OpenRouter (Llama 3.3)\n'
                  '• Frontend: Flutter',
                  style: TextStyle(fontSize: 13),
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
                appAfterFrame.createNewChat(); // Async, but we don't need to await
              }
            }
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= 1024;
            final bool isMedium = constraints.maxWidth >= 768 && constraints.maxWidth < 1024;
            final bool isMobile = constraints.maxWidth < 768;

            final sidebar = Container(
              width: isWide ? 320 : (isMedium ? 280 : double.infinity),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.9),
                borderRadius: (isWide || isMedium)
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
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Documents section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Text(
                          'Documents',
                          style: theme.textTheme.labelSmall!
                              .copyWith(color: theme.hintColor),
                        ),
                        const Spacer(),
                        if (app.hasProcessingDocuments)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('New'),
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
                  // Documents list with nested chats (folder structure)
                  Expanded(
                    child: app.documents.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                'No documents yet',
                                style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(
                              left: 8,
                              right: 8,
                              bottom: 8,
                            ),
                            itemCount: app.documents.length,
                            itemBuilder: (context, index) {
                              final doc = app.documents[index];
                              final isExpanded = _expandedDocuments.contains(doc.id);
                              final docChats = app.getSessionsForDocument(doc.id);
                              final hasChats = docChats.isNotEmpty;
                              
                              return Column(
                                children: [
                                  // Document folder
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceVariant
                                          .withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          setState(() {
                                            if (isExpanded) {
                                              _expandedDocuments.remove(doc.id);
                                            } else {
                                              _expandedDocuments.add(doc.id);
                                              app.selectDocument(doc.id);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              // Expand/collapse icon
                                              Icon(
                                                isExpanded
                                                    ? Icons.keyboard_arrow_down
                                                    : Icons.keyboard_arrow_right,
                                                size: 16,
                                                color: theme.hintColor,
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                isExpanded
                                                    ? Icons.folder_open
                                                    : Icons.folder_outlined,
                                                size: 18,
                                                color: theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      doc.filename,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        _DocumentStatusChip(
                                                            status: doc.status),
                                                        if (hasChats) ...[
                                                          const SizedBox(width: 6),
                                                          Icon(
                                                            Icons.chat_bubble_outline,
                                                            size: 10,
                                                            color: theme.hintColor,
                                                          ),
                                                          const SizedBox(width: 2),
                                                          Text(
                                                            '${docChats.length}',
                                                            style: theme.textTheme
                                                                .bodySmall!
                                                                .copyWith(
                                                              fontSize: 10,
                                                              color: theme.hintColor,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // New Chat button (only when expanded and ready)
                                              if (isExpanded && doc.isReady)
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.add_comment_outlined,
                                                    size: 16,
                                                  ),
                                                  color: theme.colorScheme.primary,
                                                  tooltip: 'New Chat',
                                                  onPressed: () async {
                                                    app.selectDocument(doc.id);
                                                    await app.createNewChat();
                                                    // Ensure folder stays expanded after creating chat
                                                    setState(() {
                                                      _expandedDocuments.add(doc.id);
                                                    });
                                                  },
                                                ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 16,
                                                ),
                                                color: theme.colorScheme.error,
                                                tooltip: 'Delete document',
                                                onPressed: () async {
                                                  final confirm =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text(
                                                          'Delete document?'),
                                                      content: Text(
                                                        'This will remove the document and all ${docChats.length} chat session(s) from the workspace.',
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
                                                              Navigator.of(ctx)
                                                                  .pop(true),
                                                          child: const Text('Delete'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    await app.deleteDocument(doc.id);
                                                    setState(() {
                                                      _expandedDocuments.remove(doc.id);
                                                    });
                                                    if (app.selectedDocumentId == doc.id) {
                                                      app.selectDocument(null);
                                                    }
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Nested chats (shown when folder is expanded)
                                  if (isExpanded) ...[
                                    if (docChats.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 32,
                                          right: 8,
                                          top: 4,
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          'No chats yet',
                                          style: TextStyle(
                                            color: theme.hintColor,
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      )
                                    else
                                      ...docChats.map((chat) {
                                        final isActive =
                                            app.activeSession?.id == chat.id;
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            left: 28,
                                            right: 4,
                                            top: 2,
                                            bottom: 2,
                                          ),
                                          child: Material(
                                            color: isActive
                                                ? theme.colorScheme.primary
                                                    .withOpacity(0.08)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () {
                                                app.selectDocument(doc.id);
                                                app.selectChat(chat.id);
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 6,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.chat_bubble_outline,
                                                      size: 14,
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
                                                            overflow:
                                                                TextOverflow.ellipsis,
                                                            style: theme.textTheme
                                                                .bodySmall!
                                                                .copyWith(
                                                              fontWeight: isActive
                                                                  ? FontWeight.w600
                                                                  : FontWeight.w400,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Row(
                                                            children: [
                                                              if (chat.messageCount > 0) ...[
                                                                Icon(
                                                                  Icons.forum_outlined,
                                                                  size: 9,
                                                                  color: theme.hintColor,
                                                                ),
                                                                const SizedBox(width: 2),
                                                                Text(
                                                                  '${chat.messageCount}',
                                                                  style: theme.textTheme
                                                                      .bodySmall!
                                                                      .copyWith(
                                                                    fontSize: 9,
                                                                    color: theme.hintColor,
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 6),
                                                              ],
                                                              Text(
                                                                chat.humanUpdatedAt,
                                                                style: theme.textTheme
                                                                    .bodySmall!
                                                                    .copyWith(
                                                                  fontSize: 9,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                        size: 14,
                                                      ),
                                                      color: theme.colorScheme.error,
                                                      tooltip: 'Delete chat',
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(
                                                        minWidth: 24,
                                                        minHeight: 24,
                                                      ),
                                                      onPressed: () async {
                                                        final confirm =
                                                            await showDialog<bool>(
                                                          context: context,
                                                          builder: (ctx) => AlertDialog(
                                                            title: const Text(
                                                                'Delete chat?'),
                                                            content: const Text(
                                                              'This will remove this chat session and its messages.',
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
                                                                    Navigator.of(ctx)
                                                                        .pop(true),
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
                                      }).toList(),
                                  ],
                                ],
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
                    constraints: BoxConstraints(
                      maxWidth: isWide ? 1600 : double.infinity,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isMobile ? 8.0 : 12.0),
                      child: (isWide || isMedium)
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                sidebar,
                                SizedBox(width: isMobile ? 8 : 12),
                                Expanded(child: chatArea),
                              ],
                            )
                          : Column(
                              children: [
                                SizedBox(
                                  height: 240,
                                  child: sidebar,
                                ),
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
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  app.hasProcessingDocuments
                      ? Icons.hourglass_empty
                      : Icons.cloud_upload_outlined,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                app.hasProcessingDocuments
                    ? 'Processing documents...'
                    : 'Upload documents to start',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                app.hasProcessingDocuments
                    ? 'Your documents are being indexed. This may take a few moments. You\'ll be able to ask questions once processing is complete.'
                    : 'Upload PDFs, DOCX, or text files to get started. Once processed, you can ask questions about your documents.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                ),
                textAlign: TextAlign.center,
              ),
              if (app.hasProcessingDocuments) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  borderRadius: BorderRadius.circular(8),
                ),
              ] else ...[
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _pickAndUpload(app),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Document'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      );
    }

    // Show message based on state
    if (app.selectedDocumentId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 64,
              color: theme.hintColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Select a document to view chats',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click on a document in the sidebar to see its chat sessions',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (active == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: theme.hintColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No active chat',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new chat from the sidebar to start asking questions',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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
                  if (msg.contexts.isNotEmpty && !isUser) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) {
                            return Container(
                              height: MediaQuery.of(ctx).size.height * 0.7,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.source_outlined,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Source Context (${msg.contexts.length})',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: ListView.separated(
                                      padding: const EdgeInsets.all(16.0),
                                      itemCount: msg.contexts.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 16),
                                      itemBuilder: (ctx, i) {
                                        final ctxChunk = msg.contexts[i];
                                        return Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme
                                                .surfaceVariant
                                                .withOpacity(0.5),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: theme.colorScheme.outline
                                                  .withOpacity(0.2),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: theme
                                                          .colorScheme.primary
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Text(
                                                      'Relevance: ${(ctxChunk.score * 100).toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                        color: theme.colorScheme
                                                            .primary,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    'Chunk #${i + 1}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: theme.hintColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                ctxChunk.text,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  height: 1.5,
                                                ),
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
                          },
                        );
                      },
                      icon: const Icon(Icons.source_outlined, size: 14),
                      label: Text(
                        '${msg.contexts.length} sources',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                    ),
                  ],
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
        return Colors.orange;
      case 'uploading':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      case 'uploaded':
        return Colors.amber;
      default:
        return Theme.of(context).disabledColor;
    }
  }
  
  IconData _icon() {
    switch (status) {
      case 'done':
        return Icons.check_circle;
      case 'processing':
        return Icons.hourglass_empty;
      case 'uploading':
        return Icons.cloud_upload;
      case 'failed':
        return Icons.error;
      case 'uploaded':
        return Icons.pending;
      default:
        return Icons.circle;
    }
  }
  
  String _displayText() {
    switch (status) {
      case 'done':
        return 'Ready';
      case 'processing':
        return 'Processing';
      case 'uploading':
        return 'Uploading';
      case 'failed':
        return 'Failed';
      case 'uploaded':
        return 'Queued';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color(context).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _color(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon(),
            size: 12,
            color: _color(context),
          ),
          const SizedBox(width: 4),
          Text(
            _displayText(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _color(context),
            ),
          ),
        ],
      ),
    );
  }
}
