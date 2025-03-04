import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import '../config/env_config.dart';

class ChatService {
  final String _baseUrl;
  final http.Client _client;
  String? _currentUsername;
  
  // Cached models to avoid frequent reloading
  List<String>? _cachedModels;
  DateTime? _modelsCacheTime;
  
  // Increased timeout durations
  static const Duration _shortTimeout = Duration(seconds: 20);  // From 10 to 20 seconds
  static const Duration _longTimeout = Duration(seconds: 60);   // From 15 to 60 seconds
  
  // Cache lifetime for models (10 minutes)
  static const Duration _modelCacheLifetime = Duration(minutes: 10);

  ChatService({http.Client? client}) : 
    _baseUrl = EnvConfig.backendUrl,
    _client = client ?? http.Client();
  
  // Set current username for authentication
  void setCurrentUsername(String username) {
    _currentUsername = username;
    debugPrint('ChatService: Set current username to $_currentUsername');
  }

  // Helper method to get the appropriate API URL based on platform
  static String _getApiUrl() {
    if (kIsWeb) {
      // For web, we need to handle CORS issues
      // If you're deploying this app, replace this with your actual API endpoint
      // For development, consider using a CORS proxy or configuring your server properly
      final webApiUrl = EnvConfig.backendUrl;
      debugPrint('Using web API URL: $webApiUrl');
      return webApiUrl;
    } else {
      // Regular mobile/desktop API URL
      return EnvConfig.backendUrl;
    }
  }

