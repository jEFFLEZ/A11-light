#!/usr/bin/env node
const express = require('express');
const cors = require('cors');
const axios = require('axios');

const app = express();
app.use(express.json({ limit: '10mb' }));
app.use(cors({ origin: true, methods: ['GET','POST','OPTIONS'], allowedHeaders: ['Content-Type','Authorization','X-NEZ-TOKEN'] }));

const UPSTREAMS = {
  llama: process.env.LLAMA_BASE || 'http://127.0.0.1:8000',
  ollama: process.env.OLLAMA_BASE || 'http://127.0.0.1:11434',
  openai: (process.env.OPENAI_BASE_URL || process.env.UPSTREAM_ORIGIN || 'https://api.funesterie.me')
};

const NEZ_TOKEN = process.env.NEZ_ALLOWED_TOKEN || process.env.NEZ_TOKENS || 'nez:a11-client-funesterie-pro';
const PORT = Number(process.env.QFLUSH_ROUTER_PORT || 4545);

function messagesToPrompt(messages){
  if (!Array.isArray(messages)) return '';
  return messages.map(m => (m.role ? `${m.role}: ${String(m.content||'')}` : String(m.content||''))).join('\n\n');
}

app.post('/v1/chat/completions', async (req, res) => {
  try {
    const body = req.body || {};
    const provider = (body.provider || '').toLowerCase();
    const model = body.model || '';
    const isStreaming = !(body.stream === false || body.stream === 'false');

    // default provider selection
    let target = provider;
    if (!target) {
      if (String(model).toLowerCase().includes('ollama') || String(UPSTREAMS.ollama).includes('11434')) target = 'ollama';
      else target = 'llama';
    }

    console.log('[router] request provider=', target, 'model=', model, 'stream=', isStreaming);

    if (target === 'openai') {
      const upstreamUrl = `${UPSTREAMS.openai.replace(/\/$/, '')}/v1/chat/completions`;
      console.log('[router] proxying to OpenAI upstream', upstreamUrl);

      const upstreamRes = await axios({
        method: 'post',
        url: upstreamUrl,
        headers: { 'Content-Type': 'application/json', 'X-NEZ-TOKEN': NEZ_TOKEN },
        data: Object.assign({}, body),
        responseType: isStreaming ? 'stream' : 'json',
        timeout: 300000
      });

      if (isStreaming) {
        try { res.status(upstreamRes.status); } catch (e) {}
        const ct = upstreamRes.headers['content-type'];
        if (ct) res.setHeader('Content-Type', ct);
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        if (res.flushHeaders) try { res.flushHeaders(); } catch (e) {}

        upstreamRes.data.on('data', (c) => { try { res.write(c); } catch (e) {} });
        upstreamRes.data.on('end', () => { try { res.end(); } catch (e) {} });
        upstreamRes.data.on('error', (err) => { console.error('[router] openai stream err', err && err.message); try { res.end(); } catch (e) {} });
        return;
      }

      return res.status(upstreamRes.status).json(upstreamRes.data);
    }

    if (target === 'ollama') {
      // Ollama expects /api/generate
      const prompt = messagesToPrompt(body.messages || []);
      const upstreamUrl = `${UPSTREAMS.ollama.replace(/\/$/, '')}/api/generate`;
      const apiBody = { model: body.model || process.env.DEFAULT_MODEL || 'llama3.2:latest', prompt, stream: isStreaming };
      console.log('[router] proxying to Ollama', upstreamUrl, { model: apiBody.model, stream: apiBody.stream });

      const upstreamRes = await axios({
        method: 'post',
        url: upstreamUrl,
        headers: { 'Content-Type': 'application/json' },
        data: apiBody,
        responseType: isStreaming ? 'stream' : 'json',
        timeout: 300000
      });

      if (isStreaming) {
        try { res.status(upstreamRes.status); } catch (e) {}
        res.setHeader('Content-Type', upstreamRes.headers['content-type'] || 'text/plain');
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        if (res.flushHeaders) try { res.flushHeaders(); } catch (e) {}

        upstreamRes.data.on('data', (c) => { try { res.write(c); } catch (e) {} });
        upstreamRes.data.on('end', () => { try { res.end(); } catch (e) {} });
        upstreamRes.data.on('error', (err) => { console.error('[router] ollama stream err', err && err.message); try { res.end(); } catch (e) {} });
        return;
      }

      // Non-stream: translate Ollama response to OpenAI-compatible format
      const llamaData = upstreamRes.data || {};
      const content = String(llamaData.response || llamaData[0] || '');
      const responseData = {
        choices: [{ message: { role: 'assistant', content } }],
        usage: { prompt_tokens: llamaData.prompt_eval_count || 0, completion_tokens: llamaData.eval_count || 0, total_tokens: (llamaData.prompt_eval_count || 0) + (llamaData.eval_count || 0) }
      };
      return res.json(responseData);
    }

    if (target === 'llama') {
      // llama-server: call non-streaming then return SSE single chunk
      const upstreamUrl = `${UPSTREAMS.llama.replace(/\/$/, '')}/v1/chat/completions`;
      const upstreamBody = Object.assign({}, body, { messages: body.messages || [], stream: false });
      console.log('[router] calling llama upstream', upstreamUrl);

      const upstreamRes = await axios.post(upstreamUrl, upstreamBody, { responseType: 'json', timeout: 300000 });
      const data = upstreamRes.data || {};
      const content = data?.choices?.[0]?.message?.content || data?.choices?.[0]?.text || data?.response || '';

      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      if (res.flushHeaders) try { res.flushHeaders(); } catch (e) {}

      const chunk = { object: 'chat.completion.chunk', choices: [{ index: 0, delta: { content }, finish_reason: content ? 'stop' : null }] };
      try { res.write(`data: ${JSON.stringify(chunk)}\n\n`); } catch (e) {}
      try { res.write('data: [DONE]\n\n'); } catch (e) {}
      try { res.end(); } catch (e) {}
      return;
    }

    res.status(400).json({ error: 'unknown_provider' });
  } catch (err) {
    console.error('[router] error', err && (err.message || err.response && err.response.data));
    if (err.response && err.response.data) {
      try { return res.status(err.response.status || 502).json(err.response.data); } catch (e) {}
    }
    return res.status(500).json({ error: String(err && err.message) });
  }
});

app.get('/health', (req, res) => res.json({ ok: true, upstreams: UPSTREAMS }));

app.listen(PORT, () => console.log(`[router] QFLUSH router listening on http://127.0.0.1:${PORT}`));
