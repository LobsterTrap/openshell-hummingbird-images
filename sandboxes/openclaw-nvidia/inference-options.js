/**
 * NeMoClaw — Inference options for integrate.api.nvidia.com
 *
 * Single source of truth for per-model thinking/reasoning and sampling
 * when using NVIDIA Integrate endpoints. Used by policy-proxy to inject
 * body and headers into completion requests. Model ids match CURATED_MODELS
 * and provider model identifiers (e.g. moonshotai/kimi-k2.5).
 *
 * Thinking/reasoning:
 *   - Kimi K2.5: chat_template_kwargs.thinking = true
 *   - MiniMax M2.5: thinking-only model (no extra body)
 *   - GLM 5: chat_template_kwargs.enable_thinking = true
 *   - Nemotron Super: enable_thinking + force_nonempty_content
 *   - GPT-OSS 120B: reasoning_effort = "high"
 */

/**
 * Default sampling parameters applied to all integrate.nvidia completion requests.
 * max_tokens can be set up to the model's context length; clients should retry
 * with max_tokens * 4 when finish_reason is "length" (output truncated).
 */
const DEFAULT_SAMPLING = {
  temperature: 1.0,
  top_p: 0.95,
  max_tokens: 8192,
};

/**
 * Per-model extra body to merge into the completion request.
 * Keys are model ids (e.g. "moonshotai/kimi-k2.5").
 * Value is merged into the request body; chat_template_kwargs and
 * reasoning_effort are passed through to the NVIDIA API.
 */
const MODEL_EXTRA_BODY = {
  "moonshotai/kimi-k2.5": {
    chat_template_kwargs: { thinking: true },
  },
  "minimaxai/minimax-m2.5": {
    // Thinking-only model; no extra body required
  },
  "z-ai/glm5": {
    chat_template_kwargs: { enable_thinking: true },
  },
  "nvidia/nemotron-3-super": {
    chat_template_kwargs: {
      enable_thinking: true,
      force_nonempty_content: true,
    },
  },
  "openai/gpt-oss-120b": {
    reasoning_effort: "high",
  },
};

/**
 * Normalize model ref from request body to model id for lookup.
 * e.g. "curated-nvidia-endpoints/minimaxai/minimax-m2.5" -> "minimaxai/minimax-m2.5"
 */
function toModelId(modelRef) {
  if (!modelRef || typeof modelRef !== "string") return null;
  const s = modelRef.trim();
  const slash = s.indexOf("/");
  if (slash === -1) return s;
  // If it looks like "provider/modelId", take from first slash onward (may be org/model)
  const rest = s.slice(slash + 1);
  return rest || s;
}

/**
 * Get extra body (thinking/reasoning) and sampling defaults for a model.
 * @param {string} modelRef - Request body model field (e.g. full ref or model id)
 * @returns {{ extraBody: object, sampling: object }}
 */
function getInferenceOptions(modelRef) {
  const modelId = toModelId(modelRef);
  const extraBody = (modelId && MODEL_EXTRA_BODY[modelId]) ? { ...MODEL_EXTRA_BODY[modelId] } : {};
  return {
    extraBody,
    sampling: { ...DEFAULT_SAMPLING },
  };
}

/**
 * Check if this model ref is one we have inference options for (integrate.nvidia).
 */
function hasInferenceOptions(modelRef) {
  const modelId = toModelId(modelRef);
  return modelId && (modelId in MODEL_EXTRA_BODY || isNvidiaCuratedModelId(modelId));
}

/** Known curated model ids that use integrate.nvidia (for injection scope) */
const CURATED_MODEL_IDS = new Set([
  "moonshotai/kimi-k2.5",
  "minimaxai/minimax-m2.5",
  "z-ai/glm5",
  "openai/gpt-oss-120b",
  "nvidia/nemotron-3-super",
]);

/** Prefix sent in the request body model field to integrate.api.nvidia.com */
const INTEGRATE_MODEL_PREFIX = "private/openshell/";

function isNvidiaCuratedModelId(modelId) {
  return modelId && CURATED_MODEL_IDS.has(modelId);
}

/**
 * Return the model id to send to integrate.api.nvidia.com (with private/openshell/ prefix).
 * For curated models we use the prefixed form; otherwise returns null (caller keeps existing model).
 * @param {string} modelId - Short model id (e.g. "z-ai/glm5") from toModelId(modelRef)
 * @returns {string|null} - e.g. "private/openshell/z-ai/glm5" or null
 */
function getModelIdForRequest(modelId) {
  if (!modelId || !isNvidiaCuratedModelId(modelId)) return null;
  return INTEGRATE_MODEL_PREFIX + modelId;
}

module.exports = {
  DEFAULT_SAMPLING,
  INTEGRATE_MODEL_PREFIX,
  MODEL_EXTRA_BODY,
  getInferenceOptions,
  getModelIdForRequest,
  hasInferenceOptions,
  toModelId,
};
