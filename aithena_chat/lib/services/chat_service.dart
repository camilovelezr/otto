import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import '../models/llm_model.dart';
import 'package:dio/dio.dart';

class ChatService {
  static const String baseUrl = 'http://localhost:8000';
  final Dio _dio;

  ChatService() : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 3),
  ));

  Future<List<String>> getOllamaModels() async {
    try {
      final response = await _dio.get('/chat/list/ollama');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((model) => model.toString()).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching Ollama models: $e');
      return [];
    }
  }

  Future<List<String>> getOpenAIModels() async {
    try {
      final response = await _dio.get('/chat/list/openai');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((model) => model.toString()).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching OpenAI models: $e');
      return [];
    }
  }

  Future<List<String>> getGroqModels() async {
    try {
      final response = await _dio.get('/chat/list/groq');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        debugPrint('Groq models response: $data');
        return data.map((model) => model.toString()).toList();
      }
      debugPrint('Groq models error status: ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('Error fetching Groq models: $e');
      // Return an empty list instead of throwing to handle the error gracefully
      return [];
    }
  }

  Stream<String> streamChat(String model, List<ChatMessage> messages) async* {
    // Manually construct the URL components
    const scheme = 'http';
    const host = 'localhost';
    const port = 8000;
    final path = '/chat/$model/generate';
    
    // Construct the URL manually with query parameter
    final url = '$scheme://$host:$port$path?stream=true';
    debugPrint('Streaming chat to raw URL: $url');
    
    // Format messages as expected by the API
    final formattedMessages = messages.map((msg) => {
      'role': msg.role,
      'content': msg.content,
    }).toList();
    
    debugPrint('Sending messages: ${json.encode(formattedMessages)}');
    
    // Create request with the raw URL
    final request = http.Request('POST', Uri.parse(url))
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode(formattedMessages);

    try {
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        debugPrint('Error response: ${response.statusCode}');
        throw Exception('Failed to get chat response: ${response.statusCode}');
      }

      await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.isEmpty) continue;
        try {
          debugPrint('Received chunk: $chunk');
          final data = json.decode(chunk);
          if (data['delta'] != null) {
            // The delta field contains the new content for this chunk
            yield data['delta'];
          }
        } catch (e) {
          debugPrint('Error parsing chunk: $e');
        }
      }
    } catch (e) {
      debugPrint('Error in stream chat: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }
} 