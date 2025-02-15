import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
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
    // Only used for autoscroll detection now
    if (!_scrollController.hasClients || !_isUserScroll) return;
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
    
    _isUserScroll = false;
    
    // Ensure we're getting the latest content height and wait for layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Wait for another frame to ensure all content is properly laid out
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        
        final position = _scrollController.position;
        // Calculate the actual bottom position including any padding
        final target = position.maxScrollExtent + 
                      MediaQuery.of(context).padding.bottom +
                      kToolbarHeight; // Add extra space to ensure copy button is visible
        
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ).then((_) {
          // Add a small delay before re-enabling user scroll
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              _isUserScroll = true;
            }
          });
        });
      });
    });
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
                    gradient: context.read<ThemeProvider>().primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _toggleSidePanel,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: AnimatedRotation(
                          duration: const Duration(milliseconds: 175),
                          turns: _isSidePanelExpanded ? 0 : 0.5,
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

    if (chatProvider.isLoading) {
      _scrollToBottom();
    }

    return Scaffold(
      body: Stack(
        children: [
          // Main content
          Row(
            children: [
              SidePanel(isExpanded: _isSidePanelExpanded),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.background,
                        ),
                        child: messages.isEmpty
                            ? _buildEmptyState(theme)
                            : ListView.builder(
                                controller: _scrollController,
                                padding: EdgeInsets.only(
                                  top: kToolbarHeight * 1.2 + topPadding,
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
              ),
            ],
          ),
          // Header overlay
          _buildHeader(context, theme, chatProvider),
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