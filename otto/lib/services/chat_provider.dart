import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import '../config/env_config.dart';  // Add import for EnvConfig
import 'chat_service.dart';
import 'model_service.dart';
import 'dart:convert'; // Add this import for JSON handling
import 'dart:math' as math;

class ChatProvider with ChangeNotifier {
  final ChatService _chatService;
  final ModelService _modelService = ModelService();
  List<ChatMessage> _messages = [];
  List<LLMModel> _availableModels = [];
  LLMModel? _selectedModel;
  bool _isLoading = false;
  bool _isLoadingModels = false; // Separate flag for model loading
  String? _error;
  String _currentStreamedResponse = '';
  String? _currentConversationId;
  String? _currentUserId = 'default_user'; // In a real app, this would come from auth
  String? _currentUserName = 'default_user'; // Username for authentication
  static const String _selectedModelKey = 'selected_model';
  
  // Token and cost tracking
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;
  double _totalCost = 0.0;
  Map<String, LLMModel> _modelCache = {};

  ChatProvider({ChatService? chatService}) : _chatService = chatService ?? ChatService();

  List<ChatMessage> get messages => _messages;
  List<LLMModel> get availableModels => _availableModels;
  LLMModel? get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  bool get isLoadingModels => _isLoadingModels; // New getter for model loading state
  String? get error => _error;
  String? get conversationId => _currentConversationId;
  String get currentStreamedResponse => _currentStreamedResponse;
  
  // Token and cost tracking getters
  int get totalInputTokens => _totalInputTokens;
  int get totalOutputTokens => _totalOutputTokens;
  int get totalTokens => _totalInputTokens + _totalOutputTokens;
  double get totalCost => _totalCost;

  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  // Clear token and cost tracking
  void resetTokenAndCostTracking() {
    _totalInputTokens = 0;
    _totalOutputTokens = 0;
    _totalCost = 0.0;
    notifyListeners();
  }
  
  // Initialize chat by loading models and ensuring a conversation exists
  Future<void> initialize({bool syncModelsWithBackend = false}) async {
    try {
      _error = null;
      // First, set loading state
      _isLoadingModels = true; // Use the dedicated model loading flag
      notifyListeners();
      
      debugPrint('Initializing chat provider with backend sync: $syncModelsWithBackend');
      debugPrint('Using backend URL: ${EnvConfig.backendUrl}');
      
      // Then perform the actual initialization asynchronously
      await Future.microtask(() async {
        // If requested, sync models with backend first
        if (syncModelsWithBackend) {
          debugPrint('Syncing models with backend...');
          final userId = _ensureValidUserId();
          final username = _currentUserName ?? ''; // Get current username if available
          
          // Now fetching models from the /models/list endpoint
          try {
            debugPrint('Syncing models with userId: $userId and username: $username');
            final syncedModels = await _modelService.syncModels(
              userId: userId,
              username: username,
            );
            
            if (syncedModels.isNotEmpty) {
              debugPrint('Synced ${syncedModels.length} models from backend');
              _availableModels = syncedModels;
            } else {
              debugPrint('No models returned from backend, will attempt to load from backup');
            }
          } catch (e) {
            debugPrint('Error syncing models with backend: $e');
            // Continue with initialization even if sync fails
          }
        }
        
        // Load models from the backend with timeout to avoid hanging
        try {
          await loadModels().timeout(Duration(seconds: 10), onTimeout: () {
            debugPrint('Model loading timed out after 10 seconds');
            // Allow app to proceed with empty model list rather than hanging
            return;
          });
        } catch (e) {
          debugPrint('Error loading models, but continuing initialization: $e');
          // Continue initialization even if model loading fails
        }
        
        try {
          await _ensureConversationExists();
        } catch (e) {
          debugPrint('Error ensuring conversation exists: $e');
          // Continue without conversation if creation fails
        }
        
        _messages = []; // Clear messages for a fresh start
        
        // Always make sure to reset loading state regardless of success/failure
        _isLoadingModels = false; // Use the dedicated flag
        notifyListeners();
      });
    } catch (e) {
      // Make sure loading state is reset in case of any error
      _isLoadingModels = false; // Use the dedicated flag
      debugPrint('Error initializing chat: $e');
      _error = 'Failed to initialize chat: $e';
      notifyListeners();
    }
  }
  
