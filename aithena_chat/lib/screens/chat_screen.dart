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
  bool _isSidePanelExpanded = true;
  static const String _sidePanelKey = 'side_panel_expanded';
  late AnimationController _shimmerController;
  bool _isUserScroll = true;
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

    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    
    // Check if user has scrolled up
    final position = _scrollController.position;
    final showButton = position.pixels < position.maxScrollExtent - 100;
    
    if (showButton != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = showButton;
      });
    }

    // Check if we're at the bottom (with a smaller threshold)
    final isAtBottom = position.pixels >= position.maxScrollExtent - 20;
    if (isAtBottom != !_isUserScroll) {
      setState(() {
        _isUserScroll = !isAtBottom;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _shimmerController.dispose();
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
    
    final position = _scrollController.position;
    final target = position.maxScrollExtent + 
                  MediaQuery.of(context).padding.bottom;
    
    // Always jump to bottom during streaming for smooth experience
    _scrollController.jumpTo(target);
  }

  Widget _buildHeader(BuildContext context, ThemeData theme, ChatProvider chatProvider) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = kToolbarHeight * 1.2 + topPadding;

    return Container(
      height: headerHeight,
      color: theme.colorScheme.background,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: theme.colorScheme.background.withOpacity(0.7),
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: topPadding + 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                // Side Panel Toggle Button
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        Color.lerp(
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                          0.3,
                        )!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                        spreadRadius: 0,
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
                // Model Selector
                if (chatProvider.selectedModel != null)
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  theme.colorScheme.surface.withOpacity(0.5),
                                  theme.colorScheme.surface.withOpacity(0.7),
                                  theme.colorScheme.surface.withOpacity(0.5),
                                ],
                                stops: [
                                  0.0,
                                  _shimmerController.value,
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

    // Auto-scroll logic
    if (chatProvider.isLoading) {
      if (chatProvider.currentStreamedResponse.isEmpty) {
        // Immediate scroll when message is first sent
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToBottom();
        });
      } else if (!_isUserScroll) {
        // Smooth scroll during streaming
        _scrollToBottom();
      }
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
                        child: messages.isEmpty
                            ? _buildEmptyState(theme)
                            : Stack(
                                children: [
                                  ListView.builder(
                                    controller: _scrollController,
                                    padding: EdgeInsets.only(
                                      bottom: 20 + MediaQuery.of(context).padding.bottom,
                                    ),
                                    physics: const AlwaysScrollableScrollPhysics(),
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
                                  if (_showScrollToBottom)
                                    Positioned(
                                      right: 16,
                                      bottom: 16,
                                      child: AnimatedScale(
                                        scale: _showScrollToBottom ? 1.0 : 0.0,
                                        duration: const Duration(milliseconds: 200),
                                        curve: Curves.easeOutCubic,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                theme.colorScheme.primary,
                                                Color.lerp(
                                                  theme.colorScheme.primary,
                                                  theme.colorScheme.secondary,
                                                  0.3,
                                                )!,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(24),
                                            boxShadow: [
                                              BoxShadow(
                                                color: theme.colorScheme.primary.withOpacity(0.15),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                                spreadRadius: 0,
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
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.arrow_downward_rounded,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Scroll to Bottom',
                                                      style: theme.textTheme.labelLarge?.copyWith(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
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
                    // Message input at bottom
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        top: 8,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.shadow.withOpacity(0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                              spreadRadius: 0,
                            ),
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.05),
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                              spreadRadius: -1,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              color: Colors.transparent,
                              child: MessageInput(
                                onSubmit: chatProvider.sendMessage,
                                isLoading: chatProvider.isLoading,
                              ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: context.read<ThemeProvider>().primaryGradient,
                borderRadius: BorderRadius.circular(60),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
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
      ),
    );
  }
} 