  // Conversation management methods
  Future<String> createConversation(String userId) async {
    try {
      // Use currentUsername if available, otherwise fall back to userId
      final String authUsername = _currentUsername ?? userId;
      debugPrint('Creating new conversation for user: $userId with auth username: $authUsername');
      
      final response = await _client.post(
        Uri.parse('$_baseUrl/conversations/create'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Username': authUsername, // Use username for authentication
        },
        body: json.encode({
          'user_id': userId,
          'title': 'New Conversation',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        final conversationId = data['id'];
        debugPrint('Created conversation with ID: $conversationId');
        return conversationId;
      }
      
      debugPrint('Failed to create conversation: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to create conversation: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error creating conversation: $e');
      rethrow;
    }
  }

  Future<void> addMessageToConversation(String conversationId, ChatMessage message, {required String userId}) async {
    try {
      debugPrint('Adding ${message.role} message to conversation $conversationId');
      
      final requestBody = {
        'content': message.content,
        'role': message.role,
        'metadata': message.metadata ?? {},
      };
      
      // Only include model_id for assistant messages
      if (message.model?.modelId != null) {
        requestBody['model_id'] = message.model!.modelId;
      }
      
      // Use currentUsername if available, otherwise fall back to userId
      final String authUsername = _currentUsername ?? userId;
      
      debugPrint('Request body: ${json.encode(requestBody)}');
      debugPrint('Using auth username: $authUsername');
      
      final response = await _client.post(
        Uri.parse('$_baseUrl/conversations/$conversationId/add_message'),
        headers: {
          'Content-Type': 'application/json',
          'X-Username': authUsername,
        },
        body: json.encode(requestBody),
      ).timeout(_shortTimeout);

      if (response.statusCode != 200) {
        debugPrint('Failed to add message: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to add message: ${response.statusCode}');
      }
      
      debugPrint('Successfully added message to conversation $conversationId');
    } catch (e) {
      debugPrint('Error adding message to conversation: $e');
      rethrow;
    }
  }

  Future<void> updateConversationTitle(String conversationId, {bool forceUpdate = false, required String userId}) async {
    try {
      // Use currentUsername if available, otherwise fall back to userId
      final String authUsername = _currentUsername ?? userId;
      
      debugPrint('Updating title for conversation $conversationId, force update: $forceUpdate');
      debugPrint('Using auth username: $authUsername');
      
      final response = await _client.put(
        Uri.parse('$_baseUrl/conversations/$conversationId/update_title'),
        headers: {
          'Content-Type': 'application/json',
          'X-Username': authUsername,
        },
        body: json.encode({
          'title': 'Auto-generated Title',
          'force_update': forceUpdate,
        }),
      ).timeout(_shortTimeout);

      if (response.statusCode != 200) {
        debugPrint('Failed to update title: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to update title: ${response.statusCode}');
      }
      
      debugPrint('Updated title for conversation $conversationId');
    } catch (e) {
      debugPrint('Error updating conversation title: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getConversations(String userId) async {
    try {
      // Use currentUsername if available, otherwise fall back to userId
      final String authUsername = _currentUsername ?? userId;
      
      debugPrint('Fetching conversations for user: $userId');
      debugPrint('Using auth username: $authUsername');
      
      final response = await _client.get(
        Uri.parse('$_baseUrl/conversations/list'),
        headers: {
          'Accept': 'application/json',
          'X-Username': authUsername,
        },
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Retrieved ${data['conversations']?.length ?? 0} conversations');
        return data['conversations'] ?? [];
      }
      
      debugPrint('Failed to get conversations: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to get conversations: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching conversations: $e');
      rethrow;
    }
  }

  Future<dynamic> getConversation(String conversationId, {required String userId}) async {
    try {
      // Use currentUsername if available, otherwise fall back to userId
      final String authUsername = _currentUsername ?? userId;
      
      debugPrint('Fetching conversation $conversationId for user: $userId');
      debugPrint('Using auth username: $authUsername');
      
      final response = await _client.get(
        Uri.parse('$_baseUrl/conversations/$conversationId/get'),
        headers: {
          'Accept': 'application/json',
          'X-Username': authUsername,
        },
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        debugPrint('Successfully retrieved conversation $conversationId');
        return json.decode(response.body);
      }
      
      debugPrint('Failed to get conversation: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to get conversation: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching conversation: $e');
      rethrow;
    }
  }
  
  Future<List<ChatMessage>> getConversationMessages(String conversationId, {required String userId}) async {
    try {
      // Use currentUsername if available, otherwise fall back to userId
      final String authUsername = _currentUsername ?? userId;
      
      debugPrint('Fetching messages for conversation $conversationId');
      debugPrint('Using auth username: $authUsername');
      
      final response = await _client.get(
        Uri.parse('$_baseUrl/conversations/$conversationId/get_messages'),
        headers: {
          'Accept': 'application/json',
          'X-Username': authUsername,
        },
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> messagesJson = data['messages'] ?? [];
        
        debugPrint('Retrieved ${messagesJson.length} messages from conversation $conversationId');
        return messagesJson.map((msgJson) => ChatMessage.fromJson(msgJson)).toList();
      }
      
      debugPrint('Failed to get conversation messages: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to get conversation messages: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching conversation messages: $e');
      rethrow;
    }
  }
  
  Future<void> deleteConversation(String conversationId, {required String userId}) async {
    try {
      // Use currentUsername if available, otherwise fall back to userId
      final String authUsername = _currentUsername ?? userId;
      
      debugPrint('Deleting conversation $conversationId');
      debugPrint('Using auth username: $authUsername');
      
      final response = await _client.delete(
        Uri.parse('$_baseUrl/conversations/$conversationId/delete'),
        headers: {
          'Accept': 'application/json',
          'X-Username': authUsername,
        },
      ).timeout(_shortTimeout);

      if (response.statusCode != 204) {
        debugPrint('Failed to delete conversation: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to delete conversation: ${response.statusCode}');
      }
      
      debugPrint('Deleted conversation $conversationId');
    } catch (e) {
      debugPrint('Error deleting conversation: $e');
      rethrow;
    }
  }

  Future<List<String>> getLLMModels() async {
    try {
      // Check if we have a valid cached model list
      final now = DateTime.now();
      if (_cachedModels != null && 
          _modelsCacheTime != null && 
          now.difference(_modelsCacheTime!) < _modelCacheLifetime) {
        debugPrint('Using cached model list (${_cachedModels!.length} models)');
        return _cachedModels!;
      }

      debugPrint('Fetching models from: $_baseUrl/v1/models');
      final response = await _client.get(
        Uri.parse('$_baseUrl/v1/models'),
        headers: {'Accept': 'application/json'},
      ).timeout(_shortTimeout, onTimeout: () {
        debugPrint('Request timed out while fetching models');
        throw TimeoutException('Connection timed out while fetching models. Please check your internet connection.');
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body)['data'];
        final List<String> modelIds = data.map((item) => item['id'] as String).toList();
        
        // Update cache
        _cachedModels = modelIds;
        _modelsCacheTime = now;
        
        debugPrint('Fetched and cached ${modelIds.length} LLM models');
        return modelIds;
      }
      
      debugPrint('LLM models error status: ${response.statusCode}, Body: ${response.body}');
      
      // If we have cached models and current fetch failed, return cached ones
      if (_cachedModels != null) {
        debugPrint('Falling back to cached models due to fetch error');
        return _cachedModels!;
      }
      
      throw Exception('Failed to load LLM models: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching LLM models: $e');
      
      // Return cached models if available, even on error
      if (_cachedModels != null) {
        debugPrint('Falling back to cached models due to error');
        return _cachedModels!;
      }
      
      rethrow;
    }
  }

  Stream<String> streamChat(String model, List<ChatMessage> messages, {required String userId}) async* {
    // Use currentUsername if available, otherwise fall back to userId
    final String authUsername = _currentUsername ?? userId;
    debugPrint('Streaming chat with model: $model');
    debugPrint('Using auth username: $authUsername for streaming chat');
    
    final url = Uri.parse('$_baseUrl/litellm/v1/chat/completions');
    
    // Validate the message list
    if (messages.isEmpty) {
      debugPrint('ERROR: Cannot stream chat with empty message list');
      yield* _provideFallbackResponse("No messages provided for chat completion. Please try again.");
      return;
    }
    
    // Check if the last message is from a user (as expected)
    final lastMsg = messages.last;
    if (lastMsg.role != 'user') {
      debugPrint('WARNING: Last message is not from user. Role: ${lastMsg.role}');
    }
    
    // Ensure messages are ordered properly (important for conversation history)
    // This ensures chronological order which is critical for context
    // The LLM expects messages in time order to understand the conversation flow
    final processedMessages = List<ChatMessage>.from(messages);
    processedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    
    // Log some info about the messages we're sending
    debugPrint('Streaming chat with ${processedMessages.length} messages using model: $model');
    for (int i = 0; i < processedMessages.length; i++) {
      final msg = processedMessages[i];
      debugPrint('Message ${i+1}: ${msg.role}: ${msg.content.length > 30 ? '${msg.content.substring(0, 30)}...' : msg.content}');
    }
    
    // Build request with proper headers
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['X-Username'] = authUsername
      ..body = json.encode(
        {
          'model': model,
          'messages': processedMessages.map((msg) => {
            'role': msg.role,
            'content': msg.content,
          }).toList(),
          'stream': true,
        },
      );

    try {
      debugPrint('Sending request to backend with X-Username: $authUsername');
      final response = await _client.send(request).timeout(
        _longTimeout, 
        onTimeout: () {
          debugPrint('Request timed out while streaming chat');
          throw TimeoutException('Connection timed out. Using offline response mode.');
        }
      );
      
      if (response.statusCode != 200) {
        debugPrint('Failed to get chat response: ${response.statusCode}');
        yield* _provideFallbackResponse("Server returned error ${response.statusCode}");
        return;
      }

      debugPrint('Stream connection established, processing response chunks...');
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          // Handle SSE format where lines start with "data: "
          if (line.startsWith('data: ')) {
            final jsonString = line.substring(6); // Skip "data: " prefix
            
            // Handle [DONE] marker
            if (jsonString.trim() == '[DONE]') {
              debugPrint('Stream completed with [DONE] marker');
              continue;
            }
            
            try {
              final data = json.decode(jsonString);
              if (data['choices'] != null && 
                  data['choices'][0]['delta'] != null && 
                  data['choices'][0]['delta']['content'] != null) {
                yield data['choices'][0]['delta']['content'].toString();
              }
            } catch (e) {
              debugPrint('Error parsing JSON: $e for line: $jsonString');
              // Don't yield the raw line if JSON parsing fails
            }
          } else {
            // For non-SSE format data, attempt to parse directly
            try {
              final data = json.decode(line);
              if (data['choices'] != null && 
                  data['choices'][0]['delta'] != null && 
                  data['choices'][0]['delta']['content'] != null) {
                yield data['choices'][0]['delta']['content'].toString();
              }
            } catch (e) {
              debugPrint('Error parsing non-SSE line: $e');
              // Don't yield the raw line if JSON parsing fails
            }
          }
        }
      }
      debugPrint('Stream completed');
    } catch (e) {
      debugPrint('Error in stream chat: $e');
      
      // Provide a fallback response for offline/error mode
      final String userMessage = processedMessages.isNotEmpty && processedMessages.last.role == 'user' 
          ? processedMessages.last.content 
          : '';
      
      yield* _provideFallbackResponse(userMessage);
    }
  }
  
  // Provide a fallback response when the backend is unavailable
  Stream<String> _provideFallbackResponse(String userMessage) async* {
    final fallbackResponse = 
        "I'm currently in offline mode and cannot process your request. "
        "It seems that I cannot connect to the backend server. "
        "Please check your internet connection or contact the administrator. "
        "\n\nYour message was: \"$userMessage\"";
    
    debugPrint('Providing fallback response for message: "$userMessage"');
    
    // Stream the response character by character to simulate typing
    for (var i = 0; i < fallbackResponse.length; i++) {
      yield fallbackResponse[i];
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void dispose() {
    debugPrint('Disposing ChatService');
    _client.close();
  }
} 