import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart'; // Add import for ScrollDirection
import 'package:flutter/gestures.dart'; // Add this import for PointerScrollEvent
import 'package:flutter/foundation.dart'; // Add import for kIsWeb
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:math' as math; // Add import for math.min
import '../services/chat_provider.dart';
import '../services/auth_provider.dart';
import '../theme/theme_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart'; // Add import for AppSpacing
import '../widgets/chat_message.dart';
import '../widgets/message_input.dart';
import '../widgets/model_selector.dart';
import '../widgets/side_panel.dart';
import '../screens/model_management_screen.dart';
import '../screens/settings_screen.dart'; // Import the new settings screen
import '../widgets/token_window_visualization.dart';
import '../config/env_config.dart';
import 'dart:async';
import '../widgets/model_selector_button.dart'; // Import the new widget

// Dedicated class to manage scroll behavior
class ChatScrollManager {
  final ScrollController controller;

  ChatScrollManager() : controller = ScrollController();

  void initialize() {
    // No need for scroll listeners anymore
  }

  void dispose() {
    controller.dispose();
  }

  void scrollToBottom({bool animate = true}) {
    if (!controller.hasClients) return;

    try {
      final position = controller.position;
      final maxScroll = position.maxScrollExtent;

      if (animate) {
        controller.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        controller.jumpTo(maxScroll);
      }
    } catch (e) {
      debugPrint('Error scrolling: $e');
    }
  }

  void reset() {
    // No need to reset any state
  }
}

// Custom scrollbar thumb widget with fixed size - OLD WORKING VERSION
class CustomScrollbarThumb extends StatefulWidget {
  final ScrollController scrollController;
  final double thickness;
  final Color color;
  final double
      height; // Note: This parameter seems unused in the old build method
  final double minThumbLength;

  const CustomScrollbarThumb({
    Key? key,
    required this.scrollController,
    this.thickness = 6.0,
    required this.color,
    this.height = 60.0, // Default value from old code
    this.minThumbLength = 60.0, // Default value from old code
  }) : super(key: key);

  @override
  State<CustomScrollbarThumb> createState() => _CustomScrollbarThumbState();
}

