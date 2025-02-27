import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import '../config/env_config.dart';

class ChatService {
  final String _baseUrl;
  final http.Client _client;

  ChatService({http.Client? client}) : 
    _baseUrl = EnvConfig.backendUrl,
    _client = client ?? http.Client();

  Future<List<String>> getLLMModels() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/v1/models'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body)['data'];
        final List<String> modelIds = data.map((item) => item['id'] as String).toList();
        debugPrint('LLM models: $modelIds');
        return modelIds;
      }
      
      debugPrint('LLM models error status: ${response.statusCode}');
      throw Exception('Failed to load LLM models: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching LLM models: $e');
      rethrow;
    }
  }

  Stream<String> streamChat(String model, List<ChatMessage> messages) async* {
    final url = Uri.parse('$_baseUrl/v1/chat/completions');
    
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode(
        {
          'model': model,
          'messages': messages.map((msg) => {
            'role': msg.role,
            'content': msg.content,
          }).toList(),
          'stream': true,
        },
      );

    try {
      final response = await _client.send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to get chat response: ${response.statusCode}');
      }

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          // Handle SSE format where lines start with "data: "
          if (line.startsWith('data: ')) {
            final jsonString = line.substring(6); // Skip "data: " prefix
            
            // Handle [DONE] marker
            if (jsonString.trim() == '[DONE]') continue;
            
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
    } catch (e) {
      debugPrint('Error in stream chat: $e');
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }
} 