import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import '../config/env_config.dart';  // Add import for EnvConfig
import 'chat_service.dart';
import 'model_service.dart';
import 'dart:convert'; // Add this import for JSON handling
import 'dart:math' show min; // Import min function
import 'dart:math' as math;
import 'dart:async';

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
  String? _currentUserId;
  String? _currentUserName;
  static const String _selectedModelKey = 'selected_model';
  
  // Token and cost tracking
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;
  double _totalCost = 0.0;
  Map<String, LLMModel> _modelCache = {};

  // Stream communication
  StreamController<String>? _streamController;
  StreamSubscription<String>? _streamSubscription;

  ChatProvider({ChatService? chatService}) : _chatService = chatService ?? ChatService();

  List<ChatMessage> get messages => _messages;
  List<LLMModel> get availableModels => _availableModels;
  LLMModel? get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  bool get isLoadingModels => _isLoadingModels; // New getter for model loading state
  String? get error => _error;
  String? get conversationId => _currentConversationId;
  String? get currentUserId => _currentUserId; // Add getter
  String? get currentUserName => _currentUserName; // Add getter
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
  
  // Set error message and notify listeners
  void setError(String errorMessage) {
    _error = errorMessage;
    _isLoading = false;
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
      
      debugPrint('Initializing chat provider');
      debugPrint('Using backend URL: ${EnvConfig.backendUrl}');
      
      // Then perform the actual initialization asynchronously
      await Future.microtask(() async {
        // Load models from backend
        try {
          debugPrint('Fetching models from backend...');
          // Always use the /models/list endpoint
          final models = await _modelService.getModels();
          
          if (models.isNotEmpty) {
            debugPrint('Fetched ${models.length} models from backend');
            _availableModels = models;
          } else {
            debugPrint('No models returned from backend, retrying once...');
            // Try again once more after a short delay
            await Future.delayed(Duration(milliseconds: 500));
            final retryModels = await _modelService.getModels();
            
            if (retryModels.isNotEmpty) {
              debugPrint('Fetched ${retryModels.length} models on retry');
              _availableModels = retryModels;
            } else {
              debugPrint('Still no models after retry');
            }
          }
        } catch (e) {
          debugPrint('Error fetching models from backend: $e');
          // Continue with initialization even if fetch fails
        }
        
        // Ensure we have a conversation
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
    _error = null; // Explicitly clear any error messages
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
        debugPrint('Creating new conversation for user: $userId');
        
        // Create a new conversation and wait for the result
        final conversationId = await _chatService.createConversation(userId);
        
        if (conversationId == null || conversationId.isEmpty) {
          throw Exception('Backend returned empty conversation ID');
        }
        
        _currentConversationId = conversationId;
        debugPrint('Created new conversation with ID: $_currentConversationId');
      } catch (e) {
        debugPrint('Error creating conversation: $e');
        // Rethrow the exception to be handled by the caller
        throw Exception('Failed to create conversation: $e');
      }
    } else {
      debugPrint('Using existing conversation: $_currentConversationId');
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
      
      // Try to get models from the backend using only the /models/list endpoint
      debugPrint('Fetching models from /models/list endpoint...');
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
        // No models returned, try one more time after a short delay
        debugPrint('No models returned, retrying fetch from /models/list endpoint...');
        
        await Future.delayed(Duration(milliseconds: 500));
        
        try {
          final modelsList = await _modelService.getModels().timeout(Duration(seconds: 5), onTimeout: () {
            debugPrint('Model fetch timed out after 5 seconds');
            return [];
          });
          
          if (modelsList.isNotEmpty) {
            gotModels = true;
            _availableModels = modelsList;
            debugPrint('Successfully fetched ${modelsList.length} models on retry');
            
            // Use the first model from fetched models
            _selectedModel = _availableModels.first;
            debugPrint('Using model from backend: ${_selectedModel!.displayName}');
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
          debugPrint('Error fetching models on retry: $e');
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
    
    debugPrint('Adding user message: "${content.substring(0, min(20, content.length))}..." to conversation');
    
    // Add to local state
    _messages.add(message);
    notifyListeners();
    
    // Update token usage
    _updateTokenUsage(message, isInput: true);
    
    debugPrint('Current message count before sending to API: ${_messages.length}');
    
    // Now send the message to the AI
    await sendMessage(content);
  }
  
  Future<void> sendMessage(String content, {
    bool useStream = true,
    double? temperature,
    int? maxTokens,
  }) async {
    try {
      // Clear any previous error messages when sending a new message
      _error = null;
      
      // Validate that we have everything needed to send a message
      if (content.trim().isEmpty) {
        debugPrint('Cannot send empty message');
        return;
      }
      
      if (_selectedModel == null) {
        debugPrint('No model selected');
        _error = 'Please select a model before sending a message';
        notifyListeners();
        return;
      }
      
      // Check if we have an active conversation ID
      await _ensureConversationExists();
      if (_currentConversationId == null) {
        debugPrint('Failed to get a valid conversation ID');
        _error = 'Could not create a conversation. Please try again.';
        notifyListeners();
        return;
      }
      
      // Get a copy of message history for the API request
      final apiMessageHistory = List<ChatMessage>.from(_messages);
      
      // Log the message count and roles
      debugPrint('Message count being sent to API: ${apiMessageHistory.length}');
      for (int i = 0; i < apiMessageHistory.length; i++) {
        final msg = apiMessageHistory[i];
        debugPrint('Message $i - Role: ${msg.role}, Content: "${msg.content.substring(0, min(20, msg.content.length))}..."');
      }
      
      // Validate we have at least one message to send
      if (apiMessageHistory.isEmpty) {
        debugPrint('ERROR: No messages to send to API');
        _error = 'No messages to send. Please try again.';
        notifyListeners();
        return;
      }
      
      // For UI purposes, add a temporary message that won't be sent to the API
      final tempAssistantMessage = ChatMessage(
        role: 'assistant',
        content: '',
        model: _selectedModel,
      );
      _messages.add(tempAssistantMessage);
      
      // Important: Reset the streamed response buffer for the new message
      _currentStreamedResponse = '';
      
      notifyListeners(); // Notify UI to show the placeholder
      
      // Debug: print messages state for debugging (just roles and shortened content)
      debugPrint('Sending messages to API:');
      for (final msg in apiMessageHistory) {
        final contentPreview = msg.content.length > 20 
            ? '${msg.content.substring(0, 20)}...' 
            : msg.content;
        debugPrint('  ${msg.role}: $contentPreview');
      }
      
      // Make sure any previous stream subscription is closed
      if (_streamSubscription != null) {
        await _streamSubscription!.cancel();
        _streamSubscription = null;
      }
      
      // Create a stream controller to handle the streaming response
      _streamController = StreamController<String>();
      
      try {
        // Use stream to get incremental responses from the AI
        debugPrint('Starting stream chat request with conversation ID: $_currentConversationId');
        if (maxTokens != null) {
          debugPrint('Using max_input_tokens: $maxTokens');
        }
        
        // Ensure we use a proper model identifier, not the hash
        // Get the display name or a fallback model name (like 'gpt-3.5-turbo')
        final String modelForApi = _selectedModel!.displayName.isNotEmpty 
            ? _selectedModel!.displayName 
            : _selectedModel!.modelId.contains('-') 
                ? _selectedModel!.modelId 
                : 'gpt-3.5-turbo'; // Fallback to a safe default
        
        debugPrint('Using model for API request: $modelForApi');
        
        // Print selectedModel details for debugging
        debugPrint('Selected model details:');
        debugPrint('  modelId: ${_selectedModel!.modelId}');
        debugPrint('  displayName: ${_selectedModel!.displayName}');
        debugPrint('  provider: ${_selectedModel!.provider}');
        
        final stream = _chatService.streamChat(
          modelForApi,
          apiMessageHistory, // Use the list without the empty assistant message
          userId: _ensureValidUserId(),
          conversationId: _currentConversationId,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        
        _streamSubscription = stream.listen(
          (chunk) {
            // Special handling for error messages marked with *ERROR_MESSAGE* prefix
            if (chunk.startsWith("*ERROR_MESSAGE*")) {
              // Extract the actual error message
              final errorMessage = chunk.substring("*ERROR_MESSAGE*".length);
              
              // Set the error state but don't add it to the message history
              setError(errorMessage);
              
              // Remove the last (empty) assistant message since we got an error
              if (_messages.isNotEmpty && _messages.last.role == 'assistant' && _messages.last.content.isEmpty) {
                _messages.removeLast();
                notifyListeners();
              }
              
              // Instead of break, just return early from this callback
              return;
            }
            
            // Process normal (non-error) chunks
            _currentStreamedResponse += chunk;
            _streamController?.add(chunk);
            
            // Update last message content in state
            if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
              // Instead of modifying the existing message's content, create a new message with the streamed content
              _messages[_messages.length - 1] = ChatMessage(
                id: _messages.last.id,
                role: 'assistant',
                content: _currentStreamedResponse, // Use only the streamed content, not existing content
                model: _selectedModel,
                createdAt: _messages.last.createdAt,
                timestamp: _messages.last.timestamp, // Preserve the timestamp
              );
              notifyListeners();
            }
          },
          onDone: () {
            // Update token usage for the assistant response if we have messages
            if (_messages.isNotEmpty) {
              _updateTokenUsage(_messages.last, isInput: false);
            }
            
            // Check if we have any content in the last message
            if (_currentStreamedResponse.isEmpty) {
              // If we have no content, we might have had a stream error. Log it.
              debugPrint('Stream completed with empty response. This might indicate an error.');
            } else {
              // If we have content, consider it a success even if there was an error
              debugPrint('Stream completed with ${_currentStreamedResponse.length} characters.');
              
              // Set the final message content when streaming is done
              if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
                // Create a new message with the final content
                _messages[_messages.length - 1] = ChatMessage(
                  id: _messages.last.id,
                  role: 'assistant',
                  content: _currentStreamedResponse,
                  model: _selectedModel,
                  createdAt: _messages.last.createdAt,
                  timestamp: _messages.last.timestamp,
                );
              }
              
              // Clear any error that might have been set
              _error = null;
            }
            
            // Notify UI of completion
            _isLoading = false;
            notifyListeners();
            
            // Close the stream controller
            if (_streamController != null && !_streamController!.isClosed) {
              _streamController!.close();
            }
            
            debugPrint('Stream completed');
            if (_messages.isNotEmpty) {
              debugPrint('Final message content length: ${_messages.last.content.length}');
            }
          },
          onError: (e) {
            debugPrint('Stream error: $e');
            
            // Only set error state if we don't have any content in the last message
            if (_currentStreamedResponse.isEmpty) {
              setError('Error during streaming: $e');
            } else {
              // If we have partial content, just log the error but don't show it to the user
              debugPrint('Stream error occurred, but we have partial content (${_currentStreamedResponse.length} chars). Not showing error to user.');
              // Clear any error state
              _error = null;
              _isLoading = false;
              notifyListeners();
            }
            
            if (_streamController != null && !_streamController!.isClosed) {
              _streamController!.addError(e);
              _streamController!.close();
            }
          },
          cancelOnError: true,
        );
      } catch (e) {
        debugPrint('Error setting up stream: $e');
        setError('Error setting up message stream: $e');
      }
    } catch (e) {
      debugPrint('Error in sendMessage: $e');
      setError('Error sending message: $e');
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
  
  // Refresh models from the server (renamed from syncModels)
  Future<void> refreshModels() async {
    try {
      _isLoadingModels = true;
      notifyListeners();
      
      // Call the syncModels endpoint instead of just getModels
      debugPrint('Calling syncModels from ChatProvider for user: $_currentUserId, username: $_currentUserName');
      final models = await _modelService.syncModels(
        userId: _currentUserId, 
        username: _currentUserName
      );
      
      if (models.isNotEmpty) {
        _availableModels = models;
        _updateSelectedModelAfterRefresh();
      } else {
        _error = 'No models returned from server. Please try again.';
      }
    } catch (e) {
      debugPrint('Error refreshing models: $e');
      _error = 'Failed to refresh models. Please try again.';
    } finally {
      _isLoadingModels = false;
      notifyListeners();
    }
  }
  
  // Helper method to update the selected model after refresh (renamed from _updateSelectedModelAfterSync)
  void _updateSelectedModelAfterRefresh() {
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
  
  // Set user information
  void setUserId(String userId, {String? username}) {
    _currentUserId = userId;
    _currentUserName = username ?? userId;
    
    // Update chat service with username for authentication
    _chatService.setCurrentUsername(_currentUserName!);
    
    debugPrint('Set user ID: $userId and username: ${username ?? userId}');
    
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
      debugPrint('Warning: No user ID set, using generated ObjectId');
      _currentUserId = defaultObjectId;
    }
    return _currentUserId!;
  }

  // Helper method to finalize an assistant message after streaming completes
  void _finalizeAssistantMessage(String content) {
    // Only proceed if there's actual content
    if (content.isEmpty) {
      debugPrint('Warning: Attempted to finalize an empty assistant message');
      return;
    }
    
    // Find the last assistant message
    final lastIndex = _messages.length - 1;
    if (lastIndex >= 0 && _messages[lastIndex].role == 'assistant') {
      // Create the final message
      final finalMessage = ChatMessage(
        id: _messages[lastIndex].id,
        role: 'assistant',
        content: content,
        model: _selectedModel,
        createdAt: DateTime.now(),  // Update with final timestamp
        timestamp: _messages[lastIndex].timestamp,
      );
      
      // Replace the temporary message
      _messages[lastIndex] = finalMessage;
      
      // Track token usage
      _updateTokenUsageWithFallback(finalMessage, isInput: false);
      
      // Update conversation title if needed
      if (_messages.length >= 3 && _currentConversationId != null) {
        _updateConversationTitle();
      }
    }
    
    // Clear loading state and current streamed response
    _isLoading = false;
    _currentStreamedResponse = '';
    notifyListeners();
  }

  // Explicitly create a new conversation before sending any messages
  // This can be called when initializing the chat screen to avoid race conditions
  Future<bool> prepareConversation() async {
    try {
      debugPrint('Explicitly preparing conversation before sending messages');
      await _ensureConversationExists();
      
      if (_currentConversationId == null || _currentConversationId!.isEmpty) {
        debugPrint('ERROR: Failed to create conversation during preparation');
        _error = 'Failed to prepare conversation. Please try again.';
        notifyListeners();
        return false;
      }
      
      debugPrint('Successfully prepared conversation: $_currentConversationId');
      return true;
    } catch (e) {
      debugPrint('Error preparing conversation: $e');
      _error = 'Failed to prepare conversation: $e';
      notifyListeners();
      return false;
    }
  }
}
