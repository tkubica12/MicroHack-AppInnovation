# Challenge 5 (Innovation Flavor): Add AI Capabilities

This optional, open-ended challenge invites you to extend the catalog application with AI-powered experiences. You can augment the existing .NET app directly, or introduce new microservices (any language/runtime) that the current app consumes via APIs or messaging. Treat the existing application as a frontend shell if that accelerates experimentation.

Suggested innovation tracks (pick one or combine):

## 1. Product Recommendation Chatbot
- Implement a conversational assistant that can answer questions like “What’s a good space-themed set for under $50?”
- Ground answers in the existing catalog data (avoid hallucination) by using retrieval-augmented generation (RAG) with embeddings over product titles/descriptions.
- Provide clickable product links or images in responses.

## 2. Semantic Search & Browsing
- Replace (or complement) keyword search with vector similarity search over product metadata.
- Use embeddings to rank results by semantic relevance (e.g., “winter village” returns holiday sets even if not exact phrase).
- Optionally add hybrid search (text + vector) for more precise ranking.

## 3. AI-Powered Translations / Localization
- Auto-translate product titles/descriptions into selected target languages on-demand or via background batch.
- Cache translations; expose language switcher in UI.
- Consider quality evaluation or human override workflow.

## 4. Image Generation / Enhancement
- Leverage similar techniques used in `dataGenerator/` to create alternate marketing images or themed variants (e.g., “cyberpunk version”).
- Provide a prompt-driven feature inside the app that generates a hero image or banner for a chosen set.
- Clearly label AI-generated assets.

## 5. Personalized Recommendations
- Track (simulated) user interactions (views, favorites) and build a simple model (content-based or embedding similarity) to suggest “You might also like”.
- Optionally experiment with lightweight collaborative filtering if you simulate multiple users.

## Architecture & Implementation Guidance
- Start with a thin AI service that exposes REST or gRPC endpoints; keep responsibilities isolated.
- Use Azure OpenAI or other model endpoints (ensure you follow org guidelines for responsible AI and data handling).
- For vector search, leverage existing Microsoft SQL server or consider Azure AI Search, PostgreSQL pgvector or Redis vector indices.
- Store embeddings once (batch job) rather than recomputing on every query.
- Add feature flags or config switches so AI additions can be disabled cleanly.

## UX Integration Ideas
- Chat side panel with streaming responses.
- “Explain this product” button producing a friendly summary.
- Semantic search toggle (“AI Search” vs “Classic”).
- Prompt box for generating themed image / banner.

## Data & Grounding
- Use existing catalog as authoritative source; avoid fabricating unavailable products.
- Maintain traceability: show “Sources” (product IDs) under generated answers.
- Log prompts/responses (anonymized) for evaluation; consider basic guardrails (profanity filter, max tokens, banned prompts).

Ask coaches for guidance—there is no single required path. Focus on delivering one polished, useful AI capability rather than many incomplete experiments.

> Tip: Start with retrieval + grounding before adding creativity. Reliable relevance builds user trust.