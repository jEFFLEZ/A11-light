#!/usr/bin/env node
// apps/server/llm-router.cjs

const express = require('express');
const cors = require('cors');
// small dynamic import for node-fetch in CJS
const fetch = (...args) => import('node-fetch').then(({ default: fetch }) => fetch(...args));

const app = express();
app.use(express.json({ limit: '10mb' }));
app.use(cors({ origin: 'http://localhost:5173', methods: ['GET','POST','OPTIONS'], allowedHeaders: ['Content-Type','Authorization','X-NEZ-TOKEN'] }));

const UPSTREAM = {
  llama: process.env.LLAMA_BASE || 'http://127.0.0.1:8000',
  ollama: process.env.OLLAMA_BASE || 'http://127.0.0.1:11434',
  openai: (process.env.OPENAI_BASE_URL || process.env.UPSTREAM_ORIGIN || 'https://api.funesterie.me')
};

const NEZ_TOKEN = process.env.NEZ_ALLOWED_TOKEN || process.env.NEZ_TOKENS || 'nez:a11-client-funesterie-pro';

app.get('/health', (req, res) => res.json({ ok: true, service: 'llm-router', time: new Date().toISOString(), upstreams: UPSTREAM }));

app.post('/v1/chat/completions', async (req, res) => {
  try {
    const body = req.body || {};
    // Allow frontends that still send "local" to map to our llama upstream
    let provider = String(body.provider || '').toLowerCase();

    // If no explicit provider provided, try model hint to detect ollama vs llama
    if (!provider) {
      provider = String(body.model || '').toLowerCase().includes('ollama') ? 'ollama' : 'llama';
    }

    // Accept some common aliases
    if (provider === 'local') provider = 'llama';
    if (provider === 'openai-chat') provider = 'openai';

    const isStreaming = !(body.stream === false || body.stream === 'false');

    console.log('[LLM-Router] provider=', provider, 'model=', body.model, 'stream=', isStreaming);

    if (provider === 'openai') {
      const upstreamUrl = `${UPSTREAM.openai.replace(/\/$/, '')}/v1/chat/completions`;
      const upstreamRes = await fetch(upstreamUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-NEZ-TOKEN': NEZ_TOKEN },
        body: JSON.stringify(body),
      });

      res.status(upstreamRes.status);
      const ct = upstreamRes.headers.get('content-type');
      if (ct) res.setHeader('Content-Type', ct);
      upstreamRes.body.pipe(res);
      return;
    }

    if (provider === 'ollama') {
      const upstreamUrl = `${UPSTREAM.ollama.replace(/\/$/, '')}/api/generate`;
      // build prompt from messages
      const prompt = Array.isArray(body.messages) ? body.messages.map(m => (m.role ? `${m.role}: ${String(m.content||'')}` : String(m.content||''))).join('\n\n') : (body.prompt || body.input || '');
      const apiBody = { model: body.model || process.env.DEFAULT_MODEL || 'llama3.2:latest', prompt, stream: isStreaming };

      const upstreamRes = await fetch(upstreamUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(apiBody),
      });

      // If client requested streaming, pipe the upstream stream through unchanged
      if (isStreaming) {
        res.status(upstreamRes.status);
        const ct = upstreamRes.headers.get('content-type');
        if (ct) res.setHeader('Content-Type', ct);
        upstreamRes.body.pipe(res);
        return;
      }

      // Non-streaming: parse Ollama JSON and translate to OpenAI-like format
      let llamaData;
      try {
        llamaData = await upstreamRes.json();
      } catch (e) {
        const txt = await upstreamRes.text();
        console.error('[LLM-Router] Ollama non-stream parse error', e && e.message, txt.slice(0,1000));
        return res.status(502).json({ error: 'ollama_nonstream_parse_error', details: txt });
      }

      // Extract textual content. Ollama may sometimes return a JSON-encoded string containing SSE-style 'data: {...}' chunks
      let content = String(llamaData.response || llamaData[0] || '');

      // If the response itself contains JSON (stringified chunks), try to unwrap and concatenate
      try {
        const maybe = JSON.parse(content);
        if (Array.isArray(maybe)) {
          // array of chunk-like objects
          const parts = maybe.map(item => {
            const ch = item?.choices?.[0];
            if (!ch) return '';
            return (ch.delta && ch.delta.content) ? String(ch.delta.content) : (ch.message && ch.message.content) ? String(ch.message.content) : '';
          });
          content = parts.join('');
        } else if (maybe && maybe.choices) {
          const parts = maybe.choices.map(ch => {
            return (ch.delta && ch.delta.content) ? String(ch.delta.content) : (ch.message && ch.message.content) ? String(ch.message.content) : '';
          });
          content = parts.join('');
        } else if (maybe && typeof maybe.response === 'string') {
          content = String(maybe.response);
        }
      } catch (e) {
        // not JSON — leave content as-is
      }

      const responseData = {
        choices: [ { message: { role: 'assistant', content } } ],
        usage: {
          prompt_tokens: llamaData.prompt_eval_count || 0,
          completion_tokens: llamaData.eval_count || 0,
          total_tokens: (llamaData.prompt_eval_count || 0) + (llamaData.eval_count || 0)
        }
      };

      res.setHeader('Content-Type', 'application/json');
      return res.json(responseData);
    }

    if (provider === 'llama') {
      const upstreamUrl = `${UPSTREAM.llama.replace(/\/$/, '')}/v1/chat/completions`;
      const upstreamBody = Object.assign({}, body, { messages: body.messages || [], stream: false });
      const upstreamRes = await fetch(upstreamUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(upstreamBody),
      });

      if (!upstreamRes.ok) {
        const t = await upstreamRes.text();
        console.error('[LLM-Router] llama upstream error', upstreamRes.status, t);
        return res.status(502).json({ error: 'llama upstream error', details: t });
      }

      const json = await upstreamRes.json();
      const text = json?.choices?.[0]?.message?.content || json?.choices?.[0]?.text || json?.response || '';

      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      if (res.flushHeaders) try { res.flushHeaders(); } catch (e) {}

      const chunk = { object: 'chat.completion.chunk', choices: [{ index: 0, delta: { content: text }, finish_reason: text ? 'stop' : null }] };
      try { res.write(`data: ${JSON.stringify(chunk)}\n\n`); } catch (e) {}
      try { res.write('data: [DONE]\n\n'); } catch (e) {}
      try { res.end(); } catch (e) {}
      return;
    }

    res.status(400).json({ error: 'unknown_provider' });
  } catch (err) {
    console.error('[LLM-Router] crash', err && (err.message || err));
    if (err && err.response) {
      try { const t = await err.response.text(); return res.status(err.response.status || 502).json({ error: t }); } catch (e) {}
    }
    res.status(500).json({ error: String(err && err.message) });
  }
});

const PORT = Number(process.env.LLM_ROUTER_PORT || 4545);
app.listen(PORT, () => console.log(`[LLM-Router] listening on http://127.0.0.1:${PORT}`));
