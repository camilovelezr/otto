import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import '../models/conversation_summary.dart'; // Import the new model
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
  String? _currentUserName; // Keep for potential internal use/logging
  String? _currentDisplayName; // Add field for display name
  static const String _selectedModelKey = 'selected_model';

  // --- New State for Conversation List ---
  List<ConversationSummary> _conversationList = [];
  bool _isLoadingConversations = false;
  Completer<void>? _userIdSetupCompleter; // Completer for setUserId initialization
  // --- End New State ---

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
  String? get currentUserName => _currentUserName; // Keep getter
  String? get currentDisplayName => _currentDisplayName; // Add getter for display name
  String get currentStreamedResponse => _currentStreamedResponse;

  // --- New Getters ---
  List<ConversationSummary> get conversationList => _conversationList;
  bool get isLoadingConversations => _isLoadingConversations;
  // --- End New Getters ---

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
    _isLoading = false; // Also stop general loading on error
    _isLoadingConversations = false; // Stop conversation loading on error
    notifyListeners();
  }
  
  // Clear token and cost tracking
  void resetTokenAndCostTracking() {
    _totalInputTokens = 0;
    _totalOutputTokens = 0;
    _totalCost = 0.0;
    // No need to notify here, usually called within other methods that notify
  }
  
  // Initialize chat provider - primarily loads models now
  Future<void> initialize({bool syncModelsWithBackend = false}) async {
    try {
      _error = null;
      _isLoadingModels = true;
      notifyListeners();
      
      debugPrint('Initializing chat provider');
      debugPrint('Using backend URL: ${EnvConfig.backendUrl}');
      
      await _loadModelsInternal(); // Load models

    } catch (e) {
      debugPrint('Error initializing chat provider: $e');
      _error = 'Failed to initialize chat: $e';
    } finally {
       _isLoadingModels = false; // Ensure loading state is always reset
       notifyListeners();
    }
  }

  // Internal helper for loading models and applying selection logic
  Future<void> _loadModelsInternal() async {
    LLMModel? newlySelectedModel;
    bool usedFallback = false;

    try {
      debugPrint('Loading models internally...');
      final prefs = await SharedPreferences.getInstance();
      final savedModelId = prefs.getString(_selectedModelKey);
      final savedModelJson = prefs.getString('${_selectedModelKey}_json');
      debugPrint('Saved model ID from prefs: $savedModelId');

      // Fetch models from backend
      try {
        _availableModels = await _modelService.getModels().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint('Model fetching timed out');
            return [];
          }
        );
        debugPrint('Fetched ${_availableModels.length} models from backend.');
      } catch (e) {
        debugPrint('Error fetching models from backend: $e');
        _availableModels = []; // Ensure list is empty on fetch error
      }

      if (_availableModels.isNotEmpty) {
        // 1. Try saved model
        if (savedModelId != null) {
          final savedIndex = _availableModels.indexWhere((m) => m.modelId == savedModelId);
          if (savedIndex != -1) {
            newlySelectedModel = _availableModels[savedIndex];
            debugPrint('Restored saved model: ${newlySelectedModel.displayName}');
          } else {
             debugPrint('Saved model ID "$savedModelId" not found in fetched list.');
          }
        }

        // 2. Try Groq fallback (if saved model not found)
        if (newlySelectedModel == null) {
          final groqIndex = _availableModels.indexWhere((m) => m.provider.toLowerCase() == 'groq');
          if (groqIndex != -1) {
            newlySelectedModel = _availableModels[groqIndex];
            usedFallback = true;
            debugPrint('Using Groq fallback model: ${newlySelectedModel.displayName}');
          } else {
             debugPrint('No Groq model found in fetched list.');
          }
        }

        // 3. Try first available fallback (if saved and Groq not found)
        if (newlySelectedModel == null) {
          newlySelectedModel = _availableModels.first;
          usedFallback = true;
          debugPrint('Using first available fallback model: ${newlySelectedModel.displayName}');
        }

      } else {
        // Fetch failed, try restoring from full JSON cache
        debugPrint('Backend fetch yielded no models. Trying cache...');
        if (savedModelJson != null) {
          try {
            final modelData = jsonDecode(savedModelJson);
            newlySelectedModel = LLMModel.fromJson(modelData);
            _availableModels = [newlySelectedModel]; // Populate available models with the cached one
            debugPrint('Restored model from JSON cache: ${newlySelectedModel.displayName}');
          } catch (e) {
            debugPrint('Error parsing cached model JSON: $e');
            _availableModels = []; // Ensure list is empty if cache parse fails
          }
        } else {
           debugPrint('No cached model JSON found.');
           _availableModels = []; // Ensure list is empty
        }
      }

      // Set the selected model
      _selectedModel = newlySelectedModel;

      // If we used a fallback (Groq or first), save it as the new default
      if (usedFallback && _selectedModel != null) {
        debugPrint('Saving fallback model selection to prefs: ${_selectedModel!.displayName}');
        await setSelectedModel(_selectedModel!); // Save the new default
      }

      if (_selectedModel == null) {
         debugPrint('Could not select any model.');
         // Error state will be handled by initialize if needed
      }

    } catch (e) {
      debugPrint('Error during internal model loading: $e');
      _error = 'Failed to load models: $e'; // Set error state here
      _availableModels = []; // Ensure list is empty on error
      _selectedModel = null; // Ensure no model is selected on error
    }
  }
  
  // Clear the current chat and start fresh (used by UI action)
  Future<void> clearChat() async {
    // Call the new UI-facing method to handle state updates correctly
    await requestNewConversation();
  }
  
  // Initialize a new conversation if one doesn't exist (internal use)
  Future<void> _ensureConversationExists() async {
    if (_currentConversationId == null) {
      try {
        debugPrint('Ensuring conversation exists...');
        final conversationId = await _chatService.createConversation(); // Pass userId REMOVED
        if (conversationId == null || conversationId.isEmpty) {
          throw Exception('Backend returned empty conversation ID');
        }
        _currentConversationId = conversationId;
        debugPrint('Ensured conversation exists with ID: $_currentConversationId');
      } catch (e) {
        debugPrint('Error ensuring conversation exists: $e');
        throw Exception('Failed to create conversation: $e'); // Rethrow
      }
    } else {
      debugPrint('Conversation already exists: $_currentConversationId');
    }
  }

  // --- Internal Fetch Conversation List ---
  // Returns the fetched list, or null on error/no user. Does NOT manage state.
  Future<List<ConversationSummary>?> _fetchConversationListInternal() async {
    if (_currentUserId == null) {
      debugPrint('Cannot fetch conversation list: No user ID set');
      return null;
    }

    try {
      final conversationsData = await _chatService.getConversations(_currentUserId!);
      final fetchedList = conversationsData
          .map((data) => ConversationSummary.fromJson(data as Map<String, dynamic>))
          .toList();
      fetchedList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      debugPrint('Fetched and parsed ${fetchedList.length} conversation summaries.');
      return fetchedList;
    } catch (e) {
      debugPrint('Error fetching conversation list internally: $e');
      return null; // Return null on error, caller (setUserId) will handle
    }
  }
  // --- End Internal Fetch Conversation List ---


  // Fetch conversations for the current user (public, manages state)
  Future<void> fetchConversationList() async {
     if (_currentUserId == null) {
      debugPrint('Cannot fetch conversation list: No user ID set');
      _conversationList = [];
      _error = 'User not logged in.';
      notifyListeners();
      return;
    }
    _isLoadingConversations = true;
    _error = null; // Clear previous errors
    notifyListeners(); // Notify UI that list is loading

    ConversationSummary? currentPlaceholder;
    // Find the current placeholder *before* fetching
    final currentConvIndex = _conversationList.indexWhere((c) => c.id == _currentConversationId);
    if (currentConvIndex != -1 && _conversationList[currentConvIndex].title == "New Conversation") {
        currentPlaceholder = _conversationList[currentConvIndex];
    }

    try {
      final fetchedList = await _fetchConversationListInternal(); // Fetch data

      if (fetchedList != null) {
         // Start with the fetched list
         _conversationList = fetchedList;
         // If the current conversation (placeholder) wasn't in the fetched list, add it back
         if (currentPlaceholder != null && !_conversationList.any((c) => c.id == currentPlaceholder!.id)) {
            _conversationList.insert(0, currentPlaceholder);
            _conversationList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Re-sort
         }
         _error = null; // Clear error on successful fetch
      } else {
        _error = 'Failed to load conversation list.';
        // Don't clear the list if fetch fails but we had a placeholder
        if (currentPlaceholder == null) {
           _conversationList = []; 
        } else {
           // Keep only the placeholder if fetch failed
           _conversationList = [currentPlaceholder];
        }
      }
    } catch (e) {
       debugPrint('Error in public fetchConversationList: $e');
       _error = 'Failed to load conversation list: $e';
       // Keep placeholder on error if it exists
       _conversationList = currentPlaceholder != null ? [currentPlaceholder] : [];
    } finally {
      _isLoadingConversations = false;
      notifyListeners(); // Notify UI about the potentially merged list or error state
    }
  }


  // Load a specific conversation
  Future<void> loadConversation(String conversationId) async {
    _isLoading = true; // Loading messages state
    _error = null;
    _messages.clear(); // Clear messages immediately
    notifyListeners(); // Notify UI about the clear
    
    try {
      final userId = _ensureValidUserId();
      
      // Get conversation details (optional, maybe just get messages)
      // final conversation = await _chatService.getConversation(conversationId, userId: userId);

      // Update the current conversation ID *before* fetching messages
      _currentConversationId = conversationId;
      debugPrint('Loading conversation: $_currentConversationId');

      // Reset token/cost tracking for the newly loaded conversation
      resetTokenAndCostTracking();

      // Get messages for the conversation
      _messages = await _chatService.getConversationMessages(conversationId, userId: userId);
      
      // TODO: Optionally update token/cost from conversation details if needed later
      // if (conversation['token_window'] != null) { ... }
      
    } catch (e) {
      debugPrint('Error loading conversation $conversationId: $e');
      _error = 'Failed to load conversation: $e';
      _messages = []; // Ensure messages are cleared on error too
      _currentConversationId = null; // Clear current ID on error
    } finally {
       _isLoading = false;
       notifyListeners(); // Update UI with messages/error/loading state
    }
  }

  // --- Model Selection Logic ---
  // Duplicated _loadModelsInternal removed, keeping the one called by initialize

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
  // --- End Model Selection ---

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
  int _estimateTokenCount(String? text) { // Accept nullable string
    if (text == null || text.isEmpty) {
      return 0;
    }
    // Simple approximation: about 4 characters per token for English
    return (text.length / 4).ceil();
  }

  // Update token usage without requiring a model
  void _updateTokenUsageWithFallback(ChatMessage message, {bool isInput = true}) {
    // Estimate token count if not provided, handle null content
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
    
    // No notifyListeners here, caller should notify if needed
  }

  // Original _updateTokenUsage method now uses the new fallback method
  void _updateTokenUsage(ChatMessage message, {bool isInput = true}) {
    _updateTokenUsageWithFallback(message, isInput: isInput);
    notifyListeners(); // Notify after updating usage
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
    _updateTokenUsage(message, isInput: true); // Update usage and notify
    
    debugPrint('Current message count before sending to API: ${_messages.length}');
    
    // Now send the message to the AI
    await sendMessage(content);
  }
  
  Future<void> sendMessage(String content, {
    bool useStream = true,
    double? temperature,
    int? maxTokens,
  }) async {
    // Ensure user ID setup is complete before sending messages
    await _userIdSetupCompleter?.future; 

    try {
      _error = null; // Clear previous errors at the start
      
      if (content.trim().isEmpty) {
        debugPrint('Cannot send empty message');
        return;
      }
      
      if (_selectedModel == null) {
        setError('Please select a model before sending a message');
        return;
      }
      
      await _ensureConversationExists();
      if (_currentConversationId == null) {
        setError('Could not create or find a conversation. Please try again.');
        return;
      }
      
      final apiMessageHistory = List<ChatMessage>.from(_messages);
      
      if (apiMessageHistory.isEmpty) {
        setError('No messages to send. Please type a message.');
        return;
      }
      
      final tempAssistantMessage = ChatMessage(
        role: 'assistant',
        content: '', // Start empty
        model: _selectedModel,
      );
      _messages.add(tempAssistantMessage);
      
      _currentStreamedResponse = ''; 
      _isLoading = true; 
      notifyListeners(); // Show placeholder and loading state
      
      debugPrint('Sending messages to API (Count: ${apiMessageHistory.length}):');
      // ... (optional detailed logging of messages) ...

      if (_streamSubscription != null) {
        await _streamSubscription!.cancel();
        _streamSubscription = null;
      }
      
      _streamController = StreamController<String>();
      
      try {
        final String modelForApi = _selectedModel!.modelId; // Use modelId directly
        debugPrint('Using model for API request: $modelForApi');
        
        final stream = _chatService.streamChat(
          modelForApi,
          apiMessageHistory,
          userId: _ensureValidUserId(),
          conversationId: _currentConversationId,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        
        _streamSubscription = stream.listen(
          (chunk) {
            if (chunk.startsWith("*ERROR_MESSAGE*")) {
              final errorMessage = chunk.substring("*ERROR_MESSAGE*".length);
              setError(errorMessage);
              if (_messages.isNotEmpty && _messages.last.role == 'assistant' && (_messages.last.content == null || _messages.last.content!.isEmpty)) {
                _messages.removeLast();
                // setError already notifies
              }
              _streamSubscription?.cancel(); // Stop listening on error
              return;
            }

            _currentStreamedResponse += chunk; 

            if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
               String currentContent = _messages.last.content ?? '';
               _messages[_messages.length - 1] = _messages.last.copyWith(
                 content: currentContent + chunk,
               );
               notifyListeners();
            } else {
               debugPrint("Warning: Stream chunk received but no assistant placeholder message found.");
            }

            _streamController?.add(chunk);
          },
          onDone: () {
            debugPrint('onDone: Entered. Accumulated response length: ${_currentStreamedResponse.length}');
            if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
               _finalizeAssistantMessage(_currentStreamedResponse); // Finalize and notify
            } else {
               debugPrint('onDone: Condition NOT met. Last message role might not be assistant or list empty.');
               _isLoading = false;
               notifyListeners();
            }

            if (_currentStreamedResponse.isEmpty) {
              debugPrint('Stream completed with empty response. Removing placeholder.');
              if (_messages.isNotEmpty && _messages.last.role == 'assistant' && (_messages.last.content == null || _messages.last.content!.isEmpty)) {
                 _messages.removeLast();
                 // No extra notify needed, _finalizeAssistantMessage handles it or the error case does
              }
            } else {
              debugPrint('Stream completed with content.');
              // Error state is handled within _finalizeAssistantMessage or onError
            }

            _streamController?.close();
            _streamSubscription = null; // Clear subscription
            debugPrint('Stream completed and resources cleaned up.');
          },
          onError: (e) {
            debugPrint('Stream error: $e');
            if (_currentStreamedResponse.isEmpty) {
              setError('Error during streaming: $e');
            } else {
              debugPrint('Stream error occurred, but we have partial content. Finalizing.');
              _finalizeAssistantMessage(_currentStreamedResponse); // Finalize with partial content
            }
            _streamController?.close();
             _streamSubscription = null; // Clear subscription
          },
          cancelOnError: true,
        );
      } catch (e) {
        debugPrint('Error setting up stream: $e');
        setError('Error setting up message stream: $e');
        // Clean up placeholder if stream setup fails
        if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
           _messages.removeLast();
        }
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in sendMessage: $e');
      setError('Error sending message: $e');
       // Clean up placeholder if outer try fails
        if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
           _messages.removeLast();
        }
       _isLoading = false;
       notifyListeners();
    }
  }
  
  // Update the conversation title
  Future<void> _updateConversationTitle({bool forceUpdate = false}) async {
    if (_currentConversationId == null) return;
    
    final userId = _ensureValidUserId();
    
    try {
      await _chatService.updateConversationTitle(
        _currentConversationId!,
        forceUpdate: forceUpdate,
        userId: userId
      );
    } catch (e) {
      debugPrint('Error updating conversation title: $e');
    }
  }
  
  // Refresh models from the server
  Future<void> refreshModels() async {
    try {
      _isLoadingModels = true;
      notifyListeners();
      
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
  
  // Helper method to update the selected model after refresh
  void _updateSelectedModelAfterRefresh() {
    if (_selectedModel != null) {
      final String currentModelId = _selectedModel!.modelId;
      final modelIndex = _availableModels.indexWhere(
        (model) => model.modelId == currentModelId
      );
      
      if (modelIndex >= 0) {
        // Found the same model in the updated list, no need to call setSelectedModel again unless details changed
        _selectedModel = _availableModels[modelIndex]; 
      } else if (_availableModels.isNotEmpty) {
        // Couldn't find same model, use the first available
        setSelectedModel(_availableModels.first); // Save the new default
      } else {
         _selectedModel = null; // No models available
      }
    } else if (_availableModels.isNotEmpty) {
      // No previously selected model, use the first one
      setSelectedModel(_availableModels.first); // Save the new default
    } else {
       _selectedModel = null; // No models available
    }
    notifyListeners(); // Notify about potential model change
  }
  
  // Set user information and initialize conversation list
  Future<void> setUserId(String userId, {String? username, String? name}) async {
    _currentUserId = userId;
    _currentUserName = username ?? userId; // Keep username for auth header
    _currentDisplayName = name ?? _currentUserName; // Use displayName, fallback to username
    
    _chatService.setCurrentUsername(_currentUserName!); // Use username for auth header
    
    debugPrint('Set user ID: $userId, username: $_currentUserName, displayName: $_currentDisplayName');
    
    // Reset state BEFORE async calls
    _currentConversationId = null;
    _messages = [];
    resetTokenAndCostTracking(); 
    _conversationList = []; // Clear list immediately
    _isLoadingConversations = true; // Set loading true
    _error = null; // Clear previous errors
    _userIdSetupCompleter = Completer<void>();
    notifyListeners(); // Notify UI about reset and loading state

    List<ConversationSummary>? fetchedList;
    ConversationSummary? conversationToUse;

    try {
      // 1. Fetch existing conversations FIRST
      fetchedList = await _fetchConversationListInternal(); 

      // 2. Check if the most recent conversation is empty (using title)
      if (fetchedList != null && fetchedList.isNotEmpty && fetchedList.first.title == "New Conversation") {
         // 3a. Reuse the existing empty conversation
         conversationToUse = fetchedList.first;
         _currentConversationId = conversationToUse.id;
         _messages = []; // Ensure messages are clear for reused empty convo
         resetTokenAndCostTracking(); 
         debugPrint('[ChatProvider setUserId] Reusing existing empty conversation: $_currentConversationId');
         // No need to call _createBackendConversation
      } else {
         // 3b. Create a new conversation if no suitable one exists
         debugPrint('[ChatProvider setUserId] No suitable empty conversation found, creating new one...');
         conversationToUse = await _createBackendConversation(); // Creates, sets _currentConversationId, clears messages
         if (conversationToUse == null) {
            throw Exception("Failed to create initial conversation.");
         }
         debugPrint('[ChatProvider setUserId] Created new conversation: $_currentConversationId');
      }

      // 4. Populate the conversation list for the UI
      // Ensure the conversation being used is at the top, followed by others.
      _conversationList = [
        if (conversationToUse != null) conversationToUse, // Add the active one (reused or new)
        ...?fetchedList?.where((c) => c.id != conversationToUse?.id), // Add others from fetched list, excluding the one we're using
      ];
      // Sort again to be sure, especially if fetchedList was null or empty initially
      _conversationList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); 

      _error = null; // Clear error on success

    } catch (e) {
       debugPrint('[ChatProvider setUserId] Error during conversation setup: $e');
       _error = 'Failed to initialize conversations.';
       _conversationList = []; // Clear list on error
       _currentConversationId = null;
       _messages = [];
       resetTokenAndCostTracking();
    } finally {
      _isLoadingConversations = false; 
      notifyListeners(); // Notify UI with the final list and state
      _userIdSetupCompleter?.complete(); 
    }
  }

  // New method for UI button press: Creates backend conversation AND updates UI state
  Future<void> requestNewConversation() async {
    final placeholder = await _createBackendConversation(); // Create backend conversation & get placeholder
    if (placeholder != null) {
      // Clear local messages and costs for the new conversation
      _messages.clear();
      resetTokenAndCostTracking();
      // Prepend placeholder to the list and notify UI
      _conversationList.removeWhere((c) => c.id == placeholder.id); // Remove potential duplicate if backend was fast
      _conversationList.insert(0, placeholder);
      _conversationList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Ensure sort order
      // _currentConversationId is already set by _createBackendConversation
      notifyListeners(); // Update list UI and selection
    }
    // If _createBackendConversation failed, error state is already set and notified
  }

  // Create a new conversation (UI Action) - Deprecated, use requestNewConversation
  Future<void> createNewConversation() async {
     final placeholder = await _createBackendConversation(); // Create backend conversation & get placeholder
     // Prepend placeholder and notify UI
     if (placeholder != null) {
        _conversationList.removeWhere((c) => c.id == placeholder.id); // Remove potential duplicate
        _conversationList.insert(0, placeholder);
        notifyListeners(); // Update list UI
     }
     // If startNewConversation failed, error state is already set and notified
  }

  @override
  void dispose() {
    _chatService.dispose();
    _streamController?.close();
    _streamSubscription?.cancel();
    super.dispose();
  }

  // Helper method to ensure we have a valid user ID
  String _ensureValidUserId() {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      debugPrint('Warning: No user ID set, using generated ObjectId');
      // This should ideally not happen if login flow is correct
      // Consider throwing an error or using a default/guest ID
      return 'DEFAULT_GUEST_ID'; // Example fallback
    }
    return _currentUserId!;
  }

  // Helper method to finalize an assistant message after streaming completes
  void _finalizeAssistantMessage(String content) {
    debugPrint('_finalizeAssistantMessage entered. Current message count: ${_messages.length}');

    if (content.isEmpty) {
      debugPrint('_finalizeAssistantMessage: Content is empty, removing placeholder.');
       if (_messages.isNotEmpty && _messages.last.role == 'assistant' && (_messages.last.content == null || _messages.last.content!.isEmpty)) {
          _messages.removeLast();
       }
       // Set loading false and notify AFTER potentially removing message
       _isLoading = false;
       _currentStreamedResponse = '';
       notifyListeners(); 
      return;
    }
    
    final lastIndex = _messages.length - 1;
    if (lastIndex >= 0 && _messages[lastIndex].role == 'assistant') {
      final finalMessage = ChatMessage(
        id: _messages[lastIndex].id, // Keep original ID if available
        role: 'assistant',
        content: content,
        model: _selectedModel,
        createdAt: DateTime.now(),
        timestamp: _messages[lastIndex].timestamp, // Keep original timestamp
      );
      
      _messages[lastIndex] = finalMessage;
      
      _updateTokenUsageWithFallback(finalMessage, isInput: false); // Update usage (doesn't notify)

      // --- Trigger Summarization Logic ---
      debugPrint('Finalize Assistant: Message count = ${_messages.length}, Current Conv ID = $_currentConversationId');
      if (_messages.length == 4 && _currentConversationId != null) {
        debugPrint('Finalize Assistant: Checking condition for summarization trigger.');
        // Directly call _triggerSummarization, which now awaits the completer internally
        _triggerSummarization(); 
      } else {
         debugPrint('Finalize Assistant: Conditions for summarization not met (message count: ${_messages.length}, convId: $_currentConversationId).');
      }
      // --- End Trigger Summarization ---
    }

    // Set loading false and notify AFTER all updates are done
    _isLoading = false;
    _currentStreamedResponse = '';
    notifyListeners(); 
  }

  // Explicitly prepare a conversation (e.g., called by ChatScreen initState)
  Future<bool> prepareConversation() async {
    try {
      debugPrint('Explicitly preparing conversation...');
      await _ensureConversationExists(); // Make sure we have an ID
      
      if (_currentConversationId == null || _currentConversationId!.isEmpty) {
        debugPrint('ERROR: Failed to create/ensure conversation during preparation');
        setError('Failed to prepare conversation. Please try again.');
        return false;
      }
      
      debugPrint('Successfully prepared conversation: $_currentConversationId');
      return true;
    } catch (e) {
      debugPrint('Error preparing conversation: $e');
      setError('Failed to prepare conversation: $e');
      return false;
    }
  }

  // Creates a new backend conversation, sets it as current, clears messages,
  // and returns a placeholder ConversationSummary. Does NOT modify _conversationList directly.
  Future<ConversationSummary?> _createBackendConversation() async {
    ConversationSummary? placeholderSummary;
    // Set loading specific to conversation creation/switching
    // _isLoading = true; // Loading state handled by caller (setUserId or requestNewConversation)
    // notifyListeners(); // Notification handled by caller

    try {
      debugPrint('Creating backend conversation...'); // Updated log message
      final conversationId = await _chatService.createConversation();
      if (conversationId == null || conversationId.isEmpty) {
         throw Exception("Failed to create conversation on backend.");
      }
      _currentConversationId = conversationId;
      _messages.clear(); // Clear messages for the new conversation
      resetTokenAndCostTracking(); // Reset costs for new conversation

      placeholderSummary = ConversationSummary(
        id: conversationId,
        title: "New Conversation", // Placeholder title
        updatedAt: DateTime.now(),
      );
      debugPrint('Backend conversation created with ID: $conversationId'); // Updated log message
      
    } catch (e) {
      debugPrint('Error creating backend conversation: $e'); // Updated log message
      setError('Failed to create backend conversation: $e'); // Use setError to notify
      return null; // Return null on error
    } finally {
       // _isLoading = false; // Loading state handled by caller
       // Do not notify here, let the caller handle final notification
    }
    return placeholderSummary; // Return the placeholder
  }

  // --- New Helper Method: Trigger Summarization ---
  Future<void> _triggerSummarization() async {
    // Await completion of setUserId before proceeding
    await _userIdSetupCompleter?.future; 
    
    debugPrint('_triggerSummarization called.');
    if (_currentConversationId == null || _messages.length < 4) {
      debugPrint('_triggerSummarization: Conditions not met (ConvID: $_currentConversationId, Msg Count: ${_messages.length}). Bailing out.');
      return;
    }

    final messagesToSummarize = _messages.sublist(0, 4);

    debugPrint('Triggering summarization for conversation $_currentConversationId');
    try {
      final generatedTitle = await _chatService.summarizeConversation(
        _currentConversationId!,
        messagesToSummarize,
      );

      if (generatedTitle != null && generatedTitle.isNotEmpty) {
        final index = _conversationList.indexWhere((c) => c.id == _currentConversationId);
        if (index != -1) {
          _conversationList[index] = _conversationList[index].copyWith(title: generatedTitle);
           _conversationList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          notifyListeners(); 
          debugPrint('Conversation list updated with new title: $generatedTitle');
        } else {
           debugPrint('Summarization triggered, but conversation ID $_currentConversationId not found in list after title generation.');
           // If the placeholder was somehow missed, add it now with the title
           _conversationList.insert(0, ConversationSummary(id: _currentConversationId!, title: generatedTitle, updatedAt: DateTime.now()));
           _conversationList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Re-sort after insert
           notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error triggering summarization: $e');
      setError('Failed to generate conversation title: $e');
    }
  }
  // --- End New Helper Method ---

  // --- New Method: Rename Conversation ---
  Future<void> renameConversation(String conversationId, String newTitle) async {
    final index = _conversationList.indexWhere((c) => c.id == conversationId);
    if (index == -1) {
      debugPrint('Cannot rename: Conversation $conversationId not found in local list.');
      throw Exception('Conversation not found');
    }

    final oldTitle = _conversationList[index].title;

    _conversationList[index] = _conversationList[index].copyWith(title: newTitle);
    notifyListeners();

    try {
      await _chatService.renameConversation(conversationId, newTitle);
      debugPrint('Successfully renamed conversation $conversationId to "$newTitle"');
    } catch (e) {
      _conversationList[index] = _conversationList[index].copyWith(title: oldTitle);
      notifyListeners();
      debugPrint('Error renaming conversation $conversationId: $e');
      throw Exception('Failed to rename conversation: $e');
    }
  }
  // --- End New Method ---

  // --- New Method: Delete Conversation ---
  Future<void> deleteConversation(String conversationId) async {
    final index = _conversationList.indexWhere((c) => c.id == conversationId);
    if (index == -1) {
      debugPrint('Cannot delete: Conversation $conversationId not found in local list.');
      throw Exception('Conversation not found');
    }
    final deletedSummary = _conversationList[index];

    _conversationList.removeAt(index);
    bool wasCurrentConversation = _currentConversationId == conversationId;
    notifyListeners();

    try {
      final userId = _ensureValidUserId();
      await _chatService.deleteConversation(conversationId, userId: userId);
      debugPrint('Successfully deleted conversation $conversationId for user $userId');

      if (wasCurrentConversation) {
        _currentConversationId = null; 
        if (_conversationList.isNotEmpty) {
          await loadConversation(_conversationList.first.id);
        } else {
          // If no conversations left, start a new one and update list
          await setUserId(_currentUserId!, username: _currentUserName); // Re-run setUserId to start fresh
        }
      }
    } catch (e) {
      _conversationList.insert(index, deletedSummary); // Re-insert on error
      notifyListeners();
      debugPrint('Error deleting conversation $conversationId: $e');
      throw Exception('Failed to delete conversation: $e');
    }
  }
  // --- End New Method ---
}
