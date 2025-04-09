import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isSidePanelExpanded = true;
  bool _isTokenWindowVisible = true;
  static const String _sidePanelKey = 'side_panel_expanded';
  static const String _tokenWindowKey = 'token_window_visible';
  late AnimationController _shimmerController;
  late AnimationController _scrollButtonController;
  late Animation<double> _scrollButtonScale;
  late Animation<double> _scrollButtonOpacity;
  bool _showScrollToBottom = false;
  late TextEditingController _messageController;
  String _modelSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _loadSavedStates();
    
    // Defer initialization to after the build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
    
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _scrollButtonController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scrollButtonScale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scrollButtonController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));

    _scrollButtonOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scrollButtonController,
      curve: Curves.easeOut,
    ));

    _scrollController.addListener(_handleScroll);
    
    // Listen for conversation changes to focus the input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      chatProvider.addListener(_handleConversationChange);
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    _updateScrollButtonVisibility();
  }

  void _updateScrollButtonVisibility() {
    if (!_scrollController.hasClients) return;
    
    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;
    
    // Show button if we're not at the bottom
    final showButton = currentScroll < maxScroll - 10;
    
    if (showButton != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = showButton;
      });
      if (showButton) {
        _scrollButtonController.forward(from: 0);
      } else {
        _scrollButtonController.reverse();
      }
    }
  }

  @override
  void dispose() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.removeListener(_handleConversationChange);
    _shimmerController.dispose();
    _scrollButtonController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _initializeChat() async {
    // Initialize the chat provider
    final chatProvider = context.read<ChatProvider>();
    await chatProvider.initialize();
    
    // Focus the input field if a conversation exists
    if (chatProvider.conversationId != null) {
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

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
    );
    _inputFocusNode.requestFocus();
  }

  void _scrollToShowNewMessage() {
    if (!_scrollController.hasClients) return;
    
    // First jump to bottom to ensure message is rendered
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    
    // Then do a small animation to give visual feedback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
    });
  }

  double _calculateMessageSpacing(bool isNewUserMessage) {
    // Not needed anymore since we're using reverse: true
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
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
            if (_isTokenWindowVisible && chatProvider.totalTokens > 0)
              TokenWindowVisualization(
                totalTokens: chatProvider.totalTokens,
                inputTokens: chatProvider.totalInputTokens,
                outputTokens: chatProvider.totalOutputTokens,
                model: chatProvider.selectedModel,
                totalCost: chatProvider.totalCost,
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
                      ClipRect( // Restore ClipRect
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
                                child: _buildMessagesList(chatProvider),
                              ),
                              
                              // Message input
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: MediaQuery.of(context).viewPadding.bottom,
                                ),
                                child: _buildMessageInput(chatProvider, isAuthenticated),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Scroll to bottom button
                  _buildScrollToBottomButton(),
                  
                  // Error message
                  if (chatProvider.error != null)
                    _buildErrorMessage(chatProvider),
                    
                  // Loading indicator for model reload
                  if (chatProvider.isLoadingModels)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black38,
                        child: Center(
                          child: Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    "Loading models...",
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
    final chatProvider = Provider.of<ChatProvider>(context);
    
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
          if (chatProvider.totalTokens > 0)
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
                  _showModelSelector(context, chatProvider);
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
                        chatProvider.selectedModel?.displayName ?? 'Select Model',
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
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final viewportHeight = MediaQuery.of(context).size.height;

    // Update scroll button visibility and scroll to new messages
    if (mounted && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollButtonVisibility();
        
        // Only scroll for new user messages, not for streaming responses
        if (messages.isNotEmpty && messages.last.isUser) {
          _scrollToShowNewMessage();
        }
      });
    }

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
            child: ClipRect(
              child: ListView.builder(
                key: const ValueKey('messages_list'),
                controller: _scrollController,
                padding: EdgeInsets.only(
                  top: 8,
                  bottom: MediaQuery.of(context).padding.bottom + 15,
                ),
                physics: const ClampingScrollPhysics(),
                reverse: false,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isLastMessage = index == messages.length - 1;
                  final isStreaming = isLastMessage && chatProvider.isLoading;

                  // Debug logging for streaming state
                  if (isLastMessage && isStreaming) {
                    debugPrint('Rendering streaming message - Content length: ${message.content?.length ?? 0}');
                  }

                  // Ensure we scroll to bottom for streaming messages
                  if (isLastMessage && isStreaming) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(
                          _scrollController.position.maxScrollExtent,
                        );
                      }
                    });
                  }

                  return ChatMessageWidget(
                    key: ValueKey('${message.id}_${message.content?.length ?? 0}_${isStreaming ? DateTime.now().millisecondsSinceEpoch : ''}'),
                    message: message,
                  );
                },
              ),
            ),
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
                      
                      // Immediately scroll after user message is added
                      _scrollToShowNewMessage();
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

  Widget _buildScrollToBottomButton() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _scrollButtonController,
          builder: (context, child) {
            return Opacity(
              opacity: _scrollButtonOpacity.value,
              child: Transform.scale(
                scale: _scrollButtonScale.value,
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary, 0.25)!,
                    Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary, 0.5)!,
                    Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary, 0.75)!,
                    Theme.of(context).colorScheme.secondary,
                  ],
                  stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _scrollToBottom();
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.arrow_downward_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context);
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
                  'Hi, ${chatProvider.currentDisplayName ?? 'there'}!', // Use currentDisplayName
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
              
              // Removed the AI Service Status box as requested
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

  // Focus input when conversation changes
  void _handleConversationChange() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    // Check if the current conversation is new or temporary
    if (chatProvider.conversationId != null && 
        chatProvider.conversationId!.startsWith("temp_")) {
      // Focus the input field for new conversations
      _focusInputField();
    }
  }
  
  // Expose method to focus the input field
  void _focusInputField() {
    // Delay focus to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _inputFocusNode.canRequestFocus) {
        _inputFocusNode.requestFocus();
      }
    });
  }
}
