import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/llm_model.dart';
import '../config/env_config.dart';
import 'dart:io' if (dart.library.js) 'package:otto/config/platform_stub.dart';

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
      
      // Since we know the correct endpoint, try it first and directly
      final directUrl = provider != null 
          ? '$_baseUrl/models/list?provider=$provider'
          : '$_baseUrl/models/list';
          
      debugPrint('Directly trying the known working endpoint: $directUrl');
      
      try {
        // Try the direct endpoint first since we know it works
        final directResponse = await _client.get(
          Uri.parse(directUrl),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-Username': 'default_user',
          },
        ).timeout(const Duration(seconds: 15));
        
        debugPrint('Direct endpoint response status: ${directResponse.statusCode}');
        
        if (directResponse.statusCode == 200) {
          try {
            final data = json.decode(directResponse.body);
            if (data is List) {
              final models = data.map((json) => LLMModel.fromJson(json)).toList();
              if (models.isNotEmpty) {
                debugPrint('Found ${models.length} models from /models/list endpoint');
                return models;
              }
            }
          } catch (e) {
            debugPrint('Error parsing direct endpoint response: $e');
          }
        }
      } catch (e) {
        debugPrint('Error with direct endpoint: $e');
      }
      
      // If direct endpoint failed, now try the test endpoints as fallback
      debugPrint('Direct endpoint failed, trying alternatives...');
      
      // Test various endpoints to find the correct one
      final testEndpoints = [
        '/api/models',
        '/v1/models',
        '/llm/models'
      ];
      
      List<LLMModel>? modelsFromEndpoint;
      
      // Try each endpoint to find working one
      for (var endpoint in testEndpoints) {
        try {
          final testUrl = '$_baseUrl$endpoint';
          debugPrint('Testing endpoint: $testUrl');
          
          final testResponse = await _client.get(
            Uri.parse(testUrl),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ).timeout(const Duration(seconds: 5));
          
          debugPrint('Endpoint $endpoint response: ${testResponse.statusCode}');
          
          // If we got a successful response, try to parse it
          if (testResponse.statusCode == 200) {
            try {
              final data = json.decode(testResponse.body);
              if (data is List) {
                final models = data.map((json) => LLMModel.fromJson(json)).toList();
                if (models.isNotEmpty) {
                  debugPrint('Found working endpoint: $endpoint with ${models.length} models');
                  modelsFromEndpoint = models;
                  break; // Stop testing once we find a working endpoint
                }
              }
            } catch (e) {
              debugPrint('Error parsing response from $endpoint: $e');
            }
          }
        } catch (e) {
          debugPrint('Error testing endpoint $endpoint: $e');
        }
      }
      
      // If we found models from our endpoint testing, return them
      if (modelsFromEndpoint != null && modelsFromEndpoint.isNotEmpty) {
        return modelsFromEndpoint;
      }
      
      // If endpoint testing failed, try the original URL
      final url = provider != null 
          ? '$_baseUrl/models/list?provider=$provider'
          : '$_baseUrl/models/list';
          
      debugPrint('Falling back to original URL: $url');
      
      // Try to ping the server first to check connectivity
      try {
        debugPrint('Checking server connectivity at root endpoint: $_baseUrl');
        final pingResponse = await _client.get(
          Uri.parse(_baseUrl),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 5));
        debugPrint('Server ping response: ${pingResponse.statusCode} - ${pingResponse.body.length > 100 ? pingResponse.body.substring(0, 100) + "..." : pingResponse.body}');
      } catch (e) {
        debugPrint('Server ping failed: $e');
        // Try a different endpoint to check if the backend is accessible at all
        try {
          debugPrint('Trying alternative endpoint: $_baseUrl/health');
          final healthResponse = await _client.get(
            Uri.parse('$_baseUrl/health'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 5));
          debugPrint('Health endpoint response: ${healthResponse.statusCode}');
        } catch (e2) {
          debugPrint('Health endpoint check failed: $e2');
        }
      }
      
      // Add more comprehensive headers for potential auth issues
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Username': 'default_user', // Add username header for auth
        },
      ).timeout(const Duration(seconds: 15)); // Increase timeout
      
      debugPrint('Models response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          debugPrint('Models response body: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}...');
          
          if (data is List) {
            final modelsList = data.map((json) => LLMModel.fromJson(json)).toList();
            debugPrint('Parsed ${modelsList.length} models successfully');
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
          'X-Username': 'default_user', // Add username header for auth
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
          'X-Username': 'default_user', // Add username header for auth
        },
        body: json.encode({
          'max_input_tokens': model.maxInputTokens,
          'max_output_tokens': model.maxOutputTokens,
          'max_total_tokens': model.maxTotalTokens,
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
    try {
      debugPrint('Syncing models with backend URL: $_baseUrl');
      
      if ((userId == null || userId.isEmpty) && (username == null || username.isEmpty)) {
        debugPrint('No user information provided for model sync, using default flow');
        return getModels(); // Fall back to regular model fetch if no user info
      }
      
      // Construct the correct URL for the sync endpoint
      final uri = Uri.parse('$_baseUrl/models/sync');
      
      // Only add user_id param if it exists and is valid
      final Map<String, String> queryParams = {};
      if (userId != null && userId.isNotEmpty) {
        queryParams['user_id'] = userId;
      }
      
      final uriWithParams = uri.replace(queryParameters: queryParams);
      debugPrint('Syncing models from: $uriWithParams');
      
      // Use username for X-Username header if available, otherwise fallback to userId
      final String authUsername = username ?? userId ?? '';
      debugPrint('Using authentication username: $authUsername');
      
      // Using POST to trigger model sync with LiteLLM
      final response = await _client.post(
        uriWithParams,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Username': authUsername, // Use username for auth header
        },
      ).timeout(const Duration(seconds: 30)); // Longer timeout for sync
      
      debugPrint('Models sync response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data is List) {
            final modelsList = data.map((json) => LLMModel.fromJson(json)).toList();
            debugPrint('Synced ${modelsList.length} models successfully');
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
      
      // Handle various error statuses
      if (response.statusCode == 404) {
        debugPrint('Sync endpoint not found: ${response.body}');
        return getModels(); // Fall back to regular model fetch
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('Authentication error when syncing models: ${response.body}');
        return getModels(); // Fall back to regular model fetch
      } else if (response.statusCode == 500) {
        debugPrint('Server error when syncing models: ${response.body}');
        return getModels(); // Fall back to regular model fetch
      }
      
      debugPrint('Failed to sync models: ${response.statusCode} - ${response.body}');
      return getModels(); // Fall back to regular model fetch in case of errors
    } catch (e) {
      debugPrint('Error syncing models: $e');
      return getModels(); // Fall back to regular model fetch in case of exceptions
    }
  }
  
  void dispose() {
    _client.close();
  }
} 