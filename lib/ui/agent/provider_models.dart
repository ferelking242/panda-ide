library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/broken_icons.dart';

// Provider definitions for agent settings
// Extracted from agent_settings.dart

class ProviderDef {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String docsUrl;
  final bool hasApiKey;
  final String apiKeyHint;

  const ProviderDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.docsUrl,
    this.hasApiKey = true,
    this.apiKeyHint = 'sk-...',
  });
}

const providerDefs = <ProviderDef>[
  ProviderDef(
    id: 'openai',
    name: 'OpenAI',
    description: 'GPT-4o, o1, o3 — le plus utilisé',
    icon: Broken.global,
    color: Color(0xff10a37f),
    docsUrl: 'https://platform.openai.com/api-keys',
    apiKeyHint: 'sk-...',
  ),
  ProviderDef(
    id: 'claude',
    name: 'Anthropic (Claude)',
    description: 'Claude 3.5 Sonnet, Haiku, Opus',
    icon: Broken.cpu,
    color: Color(0xffb87333),
    docsUrl: 'https://console.anthropic.com/settings/keys',
    apiKeyHint: 'sk-ant-...',
  ),
  ProviderDef(
    id: 'gemini',
    name: 'Google Gemini',
    description: 'Gemini 2.5 Flash, 2.5 Pro',
    icon: Broken.global_search,
    color: Color(0xff4285f4),
    docsUrl: 'https://aistudio.google.com/app/apikey',
    apiKeyHint: 'AIza...',
  ),
  ProviderDef(
    id: 'deepseek',
    name: 'DeepSeek',
    description: 'DeepSeek-V3, R1 — très bon rapport qualité/coût',
    icon: Broken.search_normal,
    color: Color(0xff4b6ef5),
    docsUrl: 'https://platform.deepseek.com/api_keys',
    apiKeyHint: 'sk-...',
  ),
  ProviderDef(
    id: 'grok',
    name: 'Grok (xAI)',
    description: 'Grok-2, Grok Beta',
    icon: Broken.code_circle,
    color: Color(0xff1da1f2),
    docsUrl: 'https://console.x.ai/',
    apiKeyHint: 'xai-...',
  ),
  ProviderDef(
    id: 'openrouter',
    name: 'OpenRouter',
    description: 'Accès unifié à 200+ modèles',
    icon: Broken.routing_2,
    color: Color(0xff8b5cf6),
    docsUrl: 'https://openrouter.ai/keys',
    apiKeyHint: 'sk-or-...',
  ),
  ProviderDef(
    id: 'mistral',
    name: 'Mistral AI',
    description: 'Mistral Large, Codestral',
    icon: Broken.wind,
    color: Color(0xffff7000),
    docsUrl: 'https://console.mistral.ai/api-keys',
    apiKeyHint: '...',
  ),
  ProviderDef(
    id: 'togetherai',
    name: 'Together AI',
    description: 'Llama, Mixtral et autres open-source',
    icon: Broken.people,
    color: Color(0xff00c9b1),
    docsUrl: 'https://api.together.xyz/settings/api-keys',
    apiKeyHint: '...',
  ),
  ProviderDef(
    id: 'perplexity',
    name: 'Perplexity',
    description: 'Sonar — recherche web intégrée',
    icon: Broken.search_zoom_in,
    color: Color(0xff20b2aa),
    docsUrl: 'https://www.perplexity.ai/settings/api',
    apiKeyHint: 'pplx-...',
  ),
  ProviderDef(
    id: 'pandagateway',
    name: 'Panda Gateway',
    description: 'Accès unifié sans clé API (abonnement Panda)',
    icon: Broken.cpu_setting,
    color: Color(0xff5090c8),
    docsUrl: '',
    hasApiKey: false,
    apiKeyHint: 'optionnel',
  ),
  ProviderDef(
    id: 'copilot',
    name: 'GitHub Copilot',
    description: 'GPT-4o via votre abonnement GitHub Copilot',
    icon: Broken.message_programming,
    color: Color(0xff8b5cf6),
    docsUrl: 'https://github.com/settings/copilot',
    hasApiKey: false,
    apiKeyHint: 'optionnel',
  ),
  ProviderDef(
    id: 'groq',
    name: 'Groq',
    description: 'Llama 3, Mixtral — ultra-rapide (inference cloud)',
    icon: Broken.flash_circle,
    color: Color(0xfff97316),
    docsUrl: 'https://console.groq.com/keys',
    apiKeyHint: 'gsk_...',
  ),
  ProviderDef(
    id: 'fireworks',
    name: 'Fireworks AI',
    description: 'Llama, Mistral, DeepSeek — inference rapide',
    icon: Broken.flash_1,
    color: Color(0xffef4444),
    docsUrl: 'https://fireworks.ai/account/api-keys',
    apiKeyHint: 'fw_...',
  ),
  ProviderDef(
    id: 'cohere',
    name: 'Cohere',
    description: 'Command R+, Command A — spécialisé RAG',
    icon: Broken.diagram,
    color: Color(0xff39d353),
    docsUrl: 'https://dashboard.cohere.com/api-keys',
    apiKeyHint: '...',
  ),
  ProviderDef(
    id: 'cerebras',
    name: 'Cerebras',
    description: 'Llama sur wafer silicon — le plus rapide du marché',
    icon: Broken.cpu,
    color: Color(0xffa855f7),
    docsUrl: 'https://cloud.cerebras.ai/',
    apiKeyHint: 'csk-...',
  ),
  ProviderDef(
    id: 'novita',
    name: 'Novita AI',
    description: 'Llama, Mistral, DeepSeek — 200+ modèles',
    icon: Broken.global,
    color: Color(0xff06b6d4),
    docsUrl: 'https://novita.ai/settings#key-management',
    apiKeyHint: '...',
  ),
  ProviderDef(
    id: 'hyperbolic',
    name: 'Hyperbolic',
    description: 'Llama, DeepSeek — inference GPU économique',
    icon: Broken.flash_circle,
    color: Color(0xffe11d48),
    docsUrl: 'https://app.hyperbolic.xyz/settings',
    apiKeyHint: 'eyJ...',
  ),
  ProviderDef(
    id: 'custom',
    name: 'Custom / Local',
    description: 'Endpoint OpenAI-compatible (Ollama, LM Studio…)',
    icon: Broken.code_1,
    color: Color(0xff888888),
    docsUrl: '',
    apiKeyHint: 'optionnel',
  ),
];

