import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart'; // Add import for ScrollDirection
import 'package:flutter/gestures.dart'; // Add this import for PointerScrollEvent
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:math';
import '../services/chat_provider.dart';
import '../services/auth_provider.dart';
import '../theme/theme_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/chat_message.dart';
import '../widgets/message_input.dart';
import '../widgets/model_selector.dart';
import '../widgets/side_panel.dart';
import '../screens/model_management_screen.dart';
import '../screens/settings_screen.dart'; // Import the new settings screen
import '../widgets/token_window_visualization.dart';
import '../config/env_config.dart';
import 'dart:async';

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
  final double thickness;
  final Color color;
  final double height;
  final double minThumbLength;

  const CustomScrollbarThumb({
    Key? key,
    required this.scrollController,
    this.thickness = 6.0,
    required this.color,
    this.height = 60.0,
    this.minThumbLength = 60.0,
  }) : super(key: key);

  @override
  State<CustomScrollbarThumb> createState() => _CustomScrollbarThumbState();
}

class _CustomScrollbarThumbState extends State<CustomScrollbarThumb> with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  bool _isHovering = false;
  bool _isScrolling = false;
  DateTime _lastScrollUpdate = DateTime.now();
  Timer? _scrollVisibilityTimer;
  late AnimationController _thumbAnimationController;
  late Animation<double> _thumbPositionAnimation;
  double _currentThumbOffset = 0.0;
  double _lastScrollPosition = 0.0;
  Timer? _scrollEndTimer;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScrollChange);
    
    // Initialize animation controller for smooth thumb movement
    _thumbAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150), // Increased duration for smoother movement
    );
    
    _thumbPositionAnimation = _thumbAnimationController
      .drive(CurveTween(curve: Curves.easeOutExpo)) // Changed to easeOutExpo for smoother deceleration
      .drive(Tween<double>(begin: 0.0, end: 0.0));
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
    
    if (maxScroll <= 0 || viewportDimension <= 0) return;

    // Fixed ratio calculation
    final double ratio = position.pixels / maxScroll;
    final double availableSpace = viewportDimension - widget.minThumbLength;
    final double thumbPosition = (1.0 - ratio.clamp(0.0, 1.0)) * availableSpace;

    setState(() {
      _currentThumbOffset = thumbPosition.clamp(0.0, availableSpace);
      _isScrolling = true;
    });

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
    
    if (maxScroll <= 0 || viewportDimension <= 0) return;

    // Fixed ratio for drag
    final double availableSpace = viewportDimension - widget.minThumbLength;
    final double dragDelta = details.delta.dy;
    final double dragRatio = dragDelta / availableSpace;
    final double scrollDelta = -dragRatio * maxScroll;
    
    widget.scrollController.jumpTo(
      (position.pixels + scrollDelta).clamp(0.0, maxScroll)
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scrollController.hasClients) return const SizedBox();

    try {
      final ScrollPosition position = widget.scrollController.position;
      final double viewportDimension = position.viewportDimension;
      final double fullExtent = position.maxScrollExtent - position.minScrollExtent;
      
      if (fullExtent <= 0 || viewportDimension <= 0) return const SizedBox();
      
      final double thumbLength = widget.minThumbLength;
      final double trackHeight = viewportDimension;
      final bool shouldShowScrollbar = _isDragging || _isHovering || _isScrolling;
      
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() {
          _isHovering = false;
          if (!_isDragging) {
            _scrollVisibilityTimer?.cancel();
            _scrollVisibilityTimer = Timer(const Duration(milliseconds: 400), () {
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
              width: 12.0,
              height: trackHeight,
              alignment: Alignment.topRight,
              child: Transform.translate(
                offset: Offset(0, _currentThumbOffset),
                child: Container(
                  width: widget.thickness,
                  height: thumbLength,
                  decoration: BoxDecoration(
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
  bool _isSidePanelExpanded = true;
  bool _isTokenWindowVisible = true;
  static const String _sidePanelKey = 'side_panel_expanded';
  static const String _tokenWindowKey = 'token_window_visible';
  late AnimationController _shimmerController;
  late TextEditingController _messageController;
  String _modelSearchQuery = '';
  late ChatProvider _chatProvider; // Store a reference to the ChatProvider

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _loadSavedStates();
    
    // Get ChatProvider immediately in initState
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    // Initialize controllers
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    // Initialize scroll manager
    _scrollManager.initialize();
    
    // Set up other providers and listeners post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Add listener first
      _chatProvider.addListener(_handleChatUpdate);
      
      // Initialize chat in the background
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
      _isSidePanelExpanded = prefs.getBool(_sidePanelKey) ?? true;
      _isTokenWindowVisible = prefs.getBool(_tokenWindowKey) ?? true;
    });
  }

  Future<void> _saveSidePanelState(bool isExpanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidePanelKey, isExpanded);
  }

  Future<void> _saveTokenWindowState(bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tokenWindowKey, isVisible);
  }

  void _toggleSidePanel() {
    setState(() {
      _isSidePanelExpanded = !_isSidePanelExpanded;
      _saveSidePanelState(_isSidePanelExpanded);
      
      // Play a subtle haptic feedback when toggling the panel
      HapticFeedback.lightImpact();
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
    
    // Only scroll to bottom when sending a new message
    if (_chatProvider.messages.isNotEmpty && _chatProvider.isLoading) {
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final authProvider = Provider.of<AuthProvider>(context);
    final isAuthenticated = authProvider.isAuthenticated;
    
    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.background : AppColors.backgroundAlt,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: Row(
          children: [
            if (_isSidePanelExpanded) SidePanel(
              isExpanded: _isSidePanelExpanded,
              onToggle: _toggleSidePanel,
              onNewChat: () {
                _focusInputField();
              },
            ),
            Expanded(
              child: Column(
                children: [
                  // Token usage visualization
                  if (_isTokenWindowVisible && _chatProvider.totalTokens > 0)
                    TokenWindowVisualization(
                      totalTokens: _chatProvider.totalTokens,
                      inputTokens: _chatProvider.totalInputTokens,
                      outputTokens: _chatProvider.totalOutputTokens,
                      model: _chatProvider.selectedModel,
                      totalCost: _chatProvider.totalCost,
                    ),
                  
                  // App bar
                  _buildAppBar(context, isDarkMode),
                  
                  // Main chat area
                  Expanded(
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent && _scrollManager.controller.hasClients) {
                          _scrollManager.controller.jumpTo(
                            (_scrollManager.controller.offset + event.scrollDelta.dy)
                              .clamp(0.0, _scrollManager.controller.position.maxScrollExtent)
                          );
                        }
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ChatContainer(
                            child: _buildMessagesList(_chatProvider),
                          ),
                          Positioned(
                            right: 2,
                            top: 0,
                            bottom: 0,
                            child: CustomScrollbarThumb(
                              scrollController: _scrollManager.controller,
                              color: AppColors.scrollbarThumb,
                            ),
                          ),
                          if (_chatProvider.error != null)
                            _buildErrorMessage(_chatProvider),
                        ],
                      ),
                    ),
                  ),
                  
                  // Message input at the bottom
                  ChatContainer(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewPadding.bottom,
                      ),
                      child: _buildMessageInput(_chatProvider, isAuthenticated),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDarkMode) {
    final theme = Theme.of(context);
    
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.background : AppColors.backgroundAlt,
        gradient: AppColors.backgroundGradient,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Add padding before the button to move it right
          const SizedBox(width: 8),
          
          // Side panel toggle with consistent hamburger icon
          IconButton(
            icon: Icon(
              Icons.menu,
              color: AppColors.onSurface.withOpacity(0.8),
            ),
            onPressed: _toggleSidePanel,
            tooltip: _isSidePanelExpanded ? 'Close side panel' : 'Open side panel',
          ),
          
          // App title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Otto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ),
          
          const Spacer(),

          // Token window toggle
          if (_chatProvider.totalTokens > 0)
            IconButton(
              icon: Icon(
                _isTokenWindowVisible ? Icons.analytics : Icons.analytics_outlined,
                color: AppColors.onSurface.withOpacity(0.8),
              ),
              onPressed: _toggleTokenWindow,
              tooltip: _isTokenWindowVisible ? 'Hide token usage' : 'Show token usage',
            ),
          
          // Model selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _showModelSelector(context, _chatProvider);
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.onSurface.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _chatProvider.selectedModel?.displayName ?? 'Select Model',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        color: AppColors.onSurface.withOpacity(0.8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Settings button
          IconButton(
            icon: Icon(
              Icons.settings,
              color: AppColors.onSurface.withOpacity(0.8),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
          
          // Sign out button
          IconButton(
            icon: Icon(
              Icons.logout,
              color: AppColors.onSurface.withOpacity(0.8),
            ),
            onPressed: () {
              _showSignOutConfirmation(context);
            },
            tooltip: 'Sign out',
          ),
          
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildMessagesList(ChatProvider chatProvider) {
    var messages = chatProvider.messages;
    final theme = Theme.of(context);

    return Stack(
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: messages.isEmpty ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !messages.isEmpty,
            child: _buildEmptyState(context),
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: messages.isEmpty ? 0.0 : 1.0,
          child: IgnorePointer(
            ignoring: messages.isEmpty,
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: constraints.maxWidth,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: false,
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: ListView.builder(
                        key: const ValueKey('messages_list'),
                        controller: _scrollManager.controller,
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: MediaQuery.of(context).padding.bottom + 15,
                          right: 12.0,
                        ),
                        physics: const AlwaysScrollableScrollPhysics(),
                        primary: false,
                        shrinkWrap: false,
                        reverse: true,
                        addRepaintBoundaries: true,
                        cacheExtent: 10000,
                        clipBehavior: Clip.none,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          
                          return RepaintBoundary(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.0),
                              child: ChatMessageWidget(
                                key: ValueKey('msg_${message.id}'),
                                message: message,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              chatProvider.error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              chatProvider.clearError();
            },
            tooltip: 'Dismiss error',
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ],
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
        final maxWidth = min(850.0, constraints.maxWidth);
        
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
