import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import 'chat_service.dart';

class ChatProvider with ChangeNotifier {
  final ChatService _chatService = ChatService();
  List<ChatMessage> _messages = [];
  List<LLMModel> _availableModels = [];
  LLMModel? _selectedModel;
  bool _isLoading = false;
  String _error = '';
  String _currentStreamedResponse = '';
  static const String _selectedModelKey = 'selected_model';
  static const String _selectedModelPlatformKey = 'selected_model_platform';

  List<ChatMessage> get messages => _messages;
  List<LLMModel> get availableModels => _availableModels;
  LLMModel? get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  String get error => _error;
  String get currentStreamedResponse => _currentStreamedResponse;

  Future<void> loadModels() async {
    try {
      _isLoading = true;
      notifyListeners();
      _error = '';

      // Load models from different endpoints
      final ollamaModels = await _chatService.getOllamaModels();
      final openaiModels = await _chatService.getOpenAIModels();
      final groqModels = await _chatService.getGroqModels();

      // Create LLMModel instances with correct platform
      final models = [
        ...ollamaModels.map((name) => LLMModel.fromName(name, platform: 'ollama')),
        ...openaiModels.map((name) => LLMModel.fromName(name, platform: 'openai')),
        ...groqModels.map((name) => LLMModel.fromName(name, platform: 'groq')),
      ];

      _availableModels = models;
      
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
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectModel(LLMModel model) async {
    _selectedModel = model;
    // Save selected model to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, model.name);
    await prefs.setString(_selectedModelPlatformKey, model.platform);
    notifyListeners();
  }

  void addUserMessage(String content) {
    _messages.add(ChatMessage(role: 'user', content: content));
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (_selectedModel == null) return;

    // Add user message immediately
    addUserMessage(content);
    
    // Create a temporary assistant message for streaming
    var tempMessage = ChatMessage(role: 'assistant', content: '');
    _messages.add(tempMessage);
    
    _isLoading = true;
    _currentStreamedResponse = '';
    notifyListeners();

    try {
      await for (final chunk in _chatService.streamChat(
        _selectedModel!.name,
        _messages,
      )) {
        _currentStreamedResponse += chunk;
        // Replace the temporary message with updated content
        _messages[_messages.length - 1] = ChatMessage(
          role: 'assistant',
          content: _currentStreamedResponse,
          id: tempMessage.id,
          timestamp: tempMessage.timestamp,
        );
        notifyListeners();
      }

      // Clear the streaming state
      _currentStreamedResponse = '';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearChat() {
    _messages.clear();
    _currentStreamedResponse = '';
    notifyListeners();
  }
} 