  // Clear the current chat and start fresh
  Future<void> clearChat() async {
    _messages = [];
    resetTokenAndCostTracking();
    // Create a new conversation
    _currentConversationId = null;
    await _ensureConversationExists();
    notifyListeners();
  }
  
  // Initialize a new conversation if one doesn't exist
  Future<void> _ensureConversationExists() async {
    if (_currentConversationId == null) {
      try {
        // Use helper method to ensure valid user ID
        final userId = _ensureValidUserId();
        _currentConversationId = await _chatService.createConversation(userId);
        debugPrint('Created new conversation: $_currentConversationId');
      } catch (e) {
        debugPrint('Error creating conversation: $e');
        // Continue without server persistence if we couldn't create a conversation
      }
    }
  }

  // Fetch conversations for the current user
  Future<List<dynamic>> fetchConversations() async {
    if (_currentUserId == null) {
      throw Exception('No user ID set');
    }
    
    try {
      return await _chatService.getConversations(_currentUserId!);
    } catch (e) {
      debugPrint('Error fetching conversations: $e');
      _error = 'Failed to load conversations: $e';
      notifyListeners();
      return [];
    }
  }
  
  // Load a specific conversation
  Future<void> loadConversation(String conversationId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Get valid user ID
      final userId = _ensureValidUserId();
      
      // Get conversation details
      final conversation = await _chatService.getConversation(
        conversationId,
        userId: userId
      );
      _currentConversationId = conversationId;
      
      // Get messages separately using the new endpoint
      _messages = await _chatService.getConversationMessages(
        conversationId,
        userId: userId
      );
      
      // If conversation has token tracking data, update our local state
      if (conversation['token_window'] != null) {
        final tokenWindow = conversation['token_window'];
        _totalInputTokens = tokenWindow['input_tokens'] ?? 0;
        _totalOutputTokens = tokenWindow['output_tokens'] ?? 0;
        _totalCost = (tokenWindow['total_cost'] ?? 0.0).toDouble();
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load conversation: $e';
      notifyListeners();
    }
  }

  void _provideFallbackModels() {
    // Note: As per user instruction, we don't want to create hardcoded models
    // Instead we'll just log an error and leave the models empty
    
    debugPrint('ERROR: Could not load models from server');
    debugPrint('No fallback models will be used, as per requirement to always use backend models');
    
    // Clear any existing models to ensure we're not using outdated data
    _availableModels = [];
    
    // Set error state to inform the user
    _error = 'Could not connect to model server. Please check your connection and try again.';
    
    // Don't set a fallback model - we must get it from the backend
    _selectedModel = null;
    
    // No notifyListeners here - caller will handle notification
  }
  
