import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/llm_model.dart';
import '../config/env_config.dart';
import 'dart:io' if (dart.library.js) 'package:otto/config/platform_stub.dart';

// Helper function to generate a valid MongoDB ObjectId
String generateObjectId() {
  // This creates a 24-character hex string that will pass MongoDB ObjectId validation
  final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toRadixString(16).padLeft(8, '0');
  final machineId = (123456).toRadixString(16).padLeft(6, '0'); // Replace with a random number
  final processId = (DateTime.now().microsecond % 65535).toRadixString(16).padLeft(4, '0');
  final counter = (DateTime.now().millisecondsSinceEpoch % 16777216).toRadixString(16).padLeft(6, '0');
  return timestamp + machineId + processId + counter;
}

// Default ObjectId to use when no user ID is provided
final String defaultObjectId = generateObjectId();

class ModelService {
  final String _baseUrl;
  final http.Client _client;
  
  ModelService({http.Client? client}) : 
    _baseUrl = EnvConfig.backendUrl,
    _client = client ?? http.Client();
  
  Future<List<LLMModel>> getModels({String? provider}) async {
    try {
      // Print configuration information for debugging
      debugPrint('Environment configuration: ${EnvConfig()}');
      debugPrint('Backend URL from config: ${EnvConfig.backendUrl}');
      
      // We know only /models/list is available, so use it directly
      final endpoint = '/models/list';
      // Only add provider parameter if specified, no user identification
      final String url = provider != null 
          ? '$_baseUrl$endpoint?provider=$provider'
          : '$_baseUrl$endpoint';
          
      debugPrint('Using models list endpoint: $url');
      
      // Make a completely plain call with no auth or user identification
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('Models response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          debugPrint('Models response body: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}...');
          
          if (data is List) {
            final modelsList = data.map((json) => LLMModel.fromJson(json)).toList();
            debugPrint('Parsed ${modelsList.length} models successfully');
            
            // Print out all model IDs for debugging
            if (modelsList.isNotEmpty) {
              debugPrint('Found ${modelsList.length} models from /models/list endpoint');
              modelsList.forEach((model) => debugPrint('Available model: ${model.modelId}'));
            }
            
            return modelsList;
          } else {
            debugPrint('Unexpected response format: ${response.body}');
            return [];
          }
        } catch (parseError) {
          debugPrint('Error parsing models response: $parseError');
          debugPrint('Response body: ${response.body}');
          return [];
        }
      }
      
      // Handle various error cases
      if (response.statusCode == 404) {
        debugPrint('Models endpoint not found: ${response.body}');
        debugPrint('Check if the API endpoint is correct: /models/list');
        return [];
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('Authentication error when fetching models: ${response.body}');
        return [];
      }
      
      debugPrint('Failed to fetch models: ${response.statusCode} - ${response.body}');
      return [];
    } catch (e) {
      debugPrint('Error fetching models: $e');
      return [];
    }
  }
  
  Future<LLMModel> getModel(String modelId) async {
    try {
      debugPrint('Fetching model: $modelId');
      
      final response = await _client.get(
        Uri.parse('$_baseUrl/models/$modelId'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Username': defaultObjectId,
        },
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('Model response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        return LLMModel.fromJson(json.decode(response.body));
      }
      
      throw Exception('Failed to fetch model: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Error fetching model: $e');
      rethrow;
    }
  }
  
  Future<LLMModel> updateModel(LLMModel model) async {
    try {
      final response = await _client.put(
        Uri.parse('$_baseUrl/models/${model.modelId}'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Username': defaultObjectId,
        },
        body: json.encode({
          'max_input_tokens': model.maxInputTokens,
          'max_output_tokens': model.maxOutputTokens,
          'input_price_per_token': model.inputPricePerToken,
          'output_price_per_token': model.outputPricePerToken,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return LLMModel.fromJson(json.decode(response.body));
      }
      
      throw Exception('Failed to update model: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Error updating model: $e');
      rethrow;
    }
  }
  
  Future<List<LLMModel>> syncModels({String? userId, String? username}) async {
    debugPrint('Syncing models is redirected to use only /models/list endpoint');
    
    // As per backend requirements, only use the /models/list endpoint with no auth or user info
    try {
      debugPrint('Using only the /models/list endpoint as directed (plain call with no user info)');
      
      // Ignore any provided user identification parameters - don't send them
      if (userId != null && !userId.isEmpty) {
        debugPrint('Note: userId $userId was provided but will not be used');
      }
      if (username != null && !username.isEmpty) {
        debugPrint('Note: username $username was provided but will not be used');
      }
      
      // Simply call getModels which makes a plain call without user identification
      return await getModels();
    } catch (e) {
      debugPrint('Error fetching models: $e');
      return [];
    }
  }
  
  void dispose() {
    _client.close();
  }
} 