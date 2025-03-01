import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import 'chat_service.dart';

class ChatProvider with ChangeNotifier {
  final ChatService _chatService;
  List<ChatMessage> _messages = [];
  List<LLMModel> _availableModels = [];
  LLMModel? _selectedModel;
  bool _isLoading = false;
  String? _error;
  String _currentStreamedResponse = '';
  static const String _selectedModelKey = 'selected_model';

  ChatProvider({ChatService? chatService}) : _chatService = chatService ?? ChatService();

  List<ChatMessage> get messages => _messages;
  List<LLMModel> get availableModels => _availableModels;
  LLMModel? get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentStreamedResponse => _currentStreamedResponse;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> loadModels() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Load models from different endpoints in parallel
      final results = await Future.wait([
        _chatService.getLLMModels().catchError((e) {
          debugPrint('LLM models error: $e');
          return <String>[];
        }),
      ]);

      final llmModels = results[0];

      // Create LLMModel instances
      _availableModels = [
        ...llmModels.map((name) => LLMModel(name: name)),
      ];

      if (_availableModels.isEmpty) {
        debugPrint('No models available from backend, using fallback models');
        // Instead of throwing an exception, provide fallback models
        _provideFallbackModels();
      }
      
      // Load previously selected model from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedModelName = prefs.getString(_selectedModelKey);
      
      if (savedModelName != null) {
        final savedModel = _availableModels.firstWhere(
          (model) => model.name == savedModelName,
          orElse: () => _availableModels.first,
        );
        await selectModel(savedModel);
      } else if (_availableModels.isNotEmpty) {
        await selectModel(_availableModels.first);
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading models: $e');
      // Provide fallback models even on error
      _provideFallbackModels();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add fallback models when backend is not available
  void _provideFallbackModels() {
    // If we already have models, don't override them
    if (_availableModels.isNotEmpty) return;
    
    _availableModels = [
      LLMModel(name: 'gpt-3.5-turbo'),
      LLMModel(name: 'gpt-4'),
    ];
    
    _error = 'Could not connect to backend. Using offline mode with limited functionality.';
    debugPrint('Using fallback models: $_availableModels');
  }

  Future<void> selectModel(LLMModel model) async {
    try {
      _selectedModel = model;
      // Save selected model to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedModelKey, model.name);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to save model preference: ${e.toString()}';
      debugPrint('Error saving model preference: $e');
      notifyListeners();
    }
  }

  void addUserMessage(String content) {
    _messages.add(ChatMessage(
      role: 'user',
      content: content,
      model: _selectedModel,
    ));
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (_selectedModel == null) {
      _error = 'Please select a model first';
      notifyListeners();
      return;
    }

    if (content.trim().isEmpty) {
      return;
    }

    // Add user message immediately
    addUserMessage(content);
    
    // Create a temporary assistant message for streaming
    var tempMessage = ChatMessage(
      role: 'assistant',
      content: '',
      model: _selectedModel,
    );
    _messages.add(tempMessage);
    
    _isLoading = true;
    _currentStreamedResponse = '';
    _error = null;
    notifyListeners();

    try {
      StringBuffer accumulatedContent = StringBuffer();
      
      await for (final chunk in _chatService.streamChat(
        _selectedModel!.name,
        _messages,
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
          model: _selectedModel,
        );
        
        // Update the message in the list and notify listeners immediately
        _messages[_messages.length - 1] = updatedMessage;
        notifyListeners();
      }
      
      // Ensure final state is reflected
      final finalMessage = ChatMessage(
        role: 'assistant',
        content: _currentStreamedResponse,
        id: tempMessage.id,
        timestamp: tempMessage.timestamp,
        model: _selectedModel,
      );
      _messages[_messages.length - 1] = finalMessage;
      
    } catch (e) {
      _error = 'Failed to get response: ${e.toString()}';
      debugPrint('Error in sendMessage: $e');
      // Remove the temporary message if we failed to get a response
      if (_messages.isNotEmpty) {
        _messages.removeLast();
      }
    } finally {
      _isLoading = false;
      _currentStreamedResponse = '';
      notifyListeners();
    }
  }

  void clearChat() {
    _messages.clear();
    _currentStreamedResponse = '';
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }
} 