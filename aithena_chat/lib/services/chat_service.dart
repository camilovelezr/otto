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

  Future<List<String>> getOllamaModels() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/chat/list/ollama'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        debugPrint('Ollama models: $data');
        return data.cast<String>();
      }
      
      debugPrint('Ollama models error status: ${response.statusCode}');
      throw Exception('Failed to load Ollama models: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching Ollama models: $e');
      rethrow;
    }
  }

  Future<List<String>> getOpenAIModels() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/chat/list/openai'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        debugPrint('OpenAI models: $data');
        return data.cast<String>();
      }
      
      debugPrint('OpenAI models error status: ${response.statusCode}');
      throw Exception('Failed to load OpenAI models: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching OpenAI models: $e');
      rethrow;
    }
  }

  Future<List<String>> getGroqModels() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/chat/list/groq'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        debugPrint('Groq models: $data');
        return data.cast<String>();
      }
      
      debugPrint('Groq models error status: ${response.statusCode}');
      throw Exception('Failed to load Groq models: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching Groq models: $e');
      rethrow;
    }
  }

  Stream<String> streamChat(String model, List<ChatMessage> messages) async* {
    final url = Uri.parse('$_baseUrl/chat/$model/generate?stream=true');
    
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode(
        messages.map((msg) => {
          'role': msg.role,
          'content': msg.content,
        }).toList(),
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
          
          try {
            final data = json.decode(line);
            if (data['delta'] != null) {
              yield data['delta'].toString();
            }
          } catch (e) {
            if (line.isNotEmpty) {
              yield line;
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