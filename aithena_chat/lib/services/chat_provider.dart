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
  static const String _selectedModelPlatformKey = 'selected_model_platform';

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
        _chatService.getOllamaModels().catchError((e) {
          debugPrint('Ollama models error: $e');
          return <String>[];
        }),
        _chatService.getOpenAIModels().catchError((e) {
          debugPrint('OpenAI models error: $e');
          return <String>[];
        }),
        _chatService.getGroqModels().catchError((e) {
          debugPrint('Groq models error: $e');
          return <String>[];
        }),
      ]);

      final ollamaModels = results[0];
      final openaiModels = results[1];
      final groqModels = results[2];

      // Create LLMModel instances with correct platform
      _availableModels = [
        ...ollamaModels.map((name) => LLMModel.fromName(name, platform: 'ollama')),
        ...openaiModels.map((name) => LLMModel.fromName(name, platform: 'openai')),
        ...groqModels.map((name) => LLMModel.fromName(name, platform: 'groq')),
      ];

      if (_availableModels.isEmpty) {
        throw Exception('No models available. Please check your backend connection.');
      }
      
      // Load previously selected model from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedModelName = prefs.getString(_selectedModelKey);
      final savedModelPlatform = prefs.getString(_selectedModelPlatformKey);
      
      if (savedModelName != null && savedModelPlatform != null) {
        final savedModel = _availableModels.firstWhere(
          (model) => model.name == savedModelName && model.platform == savedModelPlatform,
          orElse: () => _availableModels.first,
        );
        await selectModel(savedModel);
      } else if (_availableModels.isNotEmpty) {
        await selectModel(_availableModels.first);
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading models: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectModel(LLMModel model) async {
    try {
      _selectedModel = model;
      // Save selected model to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedModelKey, model.name);
      await prefs.setString(_selectedModelPlatformKey, model.platform);
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