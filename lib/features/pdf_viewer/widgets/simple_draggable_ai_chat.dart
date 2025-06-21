import 'package:flutter/material.dart';
import 'package:snapfig/shared/services/ai_service/ai_service.dart';
import 'package:snapfig/shared/services/ai_service/models/ai_provider.dart';
import 'package:snapfig/shared/services/pdf_core/models/models.dart';
import 'package:snapfig/features/pdf_viewer/models/pdf_data_viewmodel.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class Message {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isLoading;

  Message({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
    this.isLoading = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class SimpleDraggableAIChat extends StatefulWidget {
  final BaseLayout figure;
  final PDFDataViewModel viewModel;
  final VoidCallback onClose;
  final Offset? initialPosition;

  const SimpleDraggableAIChat({
    super.key,
    required this.figure,
    required this.viewModel,
    required this.onClose,
    this.initialPosition,
  });

  @override
  State<SimpleDraggableAIChat> createState() => _SimpleDraggableAIChatState();
}

class _SimpleDraggableAIChatState extends State<SimpleDraggableAIChat>
    with SingleTickerProviderStateMixin {
  final List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AIProvider? _selectedProvider;
  bool _isLoading = false;

  // Position and animation
  Offset _position = const Offset(100, 100);
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isDragging = false;
  bool _isResizing = false;

  // Size variables
  double _chatWidth = 400.0;
  double _chatHeight = 500.0;

  // Size constraints
  static const double _minWidth = 300.0;
  static const double _maxWidth = 600.0;
  static const double _minHeight = 400.0;
  static const double _maxHeight = 800.0;

  @override
  void initState() {
    super.initState();
    _initializePosition();
    _initializeAnimations();
    _loadAvailableProviders();
    _addWelcomeMessage();
    _sendInitialFigureMessage();
  }

  void _initializePosition() {
    if (widget.initialPosition != null) {
      _position = widget.initialPosition!;
    } else {
      // Default to center of screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final screenSize = MediaQuery.of(context).size;
        setState(() {
          _position = Offset(
            (screenSize.width - _chatWidth) / 2, // Center horizontally
            (screenSize.height - _chatHeight) / 2, // Center vertically
          );
        });
      });
    }
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
  }

  void _loadAvailableProviders() {
    final configurations = AIService.instance.configurations;
    if (configurations.isNotEmpty) {
      _selectedProvider = configurations.first.provider;
    }
  }

  void _addWelcomeMessage() {
    _messages.add(
      Message(
        content:
            'Hello! I can help you understand this figure. What would you like to know about it?',
        isUser: false,
      ),
    );
  }

  Future<void> _sendInitialFigureMessage() async {
    if (_selectedProvider == null) return;

    // Add user message indicating we're sending the figure
    setState(() {
      _messages.add(
        Message(content: 'Here is the figure I want to analyze', isUser: true),
      );
      _messages.add(Message(content: '', isUser: false, isLoading: true));
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // Get the figure image
      final figureImage = await widget.viewModel.getFigureImage(widget.figure);
      if (figureImage == null) {
        throw Exception('Could not load figure image');
      }

      final pageNumber = widget.viewModel.getPageNumberForFigure(widget.figure);
      final context =
          'Figure ID: ${widget.figure.figureId ?? widget.figure.id.toString()}, Page: ${pageNumber ?? 'Unknown'}';

      final response = await AIService.instance.askAI(
        provider: _selectedProvider!,
        question:
            'Please analyze this figure and describe what you can see. What kind of data or information does it represent?',
        context: context,
        image: figureImage,
      );

      setState(() {
        _messages.removeLast(); // Remove loading message
        _messages.add(Message(content: response, isUser: false));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast(); // Remove loading message
        _messages.add(
          Message(
            content: 'Sorry, I couldn\'t analyze the figure: ${e.toString()}',
            isUser: false,
          ),
        );
        _isLoading = false;
      });
    }

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configurations = AIService.instance.configurations;
    final screenSize = MediaQuery.of(context).size;

    if (configurations.isEmpty) {
      return _buildNoConfigurationView(context, screenSize);
    }

    // Constrain position to screen bounds
    final constrainedPosition = _constrainPosition(_position, screenSize);

    return Positioned(
      left: constrainedPosition.dx,
      top: constrainedPosition.dy,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          elevation: _isDragging ? 16 : 8,
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            onPanStart: (details) {
              setState(() {
                _isDragging = true;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
              });
            },
            onPanEnd: (details) {
              setState(() {
                _isDragging = false;
                // Snap to screen edges if close enough
                _position = _snapToEdges(_position, screenSize);
              });
            },
            child: Stack(
              children: [
                Container(
                  width: _chatWidth,
                  height: _chatHeight,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          _isDragging || _isResizing
                              ? theme.colorScheme.primary.withValues(alpha: 0.5)
                              : theme.colorScheme.outline.withValues(
                                alpha: 0.2,
                              ),
                      width: _isDragging || _isResizing ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _isDragging || _isResizing ? 0.3 : 0.15,
                        ),
                        blurRadius: _isDragging || _isResizing ? 20 : 10,
                        offset: Offset(0, _isDragging || _isResizing ? 8 : 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildDraggableHeader(context),
                      Expanded(child: _buildMessageList(context)),
                      _buildInputSection(context),
                    ],
                  ),
                ),
                // Resize handle
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _isResizing = true;
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        // Update size based on drag delta
                        _chatWidth = (_chatWidth + details.delta.dx).clamp(
                          _minWidth,
                          _maxWidth,
                        );
                        _chatHeight = (_chatHeight + details.delta.dy).clamp(
                          _minHeight,
                          _maxHeight,
                        );

                        // Ensure window stays within screen bounds after resizing
                        final screenSize = MediaQuery.of(context).size;
                        if (_position.dx + _chatWidth > screenSize.width) {
                          _position = Offset(
                            screenSize.width - _chatWidth,
                            _position.dy,
                          );
                        }
                        if (_position.dy + _chatHeight > screenSize.height) {
                          _position = Offset(
                            _position.dx,
                            screenSize.height - _chatHeight,
                          );
                        }
                      });
                    },
                    onPanEnd: (details) {
                      setState(() {
                        _isResizing = false;
                      });
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color:
                            _isResizing
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceVariant,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Icon(
                        Icons.drag_handle,
                        size: 12,
                        color:
                            _isResizing
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableHeader(BuildContext context) {
    final theme = Theme.of(context);
    final configurations = AIService.instance.configurations;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:
            _isDragging
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Text(
                'Assistant',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color:
                      _isDragging
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (configurations.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<AIProvider>(
                    value: _selectedProvider,
                    underline: const SizedBox(),
                    isDense: true,
                    items:
                        configurations.map((config) {
                          return DropdownMenuItem(
                            value: config.provider,
                            child: Text(
                              config.provider.displayName,
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        }).toList(),
                    onChanged: (provider) {
                      setState(() {
                        _selectedProvider = provider;
                      });
                    },
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _closeWithAnimation,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color:
                      _isDragging
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                ),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(24, 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(context, message);
      },
    );
  }

  Widget _buildMessageBubble(BuildContext context, Message message) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: theme.colorScheme.primary,
              child: Icon(
                Icons.smart_toy,
                size: 14,
                color: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    message.isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child:
                  message.isLoading
                      ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Thinking...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                      : GptMarkdown(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              message.isUser
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                        ),
                      ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 12,
              backgroundColor: theme.colorScheme.secondary,
              child: Icon(
                Icons.person,
                size: 14,
                color: theme.colorScheme.onSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputSection(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'Ask about this figure...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _isLoading ? null : (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed:
                _isLoading || _textController.text.trim().isEmpty
                    ? null
                    : _sendMessage,
            icon: Icon(
              Icons.send,
              color:
                  _isLoading || _textController.text.trim().isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
            ),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              shape: const CircleBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoConfigurationView(BuildContext context, Size screenSize) {
    final theme = Theme.of(context);
    final constrainedPosition = _constrainPosition(_position, screenSize);

    return Positioned(
      left: constrainedPosition.dx,
      top: constrainedPosition.dy,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          elevation: _isDragging ? 16 : 8,
          borderRadius: BorderRadius.circular(16),
          child: GestureDetector(
            onPanStart: (details) {
              setState(() {
                _isDragging = true;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
              });
            },
            onPanEnd: (details) {
              setState(() {
                _isDragging = false;
                _position = _snapToEdges(_position, screenSize);
              });
            },
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      _isDragging
                          ? theme.colorScheme.primary.withValues(alpha: 0.5)
                          : theme.colorScheme.outline.withValues(alpha: 0.2),
                  width: _isDragging ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Text('Assistant', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        onPressed: _closeWithAnimation,
                        icon: const Icon(Icons.close, size: 18),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(4),
                          minimumSize: const Size(24, 24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Icon(
                    Icons.settings,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AI Configuration Required',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please configure your AI API keys to use this feature.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _closeWithAnimation,
                          child: const Text('Close'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/ai-settings');
                          },
                          child: const Text('Settings'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _constrainPosition(Offset position, Size screenSize) {
    // Use smaller width for no configuration view
    final width =
        AIService.instance.configurations.isEmpty ? 300.0 : _chatWidth;
    final height =
        AIService.instance.configurations.isEmpty ? 300.0 : _chatHeight;

    double constrainedX = position.dx.clamp(0.0, screenSize.width - width);
    double constrainedY = position.dy.clamp(0.0, screenSize.height - height);

    return Offset(constrainedX, constrainedY);
  }

  Offset _snapToEdges(Offset position, Size screenSize) {
    const snapDistance = 20.0;

    // Use smaller width/height for no configuration view
    final width =
        AIService.instance.configurations.isEmpty ? 300.0 : _chatWidth;
    final height =
        AIService.instance.configurations.isEmpty ? 300.0 : _chatHeight;

    double x = position.dx;
    double y = position.dy;

    // Snap to left edge
    if (x < snapDistance) {
      x = 0;
    }
    // Snap to right edge
    else if (x > screenSize.width - width - snapDistance) {
      x = screenSize.width - width;
    }

    // Snap to top edge
    if (y < snapDistance) {
      y = 0;
    }
    // Snap to bottom edge
    else if (y > screenSize.height - height - snapDistance) {
      y = screenSize.height - height;
    }

    return Offset(x, y);
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _selectedProvider == null) return;

    setState(() {
      _messages.add(Message(content: text, isUser: true));
      _messages.add(Message(content: '', isUser: false, isLoading: true));
      _isLoading = true;
    });

    _textController.clear();
    _scrollToBottom();

    try {
      // Get the figure image for context
      final figureImage = await widget.viewModel.getFigureImage(widget.figure);

      final pageNumber = widget.viewModel.getPageNumberForFigure(widget.figure);
      final context =
          'Figure ID: ${widget.figure.figureId ?? widget.figure.id.toString()}, Page: ${pageNumber ?? 'Unknown'}';
      final response = await AIService.instance.askAI(
        provider: _selectedProvider!,
        question: text,
        context: context,
        image: figureImage,
      );

      setState(() {
        _messages.removeLast(); // Remove loading message
        _messages.add(Message(content: response, isUser: false));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast(); // Remove loading message
        _messages.add(
          Message(
            content: 'Sorry, I encountered an error: ${e.toString()}',
            isUser: false,
          ),
        );
        _isLoading = false;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _closeWithAnimation() {
    _animationController.reverse().then((_) {
      widget.onClose();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }
}
