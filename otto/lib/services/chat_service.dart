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
import 'encryption_service.dart'; // Import EncryptionService

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

  static const Duration _modelCacheLifetime = Duration(minutes: 10);

  // Add EncryptionService instance
  final EncryptionService _encryptionService;

  ChatService({http.Client? client, EncryptionService? encryptionService}) :
    _baseUrl = EnvConfig.backendUrl,
    _client = client ?? http.Client(),
    _encryptionService = encryptionService ?? EncryptionService() { // Initialize EncryptionService
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

  // Helper method to get common headers for API requests
  Future<Map<String, String>> _getHeaders() async {
    return {
      'Content-Type': 'application/json; charset=utf-8', // Ensure UTF-8
      'Accept': 'application/json',
      'X-Username': _currentUsername ?? defaultObjectId,
    };
  }

  // Conversation management methods
  Future<String> createConversation() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/conversations'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Explicitly decode response body as UTF-8 before JSON decoding
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data['id'];
      } else {
        throw Exception('Failed to create conversation: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error creating conversation: $e');
      rethrow;
    }
  }

  Future<void> addMessageToConversation(String conversationId, String content, String role) async {
    try {
      // Only encrypt user messages
      Map<String, dynamic> requestBody;
      if (role == 'user') {
        try {
          final encryptedData = await _encryptionService.encryptMessage(content);
          requestBody = {
            'content': null,
            'encrypted_content': encryptedData['encrypted_content'],
            'encrypted_key': encryptedData['encrypted_key'],
            'iv': encryptedData['iv'],
            'tag': encryptedData['tag'],
            'is_encrypted': true,
            'role': role,
          };
        } catch (e) {
          debugPrint('Failed to encrypt message: $e');
          throw Exception('Failed to encrypt message: $e');
        }
      } else {
        // For non-user messages (system messages, etc.)
        throw Exception('All messages must be encrypted');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/$conversationId/messages'),
        headers: await _getHeaders(),
        body: json.encode(requestBody),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to add message: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in addMessageToConversation: $e');
      rethrow;
    }
  }

  Future<void> updateConversationTitle(String conversationId, {bool forceUpdate = false, required String userId}) async {
    try {
      debugPrint('Updating title for conversation $conversationId, force update: $forceUpdate');

      final response = await _client.put(
        Uri.parse('$_baseUrl/conversations/$conversationId/update_title'),
        headers: await _getHeaders(),
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
      debugPrint('Fetching conversations for user: $userId');

      final response = await _client.get(
        Uri.parse('$_baseUrl/conversations/list'),
        headers: await _getHeaders(),
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        // Explicitly decode response body as UTF-8 before JSON decoding
        final data = json.decode(utf8.decode(response.bodyBytes));
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
      debugPrint('Fetching conversation $conversationId for user: $userId');

      final response = await _client.get(
        Uri.parse('$_baseUrl/conversations/$conversationId/get'),
        headers: await _getHeaders(),
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        debugPrint('Successfully retrieved conversation $conversationId');
        // Explicitly decode response body as UTF-8 before JSON decoding
        return json.decode(utf8.decode(response.bodyBytes));
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
      debugPrint('Fetching messages for conversation $conversationId');

      final response = await _client.get(
        Uri.parse('$_baseUrl/conversations/$conversationId/get_messages'),
        headers: await _getHeaders(),
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        // Explicitly decode response body as UTF-8 before JSON decoding
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> messagesJson = data['messages'] ?? [];
        debugPrint('[ChatService getConversationMessages] Retrieved ${messagesJson.length} raw messages from conversation $conversationId');

        // --- E2EE Modification: Decrypt messages ---
        List<ChatMessage> messages = [];
        int successCount = 0;
        int failureCount = 0;
        for (var msgJson in messagesJson) {
          // debugPrint('[ChatService getConversationMessages] Processing raw message JSON: ${jsonEncode(msgJson)}'); // Removed raw JSON log
          try {
            ChatMessage message = ChatMessage.fromJson(msgJson);
            // debugPrint('[ChatService getConversationMessages] Parsed message ${message.id}, Role: ${message.role}, HasContent: ${message.content != null}, HasKey: ${message.encryptedKey != null}, HasIV: ${message.iv != null}, HasTag: ${message.tag != null}'); // Removed

            // Attempt decryption if the necessary fields are present (isEncrypted removed)
            if (message.content != null && message.encryptedKey != null && message.iv != null && message.tag != null) {
              try {
                // debugPrint('[ChatService getConversationMessages] Attempting to decrypt message ${message.id}'); // Removed
                // Use the individual fields directly from the ChatMessage object, using renamed 'content'
                final Map<String, String> decryptionData = {
                  'content': message.content!, // Use renamed field
                  'encrypted_key': message.encryptedKey!,
                  'iv': message.iv!,
                  'tag': message.tag!,
                };
                // debugPrint('[ChatService getConversationMessages] Prepared decryptionData for message ${message.id}'); // Removed

                final decryptedContent = await _encryptionService.decryptMessage(decryptionData);
                successCount++; // Increment success count

                // Create a new message object with decrypted content
                // Store decrypted content in the 'content' field for UI use
                // Keep original encrypted fields for potential re-encryption or debugging
                messages.add(message.copyWith(
                  content: decryptedContent, // Update content with decrypted text
                  // isEncrypted: false, // Removed
                  // encryptedContent: message.content, // Keep original encrypted data in 'content' field? No, copyWith replaces it.
                                                // We lose the original encrypted string here unless we add another field.
                                                // For now, assume UI only needs decrypted content.
                 ));
              } catch (e) {
                failureCount++; // Increment failure count
                // Keep detailed error log
                debugPrint('[ChatService getConversationMessages] Decryption FAILED for message ${message.id}: $e. Displaying placeholder.');
                // If decryption fails, add message with placeholder content
                 messages.add(message.copyWith( // Use copyWith to keep other fields
                  content: '[Decryption Failed: $e]', // Include error in placeholder
                 ));
                 /* Original placeholder logic:
                 messages.add(ChatMessage(
                  id: message.id,
                  role: message.role,
                  content: '[Decryption Failed]',
                  model: message.model,
                  timestamp: message.timestamp,
                  createdAt: message.createdAt,
                  tokenCount: message.tokenCount,
                  encryptedKey: message.encryptedKey,
                  iv: message.iv,
                  tag: message.tag,
                ));
                */
              }
            } else {
              // Keep log for unexpected cases where decryption isn't attempted
              debugPrint('[ChatService getConversationMessages] Message ${message.id} does not have required fields for decryption. Adding as is.');
              messages.add(message);
              // Consider if this should count as a failure if content was expected
              // failureCount++; 
            }
          } catch (e) {
             failureCount++; // Count processing errors as failures too
             // Keep error log
             debugPrint('[ChatService getConversationMessages] Error processing message JSON: $e. Skipping message.');
             // Optionally add a placeholder message for the skipped one
          }
        }
        // Log summary once after processing all messages
        debugPrint('[ChatService getConversationMessages] Finished processing ${messagesJson.length} messages. Decrypted: $successCount, Failed/Skipped: $failureCount');
        return messages;
        // --- End E2EE Modification ---
      }

      debugPrint('Failed to get conversation messages: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to get conversation messages: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching conversation messages: $e');
      rethrow;
    }
  }

  // --- New Method: Rename Conversation ---
  Future<void> renameConversation(String conversationId, String newTitle) async {
    try {
      debugPrint('Renaming conversation $conversationId to "$newTitle"');

      final response = await _client.put(
        Uri.parse('$_baseUrl/conversations/$conversationId/update_title'), // Correct endpoint
        headers: await _getHeaders(),
        body: json.encode({'title': newTitle}), // Correct request body key
      ).timeout(_shortTimeout);

      if (response.statusCode != 200) {
        // Try parsing error detail
        String errorDetail = 'Failed to rename conversation: ${response.statusCode}';
        try {
          // Explicitly decode response body as UTF-8 before JSON decoding
          final errorData = json.decode(utf8.decode(response.bodyBytes));
          if (errorData['detail'] != null) {
            errorDetail = 'Rename failed: ${errorData['detail']}';
          }
        } catch (_) {} // Ignore parsing errors
        debugPrint('Failed to rename conversation: ${response.statusCode}, Body: ${response.body}');
        throw Exception(errorDetail);
      }

      debugPrint('Successfully renamed conversation $conversationId');
    } catch (e) {
      debugPrint('Error renaming conversation: $e');
      rethrow; // Rethrow to be handled by ChatProvider
    }
  }
  // --- End New Method ---

  Future<void> deleteConversation(String conversationId, {required String userId}) async {
    try {
      debugPrint('Deleting conversation $conversationId');

      final response = await _client.delete(
        Uri.parse('$_baseUrl/conversations/$conversationId/delete'),
        headers: await _getHeaders(),
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
        // Explicitly decode response body as UTF-8 before JSON decoding
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes))['data'];
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
    if (model.isEmpty) {
      debugPrint('ERROR: Empty model name provided to streamChat');
      yield* _provideFallbackResponse("No model selected. Please try again.");
      return;
    }

    // REMOVED HASH CHECK FALLBACK
    // if (model.length > 40 && !model.contains('-')) {
    //   debugPrint('WARNING: Model name appears to be a hash. Using fallback model name.');
    //   model = 'gpt-3.5-turbo';
    // }

    final String authUsername = _currentUsername ?? userId;
    debugPrint('Streaming chat with model: $model, conversation: $conversationId');
    debugPrint('Using authUsername: $authUsername (X-Username header)');

    final url = Uri.parse('$_baseUrl/chat/$model/generate');
    debugPrint('Using endpoint URL: ${url.toString()}');

    if (messages.isEmpty) {
      debugPrint('ERROR: Cannot stream chat with empty message list');
      yield* _provideFallbackResponse("No messages provided for chat completion. Please try again.");
      return;
    }

    final filteredMessages = messages.where((msg) =>
      !(msg.role == 'assistant' && (msg.content == null || msg.content!.isEmpty))).toList();

    if (filteredMessages.isEmpty) {
      debugPrint('ERROR: All messages were filtered out');
      yield* _provideFallbackResponse("No valid messages to send. Please try again.");
      return;
    }

    if (conversationId == null || conversationId.isEmpty) {
      debugPrint('ERROR: No conversation ID provided for chat streaming');
      yield* _provideFallbackResponse("No conversation ID available. Please try again.");
      return;
    }

    final lastMsg = filteredMessages.last;
    if (lastMsg.role != 'user') {
      debugPrint('WARNING: Last message is not from user. Role: ${lastMsg.role}');
    }

    final processedMessages = List<ChatMessage>.from(filteredMessages);
    processedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    debugPrint('Streaming chat with ${processedMessages.length} messages using model: $model');

    // Convert messages to API format, handling encryption for user messages
    final List<Map<String, dynamic>> apiMessages = [];
    try {
      apiMessages.addAll(await _prepareMessagesForRequest(processedMessages));
    } catch (e) {
       debugPrint('Error preparing messages for API: $e');
       yield* _provideFallbackResponse('Error preparing message for sending: $e');
       return;
    }


    final Map<String, dynamic> requestBody = {
      'messages': apiMessages,
      'stream': true,
      'conversation_id': conversationId,
    };

    if (temperature != null) {
      requestBody['temperature'] = temperature;
    }
    if (maxTokens != null) {
      requestBody['max_tokens'] = maxTokens;
      debugPrint('Setting max_tokens to: $maxTokens');
    }

    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json; charset=utf-8' // Ensure UTF-8
      ..headers['X-Username'] = authUsername
      ..body = json.encode(requestBody);

    http.StreamedResponse? response; // Declare response outside try block

    try {
      debugPrint('Sending request to chat endpoint with X-Username: $authUsername');

      response = await _client.send(request).timeout(
        _longTimeout,
        onTimeout: () {
          debugPrint('Request timed out while streaming chat');
          throw TimeoutException('Connection timed out. Using offline response mode.');
        }
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to get chat response: ${response.statusCode}');

        final responseBytes = await response.stream.toBytes();
        final responseString = utf8.decode(responseBytes); // Decode error response as UTF-8
        debugPrint('Error response body: $responseString');

        try {
          final errorData = json.decode(responseString);
          if (errorData['detail'] != null) {
            yield "*ERROR_MESSAGE*${errorData['detail']}";
            return;
          }
        } catch (e) {
          debugPrint('Failed to parse error response as JSON: $e');
        }

        yield* _provideFallbackResponse("Server returned error ${response.statusCode}: $responseString");
        return;
      }

      debugPrint('Stream connection established, processing response chunks...');

      // Correctly handle the stream processing within this try block
      await for (final chunk in response.stream.transform(utf8.decoder)) { // Ensure stream chunks are decoded as UTF-8
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;

          if (line.startsWith('data: ')) {
            final jsonString = line.substring(6);
            // Log the raw JSON string received before parsing - REMOVED
            // debugPrint('[ChatService streamChat] Received raw data line: $jsonString'); 

            if (jsonString.trim() == '[DONE]') {
              // Keep this log
              debugPrint('[ChatService streamChat] Received [DONE] marker, ending stream normally');
              // Break the inner loop, the outer loop will handle completion
              break;
            }

            if (jsonString.contains('"error":')) {
              try {
                final errorData = json.decode(jsonString);
                if (errorData['error'] != null) {
                  debugPrint('Error from server stream: ${errorData['error']}');
                  yield "Error: ${errorData['error']}";
                  continue; // Continue processing other lines/chunks
                }
              } catch (e) {
                debugPrint('Failed to parse error message from stream: $e');
              }
            }

            // Process the actual data chunk
            try {
              final data = json.decode(jsonString);

              // Check for the custom encrypted format from the backend using the CORRECT 'content' key
              if (data['content'] != null && // <-- CORRECTED KEY CHECK
                  data['encrypted_key'] != null &&
                  data['iv'] != null &&
                  data['tag'] != null) {
                try {
                  // debugPrint('Attempting to decrypt stream chunk...'); // Optional: reduce log noise
                  final encryptedData = {
                    'content': data['content'].toString(), // <-- Use 'content' here too
                    'encrypted_key': data['encrypted_key'].toString(),
                    'iv': data['iv'].toString(),
                    'tag': data['tag'].toString(),
                  };

                  final decryptedContent = await _encryptionService.decryptMessage(encryptedData);
                  // Minimal success log removed
                  // debugPrint('Stream chunk decrypted successfully.'); 
                  yield decryptedContent;
                } catch (e) {
                  // Keep detailed error log
                  debugPrint('[ChatService streamChat] Stream chunk decryption failed: $e');
                  yield "[Decryption Error]"; // Yield placeholder on error
                }
              // Removed incorrect 'else if (data['content'] != null)' block.
              // If the first 'if' fails, it means we are missing necessary decryption components.
              } else if (data['is_final'] == true) {
                 debugPrint('Received final chunk marker.');
                 // No content to yield for the final marker itself, just note it.
              } else if (data['content'] != null) {
                 // Keep log for this specific error case
                 debugPrint('[ChatService streamChat] Received stream chunk with "content" but missing other required decryption keys (encrypted_key, iv, tag). Cannot decrypt.');
                 yield "[Decryption Error: Missing Keys]";
              } else {
                 // Reduce logging for unexpected formats unless debugging
                 // Only log if it's not an empty object (which sometimes happens)
                 // and not the initial role object if backend sends one
                 if (data.isNotEmpty && data['role'] == null) {
                    debugPrint('Received stream chunk in unexpected format: $jsonString');
                 }
              }
            } catch (e) {
              debugPrint('Error processing JSON chunk: $e - String: $jsonString');
              // Consider yielding an error or just logging
            }
          } // End if line starts with 'data: '
        } // End for line in lines
      } // End await for chunk
      debugPrint('Stream processing loop completed successfully');

    } catch (e) {
      debugPrint('Error during stream chat request or processing: $e');
      // Yield an error message through the stream if possible
      yield* _provideFallbackResponse('Error during streaming: $e');
      // Rethrow if needed, or handle appropriately
      // rethrow;
    } finally {
       // Ensure the response stream is closed if it exists
       // Note: Closing the client might be too aggressive here if it's shared.
       // The http package usually handles stream closing.
       debugPrint('Stream chat finished or encountered an error.');
    }
  } // End streamChat method


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

    // REMOVED HASH CHECK FALLBACK
    // if (model.length > 40 && !model.contains('-')) {
    //   debugPrint('WARNING: Model name appears to be a hash. Using fallback model name.');
    //   model = 'gpt-3.5-turbo'; // Using fallback
    // }

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
      !(msg.role == 'assistant' && (msg.content == null || msg.content!.isEmpty))).toList(); // Check for null or empty

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
    final List<Map<String, dynamic>> apiMessages;
    try {
      apiMessages = await _prepareMessagesForRequest(processedMessages);
    } catch (e) {
       debugPrint('Error preparing messages for non-streaming API: $e');
       throw Exception('Error preparing message for sending: $e');
    }

    final Map<String, dynamic> requestBody = {
      'messages': apiMessages, // Use helper
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
        headers: await _getHeaders(), // Use helper to get headers
        body: json.encode(requestBody),
      ).timeout(_longTimeout);

      if (response.statusCode != 200) {
        debugPrint('Failed to get chat completion: ${response.statusCode}, Body: ${response.body}');

        // Try to parse the error response as JSON to extract detailed error message
        try {
          // Explicitly decode response body as UTF-8 before JSON decoding
          final errorData = json.decode(utf8.decode(response.bodyBytes));
          if (errorData['detail'] != null) {
            throw Exception(errorData['detail']);
          }
        } catch (e) {
          // If JSON parsing fails, use the generic error
          debugPrint('Failed to parse error response as JSON: $e');
        }

        throw Exception('Failed to get chat completion: ${response.statusCode}');
      }

      // Explicitly decode response body as UTF-8 before JSON decoding
      final data = json.decode(utf8.decode(response.bodyBytes));

      // Check the structure returned by *your* backend for non-streaming
      if (data['encrypted_content'] != null &&
          data['encrypted_key'] != null &&
          data['iv'] != null &&
          data['tag'] != null &&
          data['is_encrypted'] == true) {

        debugPrint('Received non-streaming encrypted response.');
        // --- E2EE Modification: Decrypt Non-Streaming Response ---
        try {
          debugPrint('Attempting to decrypt non-streaming response...');
          final decryptedContent = await _encryptionService.decryptMessage(
            Map<String, String>.from({
              'encrypted_content': data['encrypted_content'],
              'encrypted_key': data['encrypted_key'],
              'iv': data['iv'],
              'tag': data['tag']
            })
          );
          debugPrint('Non-streaming response decrypted successfully.');
          return decryptedContent;
        } catch (e) {
           debugPrint('Non-streaming response decryption failed: $e. Returning placeholder.');
           return '[Decryption Failed]';
           // Optionally rethrow or handle differently
           // throw Exception('Failed to decrypt response: $e');
        }
        // --- End E2EE Modification ---
      } else if (data['content'] != null && data['is_encrypted'] == false) {
         // Handle potential unencrypted responses if backend logic changes
         debugPrint('WARNING: Received unencrypted non-streaming response.');
         return data['content'].toString();
      }

      // If the response doesn't match expected encrypted or unencrypted format
      debugPrint('Invalid response format from non-streaming chat API: ${response.body}');
      throw Exception('Invalid response format from chat completion API.');

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

  // Added dispose method
  void dispose() {
    debugPrint('Disposing ChatService');
    _client.close();
  }

  // Helper method to prepare messages for API request (used by both stream and non-stream)
  // Encrypts the content of ALL messages in the list using the Server's Public Key.
  Future<List<Map<String, dynamic>>> _prepareMessagesForRequest(List<ChatMessage> messages) async {
    final apiMessages = <Map<String, dynamic>>[];

    for (var msg in messages) {
      // Get the plaintext content. For assistant messages, this is available in ChatProvider
      // after they've been decrypted for display. For user messages, it's directly available.
      final String? plaintextContent = msg.content;

      // Skip if there's absolutely no content to encrypt
      if (plaintextContent == null || plaintextContent.isEmpty) {
         debugPrint('Skipping message with null or empty plaintext content. Role: ${msg.role}.');
         continue;
      }

      try {
        // Encrypt the plaintext content using the server's public key
        final encryptedData = await _encryptionService.encryptMessage(plaintextContent);
        apiMessages.add({
          'role': msg.role,
          'content': null, // Always null when sending encrypted data
          'encrypted_content': encryptedData['encrypted_content'],
          'encrypted_key': encryptedData['encrypted_key'],
          'iv': encryptedData['iv'],
          'tag': encryptedData['tag'],
          'is_encrypted': true, // Mark as encrypted
        });
      } catch (e) {
        debugPrint('Encryption failed for message (Role: ${msg.role}) preparation: $e');
        // Decide how to handle: skip, throw? Skipping might lead to incomplete context.
        // Throwing stops the whole process. Let's throw for now to make errors visible.
        throw Exception('Failed to encrypt message (Role: ${msg.role}) for API request: $e');
      }
    }

    // Log the number of messages being sent
    debugPrint('Prepared ${apiMessages.length} messages for API request (encrypted with server key).');

    return apiMessages;
  }

  // --- New Method: Summarize Conversation ---
  Future<String?> summarizeConversation(String conversationId, List<ChatMessage> messages) async {
    debugPrint('[ChatService] summarizeConversation called for ID: $conversationId'); // Add entry log
    if (messages.isEmpty) {
      debugPrint('Cannot summarize conversation with empty messages');
      return null;
    }
    if (conversationId.isEmpty) {
      debugPrint('Cannot summarize conversation without conversation ID');
      return null;
    }

    final url = Uri.parse('$_baseUrl/conversations/$conversationId/summarize');
    debugPrint('Sending ${messages.length} messages to summarize conversation $conversationId at $url');

    try {
      // Prepare messages: Encrypt content using Server Public Key
      final List<Map<String, dynamic>> apiMessages = [];
      for (var msg in messages) {
         final String? plaintextContent = msg.content;
         if (plaintextContent == null || plaintextContent.isEmpty) {
           debugPrint('Skipping message with null/empty content during summarization prep. Role: ${msg.role}.');
           continue;
         }
         try {
           // Encrypt the plaintext content (assuming msg.content holds decrypted text here)
           final encryptedData = await _encryptionService.encryptMessage(plaintextContent);
           // Update the payload to match the backend's SummarizeRequestMessage model
           apiMessages.add({
             'role': msg.role,
             'content': encryptedData['encrypted_content'], // Use 'content' field for encrypted data
             'encrypted_key': encryptedData['encrypted_key'],
             'iv': encryptedData['iv'],
             'tag': encryptedData['tag'],
             // 'is_encrypted': true, // Removed
           });
         } catch (e) {
            debugPrint('Encryption failed for summarization message (Role: ${msg.role}): $e');
            // Fail summarization if any message fails encryption
            throw Exception('Failed to encrypt message for summarization: $e');
         }
      }

      if (apiMessages.isEmpty) {
         debugPrint('No valid messages to send for summarization after encryption prep.');
         return null;
      }

      final requestBody = json.encode({'messages': apiMessages});
      final headers = await _getHeaders();

      debugPrint('Summarization request body (encrypted): ${requestBody.substring(0, min(100, requestBody.length))}...');

      final response = await _client.put(
        url,
        headers: headers,
        body: requestBody,
      ).timeout(_longTimeout); // Use longer timeout for LLM calls

      if (response.statusCode == 200) {
        // Explicitly decode response body as UTF-8 before JSON decoding
        final data = json.decode(utf8.decode(response.bodyBytes));
        final title = data['title'] as String?;
        debugPrint('Summarization successful, received title: $title');
        return title;
      } else {
        debugPrint('Failed to summarize conversation: ${response.statusCode}, Body: ${response.body}');
        // Try to parse error detail
        try {
           // Explicitly decode response body as UTF-8 before JSON decoding
           final errorData = json.decode(utf8.decode(response.bodyBytes));
           if (errorData['detail'] != null) {
             throw Exception('Summarization failed: ${errorData['detail']}');
           }
        } catch (_) {} // Ignore JSON parsing errors
        throw Exception('Failed to summarize conversation: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error summarizing conversation: $e');
      // Rethrow to be handled by the caller (ChatProvider)
      rethrow;
    }
  }
  // --- End New Method ---

  // --- New Method: Delete All Conversations ---
  Future<Map<String, dynamic>> deleteAllConversations() async {
    if (_currentUsername == null || _currentUsername!.isEmpty) {
      throw Exception('Not authenticated or username missing');
    }
    try {
      debugPrint('Deleting all conversations for user: $_currentUsername');
      final response = await _client.delete(
        Uri.parse('$_baseUrl/conversations/me/all'), // Use the new endpoint
        headers: await _getHeaders(),
      ).timeout(_longTimeout); // Use longer timeout for potentially long operation

      if (response.statusCode == 200) {
        // Explicitly decode response body as UTF-8 before JSON decoding
        final data = json.decode(utf8.decode(response.bodyBytes));
        debugPrint('Successfully deleted all conversations: ${data['message']}');
        return data; // Return the response data (e.g., counts)
      } else {
        // Try parsing error detail
        String errorDetail = 'Failed to delete all conversations: ${response.statusCode}';
        try {
          // Explicitly decode response body as UTF-8 before JSON decoding
          final errorData = json.decode(utf8.decode(response.bodyBytes));
          if (errorData['detail'] != null) {
            errorDetail = 'Delete all failed: ${errorData['detail']}';
          }
        } catch (_) {} // Ignore parsing errors
        debugPrint('Failed to delete all conversations: ${response.statusCode}, Body: ${response.body}');
        throw Exception(errorDetail);
      }
    } catch (e) {
      debugPrint('Error deleting all conversations: $e');
      rethrow; // Rethrow to be handled by ChatProvider
    }
  }
  // --- End New Method ---

} // End of ChatService class
