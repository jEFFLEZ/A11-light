// Netlify Function (CommonJS) compatible: TTS streaming proxy to tunnel backend
const fetch = globalThis.fetch || require('node-fetch');

function corsHeaders(origin) {
  const allowed = origin || '*';
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With',
  };
}

module.exports.handler = async function (event, context) {
  try {
    const origin = event.headers && (event.headers.origin || event.headers.Origin) || '';
    const method = event.httpMethod || 'GET';

    if (method === 'OPTIONS') {
      return {
        statusCode: 204,
        headers: corsHeaders(origin),
        body: ''
      };
    }

    if (method !== 'POST') {
      return {
        statusCode: 405,
        headers: corsHeaders(origin),
        body: JSON.stringify({ error: 'Method not allowed' })
      };
    }

    // Utilise la variable d'environnement UPSTREAM_ORIGIN si présente
    const upstream = process.env.UPSTREAM_ORIGIN || 'https://api.funesterie.me';
    const targetUrl = `${upstream}/api/tts/stream`;

    const headers = {
      'Content-Type': event.headers['content-type'] || event.headers['Content-Type'] || 'application/json',
      'User-Agent': event.headers['user-agent'] || event.headers['User-Agent'] || 'Netlify-Function/1.0'
    };
    if (event.headers && (event.headers.authorization || event.headers.Authorization)) {
      headers.Authorization = event.headers.authorization || event.headers.Authorization;
    }

    console.log('[TTS Stream Proxy] Forwarding to:', targetUrl);

    const response = await fetch(targetUrl, {
      method: method,
      headers: headers,
      body: event.isBase64Encoded ? Buffer.from(event.body, 'base64') : event.body
    });

    const responseBody = await response.text();
    const responseHeaders = Object.assign({}, corsHeaders(origin), {
      'Content-Type': response.headers.get('content-type') || 'application/json',
      'Cache-Control': 'no-cache'
    });

    if (!response.ok) {
      console.error('[TTS Stream Proxy] Tunnel error:', response.status, responseBody);
      return {
        statusCode: response.status,
        headers: responseHeaders,
        body: responseBody
      };
    }

    return {
      statusCode: response.status,
      headers: responseHeaders,
      body: responseBody
    };
  } catch (err) {
    console.error('[TTS Stream Proxy] Error:', err);
    return {
      statusCode: 500,
      headers: corsHeaders((event && event.headers && (event.headers.origin || event.headers.Origin)) || ''),
      body: JSON.stringify({ error: `TTS stream proxy error: ${err.message || err}` })
    };
  }
};
