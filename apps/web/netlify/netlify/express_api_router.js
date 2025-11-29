// Minimal Express router for public and private API routes
// Usage: in your existing Express app (server.js), do:
//   const apiRouter = require('./netlify/express_api_router');
//   app.use(apiRouter);

const express = require('express');
const router = express.Router();

// CORS snippet (place near top of your server setup)
// const cors = require('cors');
// const allowed = new Set(['https://funesterie.me', 'https://www.funesterie.me']);
// app.use(cors({ origin: (origin, cb) => { if (!origin || allowed.has(origin)) return cb(null, true); return cb(new Error('Not allowed by CORS')); }, credentials: true }));

// Shim for old Netlify proxy paths (optional)
router.use('/.netlify/functions/proxy', (req, res, next) => {
  req.url = req.url.replace(/^\/\.netlify\/functions\/proxy/, '');
  next();
});

// Public endpoints (no Access required)
router.get('/', (req, res) => {
  res.type('html').send('<h1>funesterie.me</h1><p>Public landing page (placeholder)</p>');
});

router.get('/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

router.get('/api/public/hello', (req, res) => {
  res.json({ msg: 'Hello from public API', now: Date.now() });
});

// Admin UI path — the browser will be redirected to Cloudflare Access for IdP flow
router.get('/admin/*', (req, res) => {
  // in production the admin UI files should be served here; placeholder:
  res.type('html').send('<h1>Admin area</h1><p>Protected by Cloudflare Access (IdP).</p>');
});

// Private API endpoints (should be protected by Access at Cloudflare layer)
router.get('/api/private/health', (req, res) => {
  // You can still do server-side checks here if needed (e.g., verify CF-Access JWT)
  res.json({ status: 'private-ok', time: new Date().toISOString() });
});

router.get('/api/private/secret', (req, res) => {
  res.json({ secret: 'only-for-authenticated-users' });
});

module.exports = router;
