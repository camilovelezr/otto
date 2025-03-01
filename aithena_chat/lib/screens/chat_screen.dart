import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:math';
import '../services/chat_provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/chat_message_widget.dart';
import '../widgets/message_input.dart';
import '../widgets/model_selector.dart';
import '../widgets/side_panel.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isSidePanelExpanded = true;
  static const String _sidePanelKey = 'side_panel_expanded';
  late AnimationController _shimmerController;
  late AnimationController _scrollButtonController;
  late Animation<double> _scrollButtonScale;
  late Animation<double> _scrollButtonOpacity;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadSidePanelState();
    
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
    _scrollController.removeListener(_handleScroll);
    _shimmerController.dispose();
    _scrollButtonController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _loadModels() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadModels();
    });
  }

  Future<void> _loadSidePanelState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isSidePanelExpanded = prefs.getBool(_sidePanelKey) ?? true;
    });
  }

  Future<void> _saveSidePanelState(bool isExpanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidePanelKey, isExpanded);
  }

  void _toggleSidePanel() {
    setState(() {
      _isSidePanelExpanded = !_isSidePanelExpanded;
      _saveSidePanelState(_isSidePanelExpanded);
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

  Widget _buildHeader(BuildContext context, ThemeData theme, ChatProvider chatProvider) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = kToolbarHeight * 1.2 + topPadding;

    return Container(
      height: headerHeight,
      color: theme.colorScheme.background,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            color: theme.colorScheme.background.withOpacity(0.65),
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: topPadding + 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.2)!,
                        Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.4)!,
                        Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.6)!,
                        theme.colorScheme.secondary,
                      ],
                      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _toggleSidePanel();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          tween: Tween<double>(
                            begin: _isSidePanelExpanded ? 0 : 1,
                            end: _isSidePanelExpanded ? 0 : 1,
                          ),
                          builder: (context, value, child) => Transform.rotate(
                            angle: value * pi,
                            child: child,
                          ),
                          child: const Icon(
                            Icons.keyboard_double_arrow_left_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (chatProvider.selectedModel != null)
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  theme.colorScheme.surface.withOpacity(0.4),
                                  theme.colorScheme.surface.withOpacity(0.6),
                                  theme.colorScheme.surface.withOpacity(0.8),
                                  theme.colorScheme.surface.withOpacity(0.6),
                                  theme.colorScheme.surface.withOpacity(0.4),
                                ],
                                stops: [
                                  0.0,
                                  (_shimmerController.value - 0.2).clamp(0.0, 1.0),
                                  _shimmerController.value,
                                  (_shimmerController.value + 0.2).clamp(0.0, 1.0),
                                  1.0,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: child,
                          );
                        },
                        child: ModelSelector(
                          models: chatProvider.availableModels,
                          selectedModel: chatProvider.selectedModel!,
                          onModelSelected: chatProvider.selectModel,
                          scrollController: _scrollController,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.messages;
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

    return Scaffold(
      body: Row(
        children: [
          SidePanel(
            isExpanded: _isSidePanelExpanded,
            onToggle: _toggleSidePanel,
          ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(context, theme, chatProvider),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.background,
                        ),
                        child: Stack(
                          children: [
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: messages.isEmpty ? 1.0 : 0.0,
                              child: IgnorePointer(
                                ignoring: !messages.isEmpty,
                                child: _buildEmptyState(theme),
                              ),
                            ),
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: messages.isEmpty ? 0.0 : 1.0,
                              child: IgnorePointer(
                                ignoring: messages.isEmpty,
                                child: ClipRect(
                                  child: Stack(
                                    children: [
                                      ListView.builder(
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

                                          return ChatMessageWidget(
                                            key: ValueKey(message.id),
                                            message: message,
                                            isStreaming: isStreaming,
                                            streamedContent: chatProvider.currentStreamedResponse,
                                          );
                                        },
                                      ),
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: -4,
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
                                                      theme.colorScheme.primary,
                                                      Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.25)!,
                                                      Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.5)!,
                                                      Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.75)!,
                                                      theme.colorScheme.secondary,
                                                    ],
                                                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                                                  ),
                                                  borderRadius: BorderRadius.circular(24),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: theme.colorScheme.primary.withOpacity(0.12),
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
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: bottomPadding + 8.0,
                        top: 0,
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
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            color: Colors.transparent,
                            child: MessageInput(
                              onSubmit: (content) {
                                chatProvider.sendMessage(content);
                                // Immediately scroll after user message is added
                                _scrollToShowNewMessage();
                              },
                              isLoading: chatProvider.isLoading,
                              focusNode: _inputFocusNode,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final chatProvider = Provider.of<ChatProvider>(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.3)!,
                  Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.5)!,
                  Color.lerp(theme.colorScheme.primary, theme.colorScheme.secondary, 0.7)!,
                  theme.colorScheme.secondary,
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
              borderRadius: BorderRadius.circular(60),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
          
          if (chatProvider.error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Text(
                    'Error',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chatProvider.error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onBackground.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      chatProvider.clearError();
                      chatProvider.loadModels();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          
          if (chatProvider.error == null)
            const SizedBox(height: 20),
          Text(
            'Start a Conversation',
            style: theme.textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Select a model and start chatting',
            style: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onBackground.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel() {
    final chatProvider = Provider.of<ChatProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1F1F33) : Colors.white,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              'Aithena',
              style: theme.textTheme.displayLarge,
            ),
            actions: [
              // Add a menu button for settings and tools
              PopupMenuButton<String>(
                icon: const Icon(Icons.settings),
                onSelected: (value) {
                  if (value == 'spacing') {
                    Navigator.pushNamed(context, '/spacing-example');
                  } else if (value == 'theme') {
                    themeProvider.toggleTheme();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'spacing',
                    child: Text('Spacing Guide'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'theme',
                    child: Text('Toggle Theme'),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _toggleSidePanel(),
                tooltip: 'Close side panel',
              ),
            ],
          ),
          // ... rest of the existing side panel code ...
        ],
      ),
    );
  }
} 