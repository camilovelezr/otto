import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:math'; // Import for min function
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import '../config/env_config.dart';
import 'model_service.dart'; // Import for defaultObjectId

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
    _client = client ?? http.Client() {
    // Log the base URL for debugging
    debugPrint('ChatService initialized with base URL: $_baseUrl');
  }
  
  // Get the current user ID, defaulting to a valid ObjectId if not set
  String get _currentUserId {
    if (_currentUsername == null || _currentUsername!.isEmpty) {
      return defaultObjectId;
    }
    return _currentUsername!;
  }

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

  Stream<String> streamChat(
    String model,
    List<ChatMessage> messages, {
    required String userId,
    String? conversationId,
    double? temperature,
    int? maxTokens,
  }) async* {
    // Debug model name validation
    debugPrint('Original model name provided to streamChat: $model');
    
    // Validate and normalize model name
    if (model.isEmpty) {
      debugPrint('ERROR: Empty model name provided to streamChat');
      yield* _provideFallbackResponse("No model selected. Please try again.");
      return;
    }
    
    // Make sure model doesn't look like a hash (conversation ID)
    if (model.length > 40 && !model.contains('-')) {
      debugPrint('WARNING: Model name appears to be a hash. Using fallback model name.');
      model = 'gpt-3.5-turbo'; // Using fallback
    }
    
    // Use currentUsername if available, otherwise fall back to userId
    final String authUsername = _currentUsername ?? userId;
    debugPrint('Streaming chat with model: $model, conversation: $conversationId');
    debugPrint('Using authUsername: $authUsername (X-Username header)');
    
    // Fix URL construction - don't use query parameters in the URL for conversation_id
    // The backend expects /chat/{model_name}/generate
    final url = Uri.parse('$_baseUrl/chat/$model/generate');
    
    // Add detailed logging about the endpoint
    debugPrint('Using endpoint URL: ${url.toString()}');
    
    // Validate the message list
    if (messages.isEmpty) {
      debugPrint('ERROR: Cannot stream chat with empty message list');
      yield* _provideFallbackResponse("No messages provided for chat completion. Please try again.");
      return;
    }
    
    // Remove any assistant messages with empty content (placeholders) from the list sent to API
    final filteredMessages = messages.where((msg) => 
      !(msg.role == 'assistant' && msg.content.isEmpty)).toList();
    
    if (filteredMessages.isEmpty) {
      debugPrint('ERROR: All messages were filtered out (only empty assistant messages?)');
      yield* _provideFallbackResponse("No valid messages to send. Please try again.");
      return;
    }
    
    // Check if conversation ID is provided and valid
    if (conversationId == null || conversationId.isEmpty) {
      debugPrint('ERROR: No conversation ID provided for chat streaming');
      yield* _provideFallbackResponse("No conversation ID available. Please try again.");
      return;
    }
    
    // Check if the last message is from a user (as expected)
    final lastMsg = filteredMessages.last;
    if (lastMsg.role != 'user') {
      debugPrint('WARNING: Last message is not from user. Role: ${lastMsg.role}');
    }
    
    // Ensure messages are ordered properly (important for conversation history)
    final processedMessages = List<ChatMessage>.from(filteredMessages);
    processedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    
    // Log info about the request
    debugPrint('Streaming chat with ${processedMessages.length} messages using model: $model');
    debugPrint('Using endpoint: ${url.toString()}');
    debugPrint('Using conversation ID: $conversationId');
    
    // Build request with proper headers and body structure
    final Map<String, dynamic> requestBody = {
      'messages': processedMessages.map((msg) => {
        'role': msg.role,
        'content': msg.content,
      }).toList(),
      'stream': true,  // Explicitly set stream to true
      'conversation_id': conversationId,
    };
    
    // Only add temperature and maxTokens if they're provided
    if (temperature != null) {
      requestBody['temperature'] = temperature;
    }
    if (maxTokens != null) {
      requestBody['max_tokens'] = maxTokens;
      debugPrint('Setting max_tokens to: $maxTokens');
    }
    
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['X-Username'] = authUsername
      ..body = json.encode(requestBody);

    try {
      debugPrint('Sending request to chat endpoint with X-Username: $authUsername');
      debugPrint('Request body: ${request.body}');
      
      // Set a longer timeout for the initial connection
      final response = await _client.send(request).timeout(
        _longTimeout, 
        onTimeout: () {
          debugPrint('Request timed out while streaming chat');
          throw TimeoutException('Connection timed out. Using offline response mode.');
        }
      );
      
      if (response.statusCode != 200) {
        debugPrint('Failed to get chat response: ${response.statusCode}');
        
        // Try to read the response body for error details
        final responseBytes = await response.stream.toBytes();
        final responseString = utf8.decode(responseBytes);
        debugPrint('Error response body: $responseString');
        
        // Try to parse the error response as JSON to extract detailed error message
        try {
          final errorData = json.decode(responseString);
          if (errorData['detail'] != null) {
            yield "*ERROR_MESSAGE*${errorData['detail']}";
            return;
          }
        } catch (e) {
          // If JSON parsing fails, use the raw response
          debugPrint('Failed to parse error response as JSON: $e');
        }
        
        yield* _provideFallbackResponse("Server returned error ${response.statusCode}: $responseString");
        return;
      }

      debugPrint('Stream connection established, processing response chunks...');
      
      // Add try-catch within stream processing
      try {
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            
            // Handle SSE format where lines start with "data: "
            if (line.startsWith('data: ')) {
              final jsonString = line.substring(6); // Skip "data: " prefix
              
              // Check for error messages
              if (jsonString.contains('"error":')) {
                try {
                  final errorData = json.decode(jsonString);
                  if (errorData['error'] != null) {
                    debugPrint('Error from server: ${errorData['error']}');
                    yield "Error: ${errorData['error']}";
                    continue;
                  }
                } catch (e) {
                  debugPrint('Failed to parse error message: $e');
                }
              }
              
              try {
                final data = json.decode(jsonString);
                debugPrint('Parsed data from stream: ${jsonString.substring(0, min(50, jsonString.length))}...'); // Add debug print
                
                // First check for [DONE] special marker which signals the stream is complete
                if (jsonString.trim() == '[DONE]') {
                  debugPrint('Received [DONE] marker, ending stream normally');
                  break;
                }
                
                if (data['choices'] != null && 
                    data['choices'][0]['delta'] != null && 
                    data['choices'][0]['delta']['content'] != null) {
                  final content = data['choices'][0]['delta']['content'].toString();
                  debugPrint('Yielding content: ${content.substring(0, min(20, content.length))}...'); // Add debug print
                  yield content;
                } else if (data['choices'] != null && data['choices'].isNotEmpty) {
                  // Check for finish_reason: "stop" which indicates a normal completion
                  if (data['choices'][0]['finish_reason'] == 'stop') {
                    debugPrint('Received finish_reason: "stop", ending stream normally');
                    // Don't yield anything, just continue (the frontend will render what we have)
                    continue;
                  }
                  
                  // Log structure when delta/content is missing
                  debugPrint('Received response without content: ${json.encode(data['choices'][0])}');
                  
                  // Try alternative fields that might contain content
                  if (data['choices'][0]['message'] != null && 
                      data['choices'][0]['message']['content'] != null) {
                    yield data['choices'][0]['message']['content'].toString();
                  } else if (data['choices'][0]['text'] != null) {
                    yield data['choices'][0]['text'].toString();
                  }
                }
              } catch (e) {
                debugPrint('Error parsing JSON: $e for line: $jsonString');
              }
            } else {
              try {
                final data = json.decode(line);
                if (data['choices'] != null && 
                    data['choices'][0]['delta'] != null && 
                    data['choices'][0]['delta']['content'] != null) {
                  yield data['choices'][0]['delta']['content'].toString();
                } else if (data['choices'] != null && data['choices'].isNotEmpty) {
                  // Try alternative fields for non-SSE format
                  if (data['choices'][0]['message'] != null && 
                      data['choices'][0]['message']['content'] != null) {
                    yield data['choices'][0]['message']['content'].toString();
                  } else if (data['choices'][0]['text'] != null) {
                    yield data['choices'][0]['text'].toString();
                  }
                }
              } catch (e) {
                debugPrint('Error parsing non-SSE line: $e');
              }
            }
          }
        }
        debugPrint('Stream completed successfully');
      } catch (e) {
        debugPrint('Error while processing stream: $e');
        yield* _provideFallbackResponse("Error while processing response: $e");
      }
    } catch (e) {
      debugPrint('Error in stream chat: $e');
      yield* _provideFallbackResponse("${e.toString()}. Please try again.");
    }
  }
  
  // Non-streaming chat completion with the same endpoint
  Future<String> generateChatCompletion(
    String model,
    List<ChatMessage> messages, {
    required String userId,
    String? conversationId,
    double? temperature,
    int? maxTokens}
  ) async {
    // Debug model name validation
    debugPrint('Original model name provided to generateChatCompletion: $model');
    
    // Validate and normalize model name
    if (model.isEmpty) {
      debugPrint('ERROR: Empty model name provided to generateChatCompletion');
      throw Exception("No model selected. Please try again.");
    }
    
    // Make sure model doesn't look like a hash (conversation ID)
    if (model.length > 40 && !model.contains('-')) {
      debugPrint('WARNING: Model name appears to be a hash. Using fallback model name.');
      model = 'gpt-3.5-turbo'; // Using fallback
    }
    
    // Use currentUsername if available, otherwise fall back to userId
    final String authUsername = _currentUsername ?? userId;
    debugPrint('Generating chat completion with model: $model, conversation: $conversationId');
    
    // Fix URL construction - don't use query parameters in the URL
    // The backend expects /chat/{model_name}/generate
    final url = Uri.parse('$_baseUrl/chat/$model/generate');
    
    // Add detailed logging about the endpoint
    debugPrint('Using endpoint URL: ${url.toString()}');
    
    // Validate the message list
    if (messages.isEmpty) {
      throw Exception('Cannot generate chat completion with empty message list');
    }
    
    // Remove any assistant messages with empty content (placeholders) from the list sent to API
    final filteredMessages = messages.where((msg) => 
      !(msg.role == 'assistant' && msg.content.isEmpty)).toList();
    
    if (filteredMessages.isEmpty) {
      debugPrint('ERROR: All messages were filtered out (only empty assistant messages?)');
      throw Exception("No valid messages to send. Please try again.");
    }
    
    // Check if conversation ID is provided and valid
    if (conversationId == null || conversationId.isEmpty) {
      debugPrint('ERROR: No conversation ID provided for chat completion');
      throw Exception('No conversation ID available. Please try again.');
    }
    
    // Ensure messages are ordered properly
    final processedMessages = List<ChatMessage>.from(filteredMessages);
    processedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    
    // Log info about the request
    debugPrint('Generating chat completion with ${processedMessages.length} messages using model: $model');
    debugPrint('Using endpoint: ${url.toString()}');
    debugPrint('Using conversation ID: $conversationId');
    
    // Build the request body
    final Map<String, dynamic> requestBody = {
      'messages': processedMessages.map((msg) => {
        'role': msg.role,
        'content': msg.content,
      }).toList(),
      'stream': false,
      'conversation_id': conversationId,
    };
    
    // Only add temperature and maxTokens if they're provided
    if (temperature != null) {
      requestBody['temperature'] = temperature;
    }
    if (maxTokens != null) {
      requestBody['max_tokens'] = maxTokens;
      debugPrint('Setting max_tokens to: $maxTokens');
    }
    
    try {
      debugPrint('Sending request to chat endpoint with X-Username: $authUsername');
      debugPrint('Request body: ${json.encode(requestBody)}');
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Username': authUsername,
        },
        body: json.encode(requestBody),
      ).timeout(_longTimeout);
      
      if (response.statusCode != 200) {
        debugPrint('Failed to get chat completion: ${response.statusCode}, Body: ${response.body}');
        
        // Try to parse the error response as JSON to extract detailed error message
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            throw Exception(errorData['detail']);
          }
        } catch (e) {
          // If JSON parsing fails, use the generic error
          debugPrint('Failed to parse error response as JSON: $e');
        }
        
        throw Exception('Failed to get chat completion: ${response.statusCode}');
      }
      
      final data = json.decode(response.body);
      if (data['choices'] != null && data['choices'].isNotEmpty) {
        final content = data['choices'][0]['message']['content'];
        debugPrint('Received chat completion with ${content.length} characters');
        return content;
      }
      
      throw Exception('Invalid response format from chat completion API');
    } catch (e) {
      debugPrint('Error in chat completion: $e');
      rethrow;
    }
  }

  // Provide a fallback response when the backend is unavailable
  Stream<String> _provideFallbackResponse(String errorDetail) async* {
    // Log the error
    debugPrint('USING FALLBACK RESPONSE MODE: $errorDetail');
    
    // Report the error but mark it specially so the frontend can handle it correctly
    yield "*ERROR_MESSAGE*$errorDetail";
  }

  void dispose() {
    debugPrint('Disposing ChatService');
    _client.close();
  }
} 