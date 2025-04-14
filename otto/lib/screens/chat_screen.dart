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

// Custom scrollbar thumb widget with fixed size
class CustomScrollbarThumb extends StatefulWidget {
  final ScrollController scrollController;
  final double minThumbLength;
  final double thickness;
  // Removed color parameter

  const CustomScrollbarThumb({
    Key? key,
    required this.scrollController,
    this.minThumbLength = 48.0,
    this.thickness = 6.0, // Default thickness
    // Removed color parameter
  }) : super(key: key);

  @override
  State<CustomScrollbarThumb> createState() => _CustomScrollbarThumbState();
}

class _CustomScrollbarThumbState extends State<CustomScrollbarThumb>
    with TickerProviderStateMixin {
  double _currentThumbOffset = 0.0;
  bool _isDragging = false;
  bool _isHovering = false;
  bool _isScrolling = false;
  Timer? _scrollVisibilityTimer;
  Timer? _scrollEndTimer;
  late AnimationController _thumbAnimationController; // For smooth fade
  late Animation<double> _thumbOpacityAnimation;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScrollChange);
    
    _thumbAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200), // Fade duration
    );
    _thumbOpacityAnimation = CurvedAnimation(
      parent: _thumbAnimationController,
      curve: Curves.easeInOut,
    );

    // Initial check for scroll extent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.scrollController.hasClients) {
        _handleScrollChange(); // Initialize thumb position
      }
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScrollChange);
    _scrollVisibilityTimer?.cancel();
    _scrollEndTimer?.cancel();
    _thumbAnimationController.dispose();
    super.dispose();
  }

  void _handleScrollChange() {
    if (!mounted || !widget.scrollController.hasClients) return;
    
    final ScrollPosition position = widget.scrollController.position;
    final double viewportDimension = position.viewportDimension;
    final double maxScroll = position.maxScrollExtent;
    final double minScroll = position.minScrollExtent;
    final double scrollExtent = maxScroll - minScroll;
    
    if (scrollExtent <= 0 || viewportDimension <= 0) {
       if (_isScrolling) {
         setState(() => _isScrolling = false);
         _thumbAnimationController.reverse(); // Fade out if no scroll extent
       }
       return;
    }

    // Fixed ratio calculation
    final double ratio = (position.pixels - minScroll) / scrollExtent;
    final double availableSpace = viewportDimension - widget.minThumbLength;
    final double thumbPosition = (1.0 - ratio.clamp(0.0, 1.0)) * availableSpace;

    if (!_isScrolling) {
       setState(() => _isScrolling = true);
       _thumbAnimationController.forward(); // Fade in
    }
    setState(() {
      _currentThumbOffset = thumbPosition.clamp(0.0, availableSpace);
    });

    _scrollVisibilityTimer?.cancel();
    _scrollVisibilityTimer = Timer(const Duration(milliseconds: 800), () { // Longer delay
      if (mounted && !_isDragging && !_isHovering) {
        setState(() => _isScrolling = false);
        _thumbAnimationController.reverse(); // Fade out
      }
    });
  }

  void _startDrag(DragStartDetails details) {
    setState(() => _isDragging = true);
    _thumbAnimationController.forward(); // Ensure visible on drag
  }

  void _endDrag(DragEndDetails details) {
    if (!mounted) return;
    setState(() => _isDragging = false);
    
    if (!_isHovering) {
      _scrollVisibilityTimer?.cancel();
      _scrollVisibilityTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && !_isDragging && !_isHovering) {
          setState(() => _isScrolling = false);
          _thumbAnimationController.reverse(); // Fade out
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
    
    widget.scrollController.jumpTo(
      (position.pixels + scrollDelta).clamp(minScroll, maxScroll)
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scrollController.hasClients) return const SizedBox();

    // Get theme data for scrollbar
    final theme = Theme.of(context);
    final scrollbarTheme = theme.scrollbarTheme;
    final Set<MaterialState> currentStates = {
      if (_isDragging) MaterialState.dragged,
      if (_isHovering) MaterialState.hovered,
    };

    final effectiveThickness = scrollbarTheme.thickness?.resolve(currentStates) ?? widget.thickness;
    final effectiveThumbColor = scrollbarTheme.thumbColor?.resolve(currentStates) ?? theme.colorScheme.onSurface.withOpacity(0.5);
    final effectiveRadius = scrollbarTheme.radius ?? Radius.circular(effectiveThickness / 2);
    final showScrollbar = scrollbarTheme.thumbVisibility?.resolve(currentStates) ?? (_isDragging || _isHovering || _isScrolling);

    try {
      final ScrollPosition position = widget.scrollController.position;
      final double viewportDimension = position.viewportDimension;
      final double scrollExtent = position.maxScrollExtent - position.minScrollExtent;
      
      if (scrollExtent <= 0 || viewportDimension <= 0) return const SizedBox();
      
      final double thumbLength = widget.minThumbLength;
      final double trackHeight = viewportDimension;
      
      // Control visibility with AnimatedOpacity tied to the controller
      if (showScrollbar && _thumbAnimationController.status == AnimationStatus.dismissed) {
          _thumbAnimationController.forward();
      } else if (!showScrollbar && (_thumbAnimationController.status == AnimationStatus.completed || _thumbAnimationController.status == AnimationStatus.forward)) {
          _thumbAnimationController.reverse();
      }
      
      return MouseRegion(
        onEnter: (_) => setState(() {
           _isHovering = true;
           if (scrollbarTheme.thumbVisibility?.resolve({MaterialState.hovered}) ?? true) {
              _thumbAnimationController.forward(); // Fade in on hover if theme allows
           }
        }),
        onExit: (_) => setState(() {
          _isHovering = false;
          if (!_isDragging) {
            _scrollVisibilityTimer?.cancel();
            _scrollVisibilityTimer = Timer(const Duration(milliseconds: 800), () {
              if (mounted && !_isDragging && !_isHovering) {
                setState(() => _isScrolling = false);
                 if (!(scrollbarTheme.thumbVisibility?.resolve({}) ?? true)) { // Check if always visible
                   _thumbAnimationController.reverse(); // Fade out only if not always visible
                 }
              }
            });
          }
        }),
        child: GestureDetector(
          onVerticalDragStart: _startDrag,
          onVerticalDragUpdate: _updateDrag,
          onVerticalDragEnd: _endDrag,
          child: FadeTransition(
            opacity: _thumbOpacityAnimation,
            child: Container(
              width: effectiveThickness + 4, // Add padding for easier grabbing
              height: trackHeight,
              alignment: Alignment.topRight,
              color: Colors.transparent, // Make outer container transparent
              child: Transform.translate(
                offset: Offset(0, _currentThumbOffset),
                child: Container(
                  width: effectiveThickness,
                  height: thumbLength,
                  decoration: BoxDecoration(
                    color: effectiveThumbColor,
                    borderRadius: BorderRadius.all(effectiveRadius),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      print("Error building scrollbar thumb: $e"); // Log errors
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
  bool _isSidePanelVisible = false; // Manage side panel visibility
  bool _isTokenWindowVisible = true;
  static const String _sidePanelKey = 'side_panel_visible';
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
    // _loadSavedStates(); // Keep if you want persistence

    // Use post frame callback for things needing context/build completion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // Check if widget is still mounted
      
      // Set initial side panel visibility
      final screenWidth = MediaQuery.of(context).size.width;
      setState(() {
         _isSidePanelVisible = screenWidth >= 1024; // Example: open on larger screens
      });
      
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
    setState(() {
      _isSidePanelVisible = prefs.getBool(_sidePanelKey) ?? false;
      _isTokenWindowVisible = prefs.getBool(_tokenWindowKey) ?? true;
    });
  }

  Future<void> _saveSidePanelState(bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidePanelKey, isVisible);
  }

  Future<void> _saveTokenWindowState(bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tokenWindowKey, isVisible);
  }

  void _toggleSidePanel() {
     setState(() {
      _isSidePanelVisible = !_isSidePanelVisible;
       // Optionally save state
       // _saveSidePanelState(_isSidePanelVisible); 
    });
  }

  void _toggleTokenWindow() {
    setState(() {
      _isTokenWindowVisible = !_isTokenWindowVisible;
      _saveTokenWindowState(_isTokenWindowVisible);
    });
  }

  void _handleChatUpdate() {
    setState(() {});
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
  }

  void _focusInputField() {
    _inputFocusNode.requestFocus();
  }
  
  void _showModelSelectorDialog() {
     _showModelSelector(context, _chatProvider); // Reuse existing dialog logic
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>(); // Watch for state changes
    final authProvider = context.watch<AuthProvider>();
    final isAuthenticated = authProvider.isAuthenticated;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: Row(
        children: [
          // Animated side panel
          AnimatedContainer(
             duration: const Duration(milliseconds: 250),
             curve: Curves.easeOutCubic,
             width: _isSidePanelVisible ? math.min(MediaQuery.of(context).size.width * 0.8, 300.0) : 0,
             child: _isSidePanelVisible 
                 ? SidePanel(
                     isExpanded: _isSidePanelVisible,
                     onToggle: _toggleSidePanel,
                     onNewChat: () {
                       _focusInputField();
                       if (!kIsWeb && MediaQuery.of(context).size.width < 600) {
                         _toggleSidePanel(); // Close on mobile after new chat
                       }
                     },
                   )
                 : null,
          ),
          
          // Main Chat Content Area
          Expanded(
            child: Column(
              children: [
                // --- Top Control Row --- 
                Padding(
                  padding: EdgeInsets.only(
                     left: AppSpacing.inlineSpacing, 
                     right: AppSpacing.pagePaddingHorizontal,
                     top: MediaQuery.of(context).padding.top + AppSpacing.inlineSpacingSmall, // SafeArea top + padding
                     bottom: AppSpacing.inlineSpacingSmall,
                  ),
                  child: Row(
                    children: [
                      // Hamburger Menu Toggle
                      IconButton(
                        icon: Icon(_isSidePanelVisible ? Icons.close : Icons.menu),
                        tooltip: _isSidePanelVisible ? 'Close Panel' : 'Open Panel',
                        onPressed: _toggleSidePanel,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: AppSpacing.inlineSpacing),
                      // Model Selector Button
                      ModelSelectorButton(
                        selectedModel: chatProvider.selectedModel,
                        availableModels: chatProvider.availableModels,
                      ),
                      const Spacer(), // Pushes token window toggle right
                      // Token Window Toggle (Optional)
                      if (chatProvider.totalTokens > 0)
                         IconButton(
                           icon: Icon(
                             _isTokenWindowVisible ? Icons.insights_rounded : Icons.insights_outlined,
                             size: 20,
                             color: colorScheme.onSurface.withOpacity(0.7),
                           ),
                           onPressed: _toggleTokenWindow,
                           tooltip: _isTokenWindowVisible ? 'Hide Token Usage' : 'Show Token Usage',
                         ),
                    ],
                  ),
                ),
                // --- End Top Control Row ---

                // Token usage visualization (if visible)
                if (_isTokenWindowVisible && chatProvider.totalTokens > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pagePaddingHorizontal,
                      vertical: AppSpacing.inlineSpacingSmall,
                    ),
                    child: TokenWindowVisualization(
                      totalTokens: chatProvider.totalTokens,
                      inputTokens: chatProvider.totalInputTokens,
                      outputTokens: chatProvider.totalOutputTokens,
                      model: chatProvider.selectedModel,
                      totalCost: chatProvider.totalCost,
                    ),
                  ),
                
                // Main chat messages area
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ChatContainer(
                        child: _buildMessagesList(chatProvider),
                      ),
                      // Positioned Scrollbar
                      Positioned(
                        right: 2, 
                        top: 0,
                        bottom: 0,
                        child: CustomScrollbarThumb(
                          scrollController: _scrollManager.controller,
                        ),
                      ),
                      // Error Message Overlay
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
                
                // Message input area
                ChatContainer(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + AppSpacing.inlineSpacing, // SafeArea bottom + padding
                      left: AppSpacing.inlineSpacing, // Add consistent padding
                      right: AppSpacing.inlineSpacing,
                    ),
                    child: _buildMessageInput(chatProvider, isAuthenticated),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(ChatProvider chatProvider) {
    final messages = chatProvider.messages;
    final theme = Theme.of(context); // Get theme for empty state

    if (messages.isEmpty) {
      return _buildEmptyState(context);
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // Dismiss keyboard on tap
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _scrollManager.controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePaddingHorizontal),
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
                  horizontal: AppSpacing.inlineSpacingSmall, // Adjust spacing as needed
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
                        content: Text('Failed to create conversation. Please try again.'),
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
                context.read<ChatProvider>().initialize(syncModelsWithBackend: true);
              }
            },
            icon: Icon(hasModels ? Icons.model_training : Icons.refresh),
            label: Text(hasModels ? 'Select' : 'Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isLoading = _chatProvider.isLoading;
    final errorMessage = _chatProvider.error;
    final hasModels = _chatProvider.availableModels.isNotEmpty;
    final selectedModel = _chatProvider.selectedModel;
    
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
                Icon( // Updated Icon for welcome state
                  hasModels ? Icons.waving_hand_outlined : Icons.error_outline, // Waving hand icon
                  size: 64,
                  color: hasModels
                    ? Theme.of(context).colorScheme.primary // Use primary color directly
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
                Text( // Personalized welcome message using display name
                  'Hola, ${_chatProvider.currentDisplayName ?? 'there'}!', // Use currentDisplayName
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                     fontWeight: FontWeight.w600, // Slightly bolder
                     color: Theme.of(context).colorScheme.primary, // Use primary color
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
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  )
                else if (hasModels && selectedModel == null)
                  Text(
                    'Please select a model to continue',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  )
                else if (!hasModels)
                  Text(
                    'Check your internet connection and try again',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.error.withOpacity(0.7),
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
              Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer, size: 20),
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 450),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title bar
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                              return model.displayName.toLowerCase().contains(_modelSearchQuery) ||
                                     model.modelId.toLowerCase().contains(_modelSearchQuery) ||
                                     model.provider.toLowerCase().contains(_modelSearchQuery);
                            }).toList();

                      if (filteredModels.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 48,
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No models found',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
                          final isSelected = chatProvider.selectedModel?.modelId == model.modelId;

                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                            title: Text(
                              model.displayName,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Theme.of(context).colorScheme.primary : null,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
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