// State for OLD WORKING VERSION
class _CustomScrollbarThumbState extends State<CustomScrollbarThumb>
    with SingleTickerProviderStateMixin {
  // Added TickerProvider
  bool _isDragging = false;
  bool _isHovering = false;
  bool _isScrolling = false;
  Timer? _scrollVisibilityTimer;
  double _currentThumbOffset = 0.0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScrollChange);
    // Initial check in case content is already scrollable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.scrollController.hasClients) {
        _handleScrollChange();
      }
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScrollChange);
    _scrollVisibilityTimer?.cancel();
    super.dispose();
  }

  void _handleScrollChange() {
    if (!mounted || !widget.scrollController.hasClients) return;

    final ScrollPosition position = widget.scrollController.position;
    final double viewportDimension = position.viewportDimension;
    final double maxScroll = position.maxScrollExtent;
    final double minScroll = position.minScrollExtent;
    final double scrollExtent = maxScroll - minScroll;

    // Hide if not scrollable
    if (scrollExtent <= 0 || viewportDimension <= 0) {
      if (_isScrolling) {
        setState(() => _isScrolling = false);
      }
      return;
    }

    // Fixed ratio calculation
    final double ratio = (position.pixels - minScroll) / scrollExtent;
    final double availableSpace = viewportDimension - widget.minThumbLength;
    final double thumbPosition = (1.0 - ratio.clamp(0.0, 1.0)) * availableSpace;

    // Show and update position
    if (!_isScrolling) {
      setState(() => _isScrolling = true);
    }
    setState(() {
      _currentThumbOffset = thumbPosition.clamp(0.0, availableSpace);
    });

    // Start timer to hide thumb when scrolling stops
    _scrollVisibilityTimer?.cancel();
    _scrollVisibilityTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && !_isDragging && !_isHovering) {
        setState(() {
          _isScrolling = false;
        });
      }
    });
  }

  void _startDrag(DragStartDetails details) {
    setState(() {
      _isDragging = true;
    });
  }

  void _endDrag(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });

    // Start timer to hide thumb if not hovering
    if (!_isHovering) {
      _scrollVisibilityTimer?.cancel();
      _scrollVisibilityTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted && !_isDragging && !_isHovering) {
          setState(() {
            _isScrolling = false;
          });
        }
      });
    }
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!widget.scrollController.hasClients) return;

    final ScrollPosition position = widget.scrollController.position;
    final double viewportDimension = position.viewportDimension;
    final double maxScroll = position.maxScrollExtent;
    final double minScroll = position.minScrollExtent;
    final double scrollExtent = maxScroll - minScroll;

    if (scrollExtent <= 0 || viewportDimension <= 0) return;

    // Fixed ratio for drag
    final double availableSpace = viewportDimension - widget.minThumbLength;
    final double dragDelta = details.delta.dy;
    final double dragRatio = dragDelta / availableSpace;
    final double scrollDelta = -dragRatio * scrollExtent;

    widget.scrollController
        .jumpTo((position.pixels + scrollDelta).clamp(minScroll, maxScroll));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scrollController.hasClients) return const SizedBox();

    try {
      final ScrollPosition position = widget.scrollController.position;
      final double viewportDimension = position.viewportDimension;
      final double scrollExtent =
          position.maxScrollExtent - position.minScrollExtent;

      if (scrollExtent <= 0 || viewportDimension <= 0) return const SizedBox();

      final double thumbLength = widget.minThumbLength;
      final double trackHeight = viewportDimension;
      final bool shouldShowScrollbar =
          _isDragging || _isHovering || _isScrolling;

      return MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() {
          _isHovering = false;
          // Start timer to hide thumb if not dragging
          if (!_isDragging) {
            _scrollVisibilityTimer?.cancel();
            _scrollVisibilityTimer =
                Timer(const Duration(milliseconds: 400), () {
              if (mounted && !_isDragging && !_isHovering) {
                setState(() => _isScrolling = false);
              }
            });
          }
        }),
        child: GestureDetector(
          onVerticalDragStart: _startDrag,
          onVerticalDragUpdate: _updateDrag,
          onVerticalDragEnd: _endDrag,
          child: AnimatedOpacity(
            opacity: shouldShowScrollbar ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              // Increased width for easier grabbing on desktop/web
              width: widget.thickness + 6,
              height: trackHeight,
              alignment: Alignment.topRight,
              color: Colors
                  .transparent, // Make outer container transparent for MouseRegion
              child: Transform.translate(
                offset: Offset(0, _currentThumbOffset),
                child: Container(
                  width: widget.thickness,
                  height: thumbLength,
                  decoration: BoxDecoration(
                    // Use provided color with opacity based on drag state
                    color: widget.color.withOpacity(_isDragging ? 1.0 : 0.6),
                    borderRadius: BorderRadius.circular(widget.thickness / 2),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      // Added basic error logging
      print("Error building CustomScrollbarThumb: $e");
      return const SizedBox();
    }
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final ChatScrollManager _scrollManager = ChatScrollManager();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isTokenWindowVisible = true;
  static const String _tokenWindowKey = 'token_window_visible';
  late AnimationController _shimmerController;
  late TextEditingController _messageController;
  String _modelSearchQuery = '';
  late ChatProvider _chatProvider; // Store a reference to the ChatProvider

  @override
  void initState() {
    super.initState();

    // Initialize ChatProvider immediately
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Initialize other controllers
    _messageController = TextEditingController();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _scrollManager.initialize();
    _loadSavedStates(); // Load token window state only

    // Use post frame callback for things needing context/build completion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // Check if widget is still mounted

      // Add listener and initialize chat logic after first frame
      _chatProvider.addListener(_handleChatUpdate);
      _initializeChat();
    });
  }

  @override
  void dispose() {
    // Use the stored reference instead of Provider.of
    _chatProvider.removeListener(_handleChatUpdate);
    _shimmerController.dispose();
    _scrollManager.dispose();
    _inputFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _initializeChat() async {
    // Initialize the chat provider
    await _chatProvider.initialize();

    // Focus the input field if a conversation exists
    if (_chatProvider.conversationId != null) {
      _focusInputField();
    }
  }

  Future<void> _loadSavedStates() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isTokenWindowVisible = prefs.getBool(_tokenWindowKey) ?? true;
      });
    }
  }

  Future<void> _saveTokenWindowState(bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tokenWindowKey, isVisible);
  }

  void _toggleTokenWindow() {
    setState(() {
      _isTokenWindowVisible = !_isTokenWindowVisible;
      _saveTokenWindowState(_isTokenWindowVisible);
    });
  }

  void _handleChatUpdate() {
    // Store previous conversation ID to detect change
    final previousConversationId = _chatProvider.conversationId;

    // Use WidgetsBinding.instance.addPostFrameCallback to ensure
    // state access happens after the build phase triggered by notifyListeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // Check mount status

      // Check if the conversation ID changed *to* a temporary one
      final currentConversationId = _chatProvider.conversationId;
      if (currentConversationId != previousConversationId &&
          _chatProvider.isTemporaryConversationId(currentConversationId)) {
        debugPrint('Detected new temporary conversation, focusing input.');
        _focusInputField();
      }

      // Existing scroll logic
      if (_chatProvider.messages.isNotEmpty &&
          !_chatProvider.messages.last.isUser &&
          _chatProvider.isLoading) {
        // Slightly improved logic to scroll when assistant is responding
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            _scrollManager.scrollToBottom(animate: true);
          }
        });
      }

      // Standard setState to update UI based on general provider changes
      // This needs to be outside the postFrameCallback if other parts of build depend on it directly
      // However, if it causes issues, move it inside.
      // Let's try keeping it outside first.
      setState(() {});
    });
  }

  void _focusInputField() {
    _inputFocusNode.requestFocus();
  }

  void _showModelSelectorDialog() {
    _showModelSelector(context, _chatProvider); // Reuse existing dialog logic
  }

  void _navigateToSettings(BuildContext scaffoldContext) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
    if (Scaffold.of(scaffoldContext).isDrawerOpen) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chatProvider =
        context.watch<ChatProvider>(); // Watch for state changes
    final authProvider = context.watch<AuthProvider>();
    final isAuthenticated = authProvider.isAuthenticated;

    // Refactored using Scaffold, AppBar, Drawer
    return Scaffold(
      backgroundColor: colorScheme.background,
      // Use a Builder for the AppBar to get the right Scaffold context for the drawer button
      appBar: AppBar(
        // Hamburger icon implicitly added by Scaffold when drawer exists
        backgroundColor: colorScheme.surface,
        elevation: 2.0, // Standard AppBar elevation
        shadowColor: theme.colorScheme.shadow.withOpacity(0.2),
        toolbarHeight: 48, // Matches our previous bar height
        titleSpacing: 0, // Reduce default title spacing
        title: _buildAppBarTitle(context, chatProvider, colorScheme),
        actions: _buildAppBarActions(context, chatProvider, colorScheme),
      ),
      drawer: _buildDrawer(context),
      body: _buildBody(context, chatProvider, isAuthenticated),
    );
  }

  // Helper to build AppBar title content (Model Selector)
  Widget _buildAppBarTitle(BuildContext context, ChatProvider chatProvider,
      ColorScheme colorScheme) {
    // Use Padding to control spacing if needed
    return Padding(
      padding: const EdgeInsets.only(left: 0), // Adjust as needed
      child: ModelSelectorButton(
        selectedModel: chatProvider.selectedModel,
        availableModels: chatProvider.availableModels,
      ),
    );
  }

  // Helper to build AppBar actions (Token, Settings)
  List<Widget> _buildAppBarActions(BuildContext context,
      ChatProvider chatProvider, ColorScheme colorScheme) {
    return [
      // Token Window Toggle (Optional)
      if (chatProvider.totalTokens > 0)
        Builder(builder: (buttonContext) {
          return _buildIconButton(
            icon: _isTokenWindowVisible
                ? Icons.insights_rounded
                : Icons.insights_outlined,
            tooltip:
                _isTokenWindowVisible ? 'Hide Token Usage' : 'Show Token Usage',
            onPressed: _toggleTokenWindow,
            colorScheme: colorScheme,
            useAccentColor: true,
          );
        }),
      // Settings Button - Wrap with Builder
      Builder(builder: (buttonContext) {
        return _buildIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onPressed: () => _navigateToSettings(buttonContext),
          colorScheme: colorScheme,
          useAccentColor: true,
        );
      }),
      const SizedBox(
          width: AppSpacing.inlineSpacingSmall), // Add padding at the end
    ];
  }

  // Helper to build the Drawer
  Widget _buildDrawer(BuildContext context) {
    return SizedBox(
      width: math.min(
          MediaQuery.of(context).size.width * 0.8, 300.0), // Set drawer width
      child: SidePanel(
        // Removed properties related to old expansion logic
        onNewChat: () {
          // Delay focus request slightly to allow drawer animation to potentially complete
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              // Check if widget is still mounted after delay
              _focusInputField();
            }
          });
          // Close drawer after starting new chat (This happens immediately)
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // Helper to build the Scaffold body
  Widget _buildBody(
      BuildContext context, ChatProvider chatProvider, bool isAuthenticated) {
    final theme = Theme.of(context);
    // Restore the original Column structure (Remove SingleChildScrollView)
    return Column(
      children: [
        // --- Restore Token Usage Visualization ---
        if (_isTokenWindowVisible &&
            chatProvider.totalTokens > 0 &&
            chatProvider.selectedModel != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePaddingHorizontal,
              vertical: AppSpacing.inlineSpacingSmall,
            ),
            child: TokenWindowVisualization(
              totalTokens: chatProvider.totalTokens,
              inputTokens: chatProvider.totalInputTokens,
              outputTokens: chatProvider.totalOutputTokens,
              model:
                  chatProvider.selectedModel!, // Safe due to null check above
              totalCost: chatProvider.totalCost,
            ),
          ),

        // Main chat messages area
        Expanded(
          child: ClipRect(
            // Keep ClipRect and Stack structure
            child: Stack(
              children: [
                // Conditionally show Empty State or Message List INSIDE Stack
                chatProvider.messages.isEmpty
                    ? _buildEmptyState(context, chatProvider)
                    : ChatContainer(
                        // Render message list container
                        key: const ValueKey(
                            'message_list_content'), // Add key here
                        child: _buildMessagesList(chatProvider),
                      ),

                // Scrollbar is always present in the Stack, but CustomScrollbarThumb handles its own visibility
                Positioned(
                  right: 2,
                  top: 0,
                  bottom: 0,
                  child: CustomScrollbarThumb(
                    scrollController: _scrollManager.controller,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                // Error Message Overlay (always potentially present)
                if (chatProvider.error != null)
                  Positioned(
                    bottom: 80, // Position above input
                    left: AppSpacing.pagePaddingHorizontal,
                    right: AppSpacing.pagePaddingHorizontal,
                    child: _buildErrorMessage(chatProvider),
                  ),
              ],
            ),
          ),
        ),

        // --- Restore Message Input Area ---
        ChatContainer(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom +
                  AppSpacing.inlineSpacing, // SafeArea bottom + padding
              left: AppSpacing.inlineSpacing, // Add consistent padding
              right: AppSpacing.inlineSpacing,
            ),
            child: _buildMessageInput(chatProvider, isAuthenticated),
          ),
        ),
      ],
    );
  }

  // Helper method to build consistent icon buttons (used in AppBar actions)
  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required ColorScheme colorScheme,
    bool useAccentColor = false,
  }) {
    // Removed the outer Center wrapper
    return Container(
      decoration: BoxDecoration(
        // Always transparent background
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8), // Smaller radius
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8), // Match container
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6.0), // Further reduced padding
            child: Tooltip(
              message: tooltip,
              child: Center(
                // Explicitly center the icon
                child: Icon(
                  icon,
                  size: 22, // Reduced icon size again
                  // Icon color still uses accent when requested
                  color: useAccentColor
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList(ChatProvider chatProvider) {
    // Removed isEmpty check - handled in _buildBody now
    final messages = chatProvider.messages;
    final theme = Theme.of(context);

    // Directly return the GestureDetector containing the ListView
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // Dismiss keyboard on tap
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _scrollManager.controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePaddingHorizontal),
          shrinkWrap: false,
          reverse: true,
          addRepaintBoundaries: true,
          cacheExtent: 10000,
          clipBehavior: Clip.none,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[messages.length - 1 - index];

            // Use RepaintBoundary for performance optimization
            return RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal:
                      AppSpacing.inlineSpacingSmall, // Adjust spacing as needed
                  vertical: AppSpacing.verticalPaddingSmall / 2,
                ),
                child: ChatMessageWidget(
                  key: ValueKey('msg_${message.id}'),
                  message: message,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageInput(ChatProvider chatProvider, bool isAuthenticated) {
    final theme = Theme.of(context);
    final focusNode = _inputFocusNode;
    final hasModels = chatProvider.availableModels.isNotEmpty;
    final selectedModel = chatProvider.selectedModel;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: !hasModels || selectedModel == null
          ? _buildNoModelsInput()
          : MessageInput(
              onSubmit: (content) async {
                final chatProvider = context.read<ChatProvider>();

                // Check if we have a valid conversation ID
                if (chatProvider.conversationId == null ||
                    chatProvider.conversationId!.isEmpty) {
                  // Try to prepare a conversation first
                  final success = await chatProvider.prepareConversation();
                  if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Failed to create conversation. Please try again.'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                    return;
                  }
                }

                // Now send the message with a valid conversation ID
                chatProvider.addUserMessage(content);

                // Reset scroll manager and scroll to bottom when user sends message
                _scrollManager.reset();
                _scrollManager.scrollToBottom(animate: true);
              },
              isLoading: chatProvider.isLoading,
              focusNode: focusNode,
            ),
    );
  }

  Widget _buildNoModelsInput() {
    final chatProvider = Provider.of<ChatProvider>(context);
    final hasModels = chatProvider.availableModels.isNotEmpty;
    final theme = Theme.of(context);

    final String errorMessage = hasModels
        ? 'Cannot send messages: No model selected'
        : 'Cannot send messages: Connection to AI service unavailable';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              if (hasModels) {
                _showModelSelector(context, chatProvider);
              } else {
                context
                    .read<ChatProvider>()
                    .initialize(syncModelsWithBackend: true);
              }
            },
            icon: Icon(hasModels ? Icons.model_training : Icons.refresh),
            label: Text(hasModels ? 'Select' : 'Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ChatProvider chatProvider) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isLoading = chatProvider.isLoading;
    final errorMessage = chatProvider.error;
    final hasModels = chatProvider.availableModels.isNotEmpty;
    final selectedModel = chatProvider.selectedModel;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const CircularProgressIndicator()
              else
                Icon(
                  // Updated Icon for welcome state
                  hasModels
                      ? Icons.waving_hand_outlined
                      : Icons.error_outline, // Waving hand icon
                  size: 64,
                  color: hasModels
                      ? Theme.of(context)
                          .colorScheme
                          .primary // Use primary color directly
                      : Theme.of(context).colorScheme.error.withOpacity(0.7),
                ),
              const SizedBox(height: 24),

              // Main title based on state
              if (isLoading)
                Text(
                  'Setting up your conversation...',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                )
              else if (!hasModels)
                Text(
                  'Unable to connect to the AI service',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                  textAlign: TextAlign.center,
                )
              else if (selectedModel == null)
                Text(
                  'No model selected',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  textAlign: TextAlign.center,
                )
              else
                Text(
                  // Use passed chatProvider parameter
                  'Hola, ${chatProvider.currentDisplayName ?? 'there'}!',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600, // Slightly bolder
                        color: Theme.of(context)
                            .colorScheme
                            .primary, // Use primary color
                      ),
                  textAlign: TextAlign.center,
                ),

              const SizedBox(height: 8),

              // Subtitle based on state
              if (!isLoading) ...[
                if (hasModels && selectedModel != null)
                  Text(
                    'How can I help you today?', // Updated welcome subtitle
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                    textAlign: TextAlign.center,
                  )
                else if (hasModels && selectedModel == null)
                  Text(
                    'Please select a model to continue',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.7),
                        ),
                    textAlign: TextAlign.center,
                  )
                else if (!hasModels)
                  Text(
                    'Check your internet connection and try again',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.7),
                        ),
                  )
              ],

              if (errorMessage != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Error: $errorMessage',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(ChatProvider chatProvider) {
    final theme = Theme.of(context);
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium),
      color: theme.colorScheme.errorContainer,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                color: theme.colorScheme.onErrorContainer, size: 20),
            const SizedBox(width: AppSpacing.inlineSpacing),
            Expanded(
              child: Text(
                chatProvider.error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                chatProvider.clearError();
              },
              tooltip: 'Dismiss error',
              color: theme.colorScheme.onErrorContainer,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  void _showModelSelector(BuildContext context, ChatProvider chatProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 60),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 450),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title bar
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.5),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select Model',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close),
                        splashRadius: 20,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Search field
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search models...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outline,
                          width: 0.5,
                        ),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _modelSearchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),

                // Model list
                Expanded(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      // Filter models by search query
                      final filteredModels = _modelSearchQuery.isEmpty
                          ? chatProvider.availableModels
                          : chatProvider.availableModels.where((model) {
                              return model.displayName
                                      .toLowerCase()
                                      .contains(_modelSearchQuery) ||
                                  model.modelId
                                      .toLowerCase()
                                      .contains(_modelSearchQuery) ||
                                  model.provider
                                      .toLowerCase()
                                      .contains(_modelSearchQuery);
                            }).toList();

                      if (filteredModels.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No models found',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.5),
                                    ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredModels.length,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemBuilder: (context, index) {
                          final model = filteredModels[index];
                          final isSelected =
                              chatProvider.selectedModel?.modelId ==
                                  model.modelId;

                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.3),
                            title: Text(
                              model.displayName,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              '${model.provider} • ${model.maxInputTokens} tokens',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            onTap: () {
                              chatProvider.setSelectedModel(model);
                              _modelSearchQuery = '';
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

                // Optional footer or action buttons
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.3),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${chatProvider.availableModels.length} models available',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Sign out confirmation dialog
  Future<void> _showSignOutConfirmation(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark
              ? Color.lerp(theme.colorScheme.surface, Colors.black, 0.3)
              : Color.lerp(theme.colorScheme.surface, Colors.white, 0.3),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Sign Out',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out?',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.primary.withOpacity(0.8),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await authProvider.logout();
              },
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Sign Out',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ChatContainer extends StatelessWidget {
  final Widget child;

  const ChatContainer({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(850.0, constraints.maxWidth);

        return Center(
          child: SizedBox(
            width: maxWidth,
            child: child,
          ),
        );
      },
    );
  }
}
