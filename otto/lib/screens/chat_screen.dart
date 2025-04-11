import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart'; // Add import for ScrollDirection
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:math';
import '../services/chat_provider.dart';
import '../services/auth_provider.dart';
import '../theme/theme_provider.dart';
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
  bool _isAutoScrollEnabled = true;
  bool _userScrolling = false;
  DateTime? _lastUserScroll;
  static const Duration _userScrollTimeout = Duration(seconds: 3);

  ChatScrollManager() : controller = ScrollController();

  void initialize() {
    controller.addListener(_handleScroll);
  }

  void dispose() {
    controller.removeListener(_handleScroll);
    controller.dispose();
  }

  void _handleScroll() {
    if (!controller.hasClients) return;
    
    // Track user scrolling more reliably
    final ScrollPosition position = controller.position;
    
    // Consider it user scrolling when not at bottom and moving
    if (position.userScrollDirection != ScrollDirection.idle) {
      _userScrolling = true;
      _lastUserScroll = DateTime.now();
      
      // Only disable auto-scroll when scrolling away from bottom
      if (position.userScrollDirection == ScrollDirection.forward) {
        debugPrint("User scrolled up - disabling auto-scroll");
        _isAutoScrollEnabled = false;
      }
    }
    
    // Check if we've scrolled back to the bottom
    if (!_isAutoScrollEnabled && _isAtBottom) {
      debugPrint("Reached bottom - re-enabling auto-scroll");
      _isAutoScrollEnabled = true;
    }
  }

  // Check if we're at the bottom of the list
  bool get _isAtBottom {
    if (!controller.hasClients) return true;
    
    final position = controller.position;
    // Consider "at bottom" if within 20 pixels of bottom
    return position.pixels >= (position.maxScrollExtent - 20);
  }

  bool get shouldAutoScroll {
    // If auto-scroll is disabled by user action, don't auto-scroll
    if (!_isAutoScrollEnabled) return false;
    
    // If we're near bottom or no clients yet, allow auto-scroll
    if (!controller.hasClients) return true;
    
    return _isAtBottom;
  }

  void scrollToBottom({bool animate = true}) {
    if (!controller.hasClients) return;
    
    try {
      // Skip if user is actively scrolling
      if (_userScrolling && 
          _lastUserScroll != null && 
          DateTime.now().difference(_lastUserScroll!) < _userScrollTimeout) {
        debugPrint("User is actively scrolling - skip auto-scroll");
        return;
      }
      
      final position = controller.position;
      final maxScroll = position.maxScrollExtent;
      
      // Use simpler animation for smoother effect
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
    _isAutoScrollEnabled = true;
    _userScrolling = false;
    _lastUserScroll = null;
    debugPrint("Scroll manager reset");
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

class _CustomScrollbarThumbState extends State<CustomScrollbarThumb> {
  bool _isDragging = false;
  bool _isHovering = false;
  bool _isScrolling = false;
  DateTime _lastScrollUpdate = DateTime.now();
  Timer? _scrollVisibilityTimer;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScrollChange);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScrollChange);
    _scrollVisibilityTimer?.cancel();
    super.dispose();
  }

  void _handleScrollChange() {
    final now = DateTime.now();
    setState(() {
      _isScrolling = true;
      _lastScrollUpdate = now;
    });

    // Hide scrollbar after inactivity (reduced to 400ms for even faster disappearance)
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
    
    // If we're not hovering, schedule hiding the scrollbar
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
    final ScrollPosition position = widget.scrollController.position;
    final double fullExtent = position.maxScrollExtent - position.minScrollExtent;
    
    if (fullExtent <= 0) return;
    
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final double dragDelta = details.delta.dy;
    final double scrollDelta = dragDelta * fullExtent / renderBox.size.height;
    
    widget.scrollController.jumpTo(widget.scrollController.offset + scrollDelta);
  }

  @override
  Widget build(BuildContext context) {
    final ScrollPosition position = widget.scrollController.position;
    final double viewportDimension = position.viewportDimension;
    final double fullExtent = position.maxScrollExtent - position.minScrollExtent;
    
    // Don't show scrollbar if there's nothing to scroll
    if (fullExtent <= 0 || viewportDimension <= 0) {
      return const SizedBox();
    }
    
    // Calculate the available scroll space for the thumb to travel in
    final double thumbLength = widget.minThumbLength;
    final double scrollbarHeight = viewportDimension;
    final double trackHeight = scrollbarHeight;
    final double maxThumbOffset = trackHeight - thumbLength;
    
    // Calculate thumb position using the scroll position ratio
    final double scrollPositionRatio = fullExtent > 0 ? position.pixels / fullExtent : 0.0;
    final double thumbOffset = scrollPositionRatio * maxThumbOffset;
    
    // Only show the scrollbar when user is interacting or scrolling
    final bool shouldShowScrollbar = _isDragging || _isHovering || _isScrolling;
    
    return Positioned(
      right: 2.0,
      top: 0,
      bottom: 0,
      width: 12.0,
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _isHovering = true;
        }),
        onExit: (_) => setState(() {
          _isHovering = false;
          if (!_isDragging) {
            _scrollVisibilityTimer?.cancel();
            _scrollVisibilityTimer = Timer(const Duration(milliseconds: 400), () {
              if (mounted && !_isDragging && !_isHovering) {
                setState(() {
                  _isScrolling = false;
                });
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
                offset: Offset(0, thumbOffset.clamp(0, maxThumbOffset)),
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
      ),
    );
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
    
    // Check if there are messages and if we need to scroll
    if (_chatProvider.messages.isNotEmpty && _scrollManager.shouldAutoScroll) {
      // Use a short delay to ensure proper UI update before scrolling
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _scrollManager.scrollToBottom(animate: !_chatProvider.isLoading);
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
      body: SafeArea(
        bottom: false,
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
            
            // Main chat area
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Side panel and chat messages
                  Row(
                    children: [
                      // Side panel with animated container
                      ClipRect(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          width: _isSidePanelExpanded ? null : 0,
                          child: _isSidePanelExpanded 
                              ? SidePanel(
                                  onNewChat: () {
                                    // Focus the input field when a new conversation is created
                                    _focusInputField();
                                  },
                                  onToggle: _toggleSidePanel,
                                  isExpanded: _isSidePanelExpanded,
                                  animationDuration: const Duration(milliseconds: 300),
                                )
                              : null,
                        ),
                      ),
                      
                      // Chat messages area with animated width and shadow
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            // Add a subtle shadow when side panel is expanded
                            boxShadow: [
                              if (_isSidePanelExpanded)
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  offset: const Offset(-2, 0),
                                  blurRadius: 8,
                                )
                            ],
                          ),
                          child: Column(
                            children: [
                              // App bar
                              _buildAppBar(context, isDarkMode),
                              
                              // Messages list
                              Expanded(
                                child: _buildMessagesList(_chatProvider),
                              ),
                              
                              // Message input
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: MediaQuery.of(context).viewPadding.bottom,
                                ),
                                child: _buildMessageInput(_chatProvider, isAuthenticated),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Error message
                  if (_chatProvider.error != null)
                    _buildErrorMessage(_chatProvider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDarkMode) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Add padding before the button to move it right
          const SizedBox(width: 8),
          
          // Side panel toggle with consistent hamburger icon
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _toggleSidePanel,
            tooltip: _isSidePanelExpanded ? 'Close side panel' : 'Open side panel',
          ),
          
          // App title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Otto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const Spacer(),

          // Token window toggle
          if (_chatProvider.totalTokens > 0)
            IconButton(
              icon: Icon(_isTokenWindowVisible ? Icons.analytics : Icons.analytics_outlined),
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
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _chatProvider.selectedModel?.displayName ?? 'Select Model',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to the actual SettingsScreen
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
          
          // Sign out button
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              _showSignOutConfirmation(context);
            },
            tooltip: 'Sign out',
          ),
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
                  // Main scrollable content with stabilized layout
                  Container(
                    width: constraints.maxWidth,
                    child: NotificationListener<ScrollNotification>(
                      // Handle scroll notifications to update the scroll manager
                      onNotification: (notification) {
                        // Only process user-driven scrolls
                        if (notification is ScrollUpdateNotification && 
                            notification.dragDetails != null) {
                          // Update user scrolling state
                          _scrollManager._userScrolling = true;
                          _scrollManager._lastUserScroll = DateTime.now();
                        }
                        return false;
                      },
                      child: ScrollConfiguration(
                        // Remove default scrollbar
                        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: ListView.builder(
                          key: const ValueKey('messages_list'),
                          controller: _scrollManager.controller,
                          padding: EdgeInsets.only(
                            top: 8,
                            bottom: MediaQuery.of(context).padding.bottom + 15,
                            right: 12.0, // Right padding for scrollbar space
                          ),
                          physics: const ClampingScrollPhysics(),
                          reverse: false,
                          addRepaintBoundaries: true,
                          cacheExtent: 1000,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            
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
                  ),
                  
                  // Custom fixed-size scrollbar thumb
                  CustomScrollbarThumb(
                    scrollController: _scrollManager.controller,
                    color: theme.colorScheme.primary,
                    thickness: 6.0,
                    height: 60.0,
                    minThumbLength: 60.0,
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
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16,
        top: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface.withOpacity(0.5),
            theme.colorScheme.surface.withOpacity(0.65),
            theme.colorScheme.surface.withOpacity(0.8),
            theme.colorScheme.surface.withOpacity(0.65),
            theme.colorScheme.surface.withOpacity(0.5),
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: EdgeInsets.zero,
            color: Colors.transparent,
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
          ),
        ),
      ),
    );
  }

  Widget _buildNoModelsInput() {
    final chatProvider = Provider.of<ChatProvider>(context);
    final hasModels = chatProvider.availableModels.isNotEmpty;
    final isLoading = chatProvider.isLoading;
    final selectedModel = chatProvider.selectedModel;
    
    final String errorMessage = hasModels 
        ? 'Cannot send messages: No model selected' 
        : 'Cannot send messages: Connection to AI service unavailable';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              if (hasModels) {
                // If models are available but none selected, show model selector
                _showModelSelector(context, chatProvider);
              } else {
                // If no models available, retry connection
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
