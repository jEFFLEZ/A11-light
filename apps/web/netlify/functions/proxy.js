// netlify/functions/proxy.cjs
// Simple proxy A11 → Cloudflare tunnel (api.funesterie.me)

const ORIGIN = process.env.UPSTREAM_ORIGIN || 'https://api.funesterie.me';

exports.handler = async function (event, context) {
  const requestOrigin = (event.headers && (event.headers.origin || event.headers.Origin)) || '*';

  // CORS headers — reflect request origin and allow credentials
  const corsHeaders = {
    'Access-Control-Allow-Origin': requestOrigin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, CF-Access-Client-Id, CF-Access-Client-Secret, X-NEZ-TOKEN',
    'Access-Control-Allow-Credentials': 'true',
  };

  // Préflight CORS
  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 204,
      headers: corsHeaders,
      body: '',
    };
  }

  const path = event.path.replace(/^\/\.netlify\/functions\/proxy/, '') || '/';
  const url = ORIGIN + path;

  // Copy headers, excluding hop-by-hop
  const hopByHop = new Set([
    'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
    'te', 'trailers', 'transfer-encoding', 'upgrade', 'content-length'
  ]);
  const headers = {};
  for (const [k, v] of Object.entries(event.headers || {})) {
    const key = k.toLowerCase();
    if (!hopByHop.has(key)) {
      headers[k] = v;
    }
  }
  // Ensure content-type
  if (!headers['content-type']) {
    headers['content-type'] = 'application/json';
  }

  // Add Cloudflare Access headers if available
  if (process.env.CF_ACCESS_CLIENT_ID) {
    headers['CF-Access-Client-Id'] = process.env.CF_ACCESS_CLIENT_ID;
  }
  if (process.env.CF_ACCESS_CLIENT_SECRET) {
    headers['CF-Access-Client-Secret'] = process.env.CF_ACCESS_CLIENT_SECRET;
  }

  // Handle body
  let body = undefined;
  if (event.httpMethod !== 'GET' && event.httpMethod !== 'HEAD') {
    if (event.isBase64Encoded) {
      body = Buffer.from(event.body, 'base64');
    } else {
      body = event.body;
    }
  }

  try {
    const upstreamResp = await fetch(url, {
      method: event.httpMethod,
      headers,
      body,
    });

    const text = await upstreamResp.text();

    const responseHeaders = {};
    const multiValueHeaders = {};

    // Copy upstream headers except hop-by-hop; keep Set-Cookie in multiValueHeaders
    upstreamResp.headers.forEach((value, key) => {
      const k = key.toLowerCase();
      if (k === 'transfer-encoding' || k === 'content-encoding') return;
      if (k === 'set-cookie') {
        // Add Set-Cookie to multiValueHeaders to preserve cookies
        try {
          // Some runtimes expose multiple Set-Cookie via comma-separated string — normalize into array
          const cookies = Array.isArray(value) ? value : String(value).split(/, (?=[^ ;]+=)/g).filter(Boolean);
          multiValueHeaders['Set-Cookie'] = (multiValueHeaders['Set-Cookie'] || []).concat(cookies);
        } catch (e) {
          multiValueHeaders['Set-Cookie'] = (multiValueHeaders['Set-Cookie'] || []).concat([value]);
        }
        return;
      }
      responseHeaders[key] = value;
    });

    // Merge CORS headers (reflecting origin)
    Object.assign(responseHeaders, corsHeaders);

    // Return with multiValueHeaders if Set-Cookie present
    const result = {
      statusCode: upstreamResp.status,
      headers: responseHeaders,
      body: text,
    };
    if (Object.keys(multiValueHeaders).length) result.multiValueHeaders = multiValueHeaders;

    return result;
  } catch (err) {
    console.error('Proxy error:', err);
    return {
      statusCode: 502,
      headers: corsHeaders,
      body: JSON.stringify({
        error: 'proxy-failed',
        message: err && err.message ? err.message : String(err),
        target: url,
      }),
    };
  }
};