  // Load available models
  Future<void> loadModels() async {
    // Set a flag to track if we got any models
    bool gotModels = false;
    
    try {
      debugPrint('Loading models from backend...');
      
      // Try to restore previously selected model from preferences first
      final prefs = await SharedPreferences.getInstance();
      final savedModelId = prefs.getString(_selectedModelKey);
      final savedModelJson = prefs.getString('${_selectedModelKey}_json');
      
      debugPrint('Saved model ID from preferences: $savedModelId');
      
      // Try to get models from the backend
      debugPrint('Fetching models from backend...');
      try {
        _availableModels = await _modelService.getModels().timeout(
          Duration(seconds: 8),
          onTimeout: () {
            debugPrint('Model fetching timed out after 8 seconds');
            return [];
          }
        );
        debugPrint('Fetched ${_availableModels.length} models from backend');
      } catch (e) {
        debugPrint('Error fetching models: $e');
        _availableModels = [];
      }
      
      // If we got models, find the previously selected one or use the first one
      if (_availableModels.isNotEmpty) {
        gotModels = true;
        // If we previously had a saved model, try to restore it
        if (savedModelId != null) {
          // Try to find the previously selected model in the new list
          final modelIndex = _availableModels.indexWhere(
            (model) => model.modelId == savedModelId
          );
          
          if (modelIndex >= 0) {
            _selectedModel = _availableModels[modelIndex];
            debugPrint('Found saved model in backend models: ${_selectedModel!.displayName}');
          } else {
            // If we couldn't find the saved model, use the first one from the backend
            _selectedModel = _availableModels.first;
            debugPrint('Saved model not found in backend, using first model: ${_selectedModel!.displayName}');
          }
        } else {
          // No saved model, use the first available from the backend
          _selectedModel = _availableModels.first;
          debugPrint('No saved model, using first model from backend: ${_selectedModel!.displayName}');
        }
      } else {
        // No models returned from backend, try direct sync once as a last resort
        debugPrint('No models returned from backend, trying direct sync with /models/list endpoint...');
        
        try {
          final syncedModels = await _modelService.syncModels(
            userId: _ensureValidUserId()
          ).timeout(Duration(seconds: 5), onTimeout: () {
            debugPrint('Model sync timed out after 5 seconds');
            return [];
          });
          
          if (syncedModels.isNotEmpty) {
            gotModels = true;
            _availableModels = syncedModels;
            debugPrint('Successfully fetched ${syncedModels.length} models from /models/list endpoint');
            
            // Use the first model from synced models
            _selectedModel = _availableModels.first;
            debugPrint('Using model from direct fetch: ${_selectedModel!.displayName}');
          } else {
            // Try to use saved model from preferences as a last resort
            if (savedModelJson != null) {
              try {
                final modelData = jsonDecode(savedModelJson);
                _selectedModel = LLMModel.fromJson(modelData);
                _availableModels = [_selectedModel!];
                gotModels = true;
                debugPrint('Using cached model from preferences: ${_selectedModel!.displayName}');
              } catch (e) {
                debugPrint('Error parsing saved model JSON: $e');
              }
            }
            
            if (!gotModels) {
              debugPrint('No models available from the backend - cannot continue');
              _error = 'Could not load models from backend. Please check your connection and try again.';
            }
          }
        } catch (e) {
          debugPrint('Error syncing models: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading models from backend: $e');
      _error = 'Error loading models: $e';
    }
    
    // If we couldn't get any models, create a fallback model so the app doesn't hang
    if (!gotModels && _selectedModel == null) {
      debugPrint('No models available from the backend - cannot continue');
      _error = 'Could not load models from backend. Please check your connection and try again.';
      
      // IMPORTANT: As per requirement, we do NOT create a fallback model
      // All models must come from MongoDB backend
      debugPrint('No fallback models will be used, as per requirement to always use backend models');
      
      // Clear any existing models to ensure we're not using outdated data
      _availableModels = [];
      
      // Don't set a fallback model - we must get it from the backend
      _selectedModel = null;
    }
    
    // No notifyListeners here - caller will handle notification
  }

  Future<void> setSelectedModel(LLMModel model) async {
    _selectedModel = model;
    notifyListeners();
    
    // Persist selection to preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedModelKey, model.modelId);
      
      // Also save the full model JSON for complete restoration
      final modelJson = jsonEncode(model.toJson());
      await prefs.setString('${_selectedModelKey}_json', modelJson);
    } catch (e) {
      debugPrint('Error saving model preference: $e');
    }
  }

  // Get model metadata for token tracking
  Future<LLMModel?> _getModelMetadata(String modelId) async {
    if (_modelCache.containsKey(modelId)) {
      return _modelCache[modelId];
    }
    
    try {
      final model = await _modelService.getModel(modelId);
      _modelCache[modelId] = model;
      return model;
    } catch (e) {
      debugPrint('Error fetching model metadata: $e');
      return null;
    }
  }
  
  // Estimate token count using a simple approximation
  int _estimateTokenCount(String text) {
    // Simple approximation: about 4 characters per token for English
    return (text.length / 4).ceil();
  }
  
  // Update token usage without requiring a model
  void _updateTokenUsageWithFallback(ChatMessage message, {bool isInput = true}) {
    // Estimate token count if not provided
    int tokens = message.tokenCount ?? _estimateTokenCount(message.content);
    
    // Update token counts
    if (isInput) {
      _totalInputTokens += tokens;
    } else {
      _totalOutputTokens += tokens;
    }
    
    // Update cost if we have a selected model, otherwise just track tokens
    if (_selectedModel != null) {
      double cost;
      if (isInput) {
        cost = _selectedModel!.calculateInputCost(tokens);
      } else {
        cost = _selectedModel!.calculateOutputCost(tokens);
      }
      _totalCost += cost;
    }
    
    notifyListeners();
  }

  // Original _updateTokenUsage method now uses the new fallback method
  void _updateTokenUsage(ChatMessage message, {bool isInput = true}) {
    _updateTokenUsageWithFallback(message, isInput: isInput);
  }

  Future<void> addUserMessage(String content) async {
    if (content.trim().isEmpty) return;
    
    // Ensure we have a conversation
    await _ensureConversationExists();
    
    final message = ChatMessage(
      role: 'user',
      content: content,
    );
    
    // Add to local state
    _messages.add(message);
    notifyListeners();
    
    // Update token usage
    _updateTokenUsage(message, isInput: true);
    
    // Get valid user ID
    final userId = _ensureValidUserId();
    
    // Persist to backend
    try {
      await _chatService.addMessageToConversation(
        _currentConversationId!, 
        message,
        userId: userId
      );
      debugPrint('Successfully persisted user message to backend');
    } catch (e) {
      debugPrint('Error persisting user message: $e');
      // Continue anyway, as the message is already in local state
    }
    
    // Now send the message to the AI
    await sendMessage(content);
  }
  
  Future<void> sendMessage(String content) async {
    // Store the previous error to restore it if needed
    final previousError = _error;
    
    if (_selectedModel == null) {
      _error = 'Please select a model first';
      notifyListeners();
      return;
    }

    if (content.trim().isEmpty) {
      return;
    }
    
    // Make sure we have a valid model before sending the message
    if (_availableModels.isEmpty) {
      debugPrint('No models available, attempting to load models first');
      _isLoadingModels = true; // Use the dedicated model loading flag instead of _isLoading
      notifyListeners();
      
      try {
        await loadModels().timeout(Duration(seconds: 5), onTimeout: () {
          debugPrint('Model loading timed out after 5 seconds');
          return;
        });
      } catch (e) {
        debugPrint('Error loading models: $e');
      } finally {
        _isLoadingModels = false; // Use the dedicated model loading flag
        notifyListeners();
      }
      
      if (_availableModels.isEmpty || _selectedModel == null) {
        _error = 'Could not load models. Please check your connection and try again.';
        notifyListeners();
        return;
      }
    }
    
    // DEBUG: Print current messages state
    debugPrint('Current messages before processing: ${_messages.length}');
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      debugPrint(' - Message ${i+1}: ${msg.role}: ${msg.content.substring(0, math.min(20, msg.content.length))}...');
    }

    // Create a temporary assistant message for streaming
    var tempMessage = ChatMessage(
      role: 'assistant',
      content: '',
      model: _selectedModel,
    );
    
    // Make a copy of the messages BEFORE adding the temporary message
    // This ensures we have the user message but not the temporary assistant message
    final messageHistory = List<ChatMessage>.from(_messages);
    
    // If messageHistory is empty but content is provided, this is likely the first message
    // In this case, we need to create a user message and add it to the history
    if (messageHistory.isEmpty && content.isNotEmpty) {
      debugPrint('No messages in history but content provided. Creating user message for first interaction.');
      final initialUserMessage = ChatMessage(
        role: 'user',
        content: content,
      );
      
      // Add to both message history (for LLM context) and _messages (for UI display)
      messageHistory.add(initialUserMessage);
      
      // Only add to _messages if it's not already there
      if (_messages.isEmpty) {
        _messages.add(initialUserMessage);
        notifyListeners();
      }
    }
    
    // Now add the temporary message to _messages for UI updates
    _messages.add(tempMessage);
    
    _isLoading = true;
    _currentStreamedResponse = '';
    _error = null;
    notifyListeners();

    // Use a timeout for the entire operation to prevent hanging
    try {
      await Future.microtask(() async {
        StringBuffer accumulatedContent = StringBuffer();
        
        // Get valid user ID
        final userId = _ensureValidUserId();
        
        // Sort by timestamp to maintain proper conversation context
        // This ensures the LLM gets messages in chronological order
        messageHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        
        // Log the conversation context for debugging
        debugPrint('Sending ${messageHistory.length} messages to LLM in conversation $_currentConversationId');
        for (int i = 0; i < messageHistory.length; i++) {
          final msg = messageHistory[i];
          debugPrint('Message ${i+1}: ${msg.role}: ${msg.content.length > 30 ? '${msg.content.substring(0, 30)}...' : msg.content}');
        }
        
        // Verify we're not sending an empty list
        if (messageHistory.isEmpty) {
          debugPrint('ERROR: No messages to send to LLM. This should not happen.');
          _error = 'Error: No messages to send to the model.';
          _isLoading = false;
          notifyListeners();
          return;
        }
        
        // Send the message history to the LLM (without the temporary message)
        try {
          await for (final chunk in _chatService.streamChat(
            _selectedModel!.modelId,
            messageHistory, // Already excludes the temporary message
            userId: userId
          )) {
            // Add the chunk to accumulated content
            accumulatedContent.write(chunk);
            _currentStreamedResponse = accumulatedContent.toString();
            
            // Update the message with the accumulated content
            final updatedMessage = ChatMessage(
              role: 'assistant',
              content: _currentStreamedResponse,
              id: tempMessage.id,
              timestamp: tempMessage.timestamp,
              createdAt: tempMessage.createdAt,
              model: _selectedModel,
            );
            
            // Update the message in the list and notify listeners immediately
            _messages[_messages.length - 1] = updatedMessage;
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Error during streaming: $e');
          // Continue with processing to ensure we don't get stuck
          _error = 'Error receiving response: $e';
        }
        
        // If we got any response, finalize it
        if (accumulatedContent.isNotEmpty) {
          // Ensure final state is reflected
          final finalMessage = ChatMessage(
            role: 'assistant',
            content: _currentStreamedResponse,
            id: tempMessage.id,
            timestamp: tempMessage.timestamp,
            createdAt: DateTime.now(),  // Update with final timestamp
            model: _selectedModel,
          );
          _messages[_messages.length - 1] = finalMessage;
          
          // Track token usage for the complete response
          _updateTokenUsage(finalMessage, isInput: false);
          
          // Persist the assistant's message to backend (reuse the userId from above)
          try {
            await _chatService.addMessageToConversation(
              _currentConversationId!, 
              finalMessage,
              userId: userId
            );
            debugPrint('Successfully persisted assistant message to backend');
          } catch (e) {
            debugPrint('Warning: Failed to persist assistant message to backend: $e');
            // Continue without server persistence if we couldn't save the message
          }
          
          // Update conversation title if this is the second message or later
          if (_messages.length >= 3 && _currentConversationId != null) {
            await _updateConversationTitle().timeout(Duration(seconds: 5), onTimeout: () {
              debugPrint('Update conversation title timed out');
              return;
            });
          }
        } else if (_currentStreamedResponse.isEmpty) {
          // If we didn't get any response, update the message to indicate error
          final errorMessage = ChatMessage(
            role: 'assistant',
            content: 'Sorry, I couldn\'t generate a response. Please try again.',
            id: tempMessage.id,
            timestamp: tempMessage.timestamp,
            createdAt: DateTime.now(),
            model: _selectedModel,
          );
          _messages[_messages.length - 1] = errorMessage;
          _error = 'No response received from the model.';
        }
      }).timeout(Duration(seconds: 60), onTimeout: () {
        debugPrint('Send message operation timed out after 60 seconds');
        _error = 'Operation timed out. Please try again.';
        
        // Update the last message to show timeout
        if (_messages.isNotEmpty && _messages.last.role == 'assistant' && _messages.last.content.isEmpty) {
          final timeoutMessage = ChatMessage(
            role: 'assistant',
            content: 'Sorry, the response timed out. Please try again later.',
            id: _messages.last.id,
            timestamp: _messages.last.timestamp,
            createdAt: DateTime.now(),
            model: _selectedModel,
          );
          _messages[_messages.length - 1] = timeoutMessage;
        }
      });
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      debugPrint('Chat error: $e');
    } finally {
      // Ensure loading state is always turned off when done
      _isLoading = false;
      
      // If _error is null but we had a previous error about models, restore it
      // This ensures the model error message remains visible
      if (_error == null && previousError != null && previousError.contains('models')) {
        _error = previousError;
      }
      
      notifyListeners();
    }
  }
  
  // Update the conversation title
  Future<void> _updateConversationTitle({bool forceUpdate = false}) async {
    if (_currentConversationId == null) return;
    
    // Get valid user ID
    final userId = _ensureValidUserId();
    
    try {
      await _chatService.updateConversationTitle(
        _currentConversationId!,
        forceUpdate: forceUpdate,
        userId: userId
      );
    } catch (e) {
      debugPrint('Error updating conversation title: $e');
      // Not critical, so we don't set an error state
    }
  }
  
  // Sync models with backend
  Future<void> syncModels() async {
    try {
      _isLoadingModels = true;
      notifyListeners();
      
      final updatedModels = await _modelService.syncModels(
        userId: _currentUserId,
        username: _currentUserName,
      );
      
      if (updatedModels.isNotEmpty) {
        _availableModels = updatedModels;
        
        // Reselect current model if we had one previously
        if (_selectedModel != null) {
          final String currentModelId = _selectedModel!.modelId;
          
          // Try to find the same model in the updated list
          final modelIndex = _availableModels.indexWhere(
            (model) => model.modelId == currentModelId
          );
          
          if (modelIndex >= 0) {
            // Found the same model in the updated list
            setSelectedModel(_availableModels[modelIndex]);
          } else if (_availableModels.isNotEmpty) {
            // Couldn't find same model, use the first available
            setSelectedModel(_availableModels.first);
          }
        } else if (_availableModels.isNotEmpty) {
          // No previously selected model, use the first one
          setSelectedModel(_availableModels.first);
        }
      }
    } catch (e) {
      debugPrint('Error syncing models: $e');
      _error = 'Failed to sync models. Please try again.';
    } finally {
      _isLoadingModels = false;
      notifyListeners();
    }
  }
  
  // Set user information
  void setUserId(String userId, {String? username}) {
    _currentUserId = userId;
    // Set the username if provided, otherwise use userId as username
    _currentUserName = username ?? userId;
    debugPrint('Set user ID: $userId and username: $_currentUserName');
    
    // Also set the username in ChatService for authentication
    _chatService.setCurrentUsername(_currentUserName ?? userId);
    
    // Reset conversation ID so a new one will be created
    _currentConversationId = null;
  }
  
  // Create a new conversation
  Future<void> createNewConversation() async {
    _messages = [];
    _currentConversationId = null;
    notifyListeners();
    
    // A new conversation will be created when the first message is sent
  }

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }

  // Helper method to ensure we have a valid user ID
  String _ensureValidUserId() {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      debugPrint('Warning: No user ID set, using default_user');
      _currentUserId = 'default_user';
    }
    return _currentUserId!;
  }
} 