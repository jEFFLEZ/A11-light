const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

function listOnnxFiles(modelsDir) {
  const results = [];
  function walk(dir, relative = '') {
    const items = fs.readdirSync(dir, { withFileTypes: true });
    for (const it of items) {
      const rel = path.join(relative, it.name);
      const full = path.join(dir, it.name);
      if (it.isDirectory()) {
        walk(full, rel);
      } else if (it.isFile() && it.name.toLowerCase().endsWith('.onnx')) {
        results.push(rel.replace(/\\/g, '/'));
      }
    }
  }
  try {
    walk(modelsDir);
  } catch (e) {
    return [];
  }
  return results;
}

module.exports = function registerTTS(router) {
  // GET /api/tts/models -> list available models under piper/models
  router.get('/tts/models', (req, res) => {
    try {
      // baseDir should point to repository root (move up three levels)
      const baseDir = path.resolve(__dirname, '..', '..', '..');
      const modelsDir = path.join(baseDir, 'piper', 'models');
      if (!fs.existsSync(modelsDir)) return res.json({ models: [] });
      const models = listOnnxFiles(modelsDir);
      return res.json({ models });
    } catch (err) {
      console.error('[TTS][Piper] list models error', err);
      return res.status(500).json({ error: 'list_models_failed' });
    }
  });

  // POST /api/tts/piper
  router.post('/tts/piper', async (req, res) => {
    try {
      const text = String((req.body && req.body.text) || '').trim();
      if (!text) return res.status(400).json({ error: 'Missing text' });

      // baseDir should point to repository root (move up three levels)
      const baseDir = path.resolve(__dirname, '..', '..', '..');
      const piperExe = path.join(baseDir, 'piper', 'piper.exe');
      const modelsDir = path.join(baseDir, 'piper', 'models');

      // model param: optional relative path within models dir
      const requestedModel = String((req.body && req.body.model) || '').trim();
      let modelPath;
      if (requestedModel) {
        // sanitize and resolve
        const candidate = path.join(modelsDir, requestedModel);
        const resolved = path.resolve(candidate);
        if (!resolved.startsWith(path.resolve(modelsDir) + path.sep) && path.resolve(modelsDir) !== resolved) {
          console.warn('[TTS][Piper] model path outside models dir attempted:', requestedModel);
          return res.status(400).json({ error: 'invalid_model' });
        }
        modelPath = resolved;
      } else {
        // Default to siwis model
        modelPath = path.join(modelsDir, 'fr_FR-siwis-medium.onnx');
      }

      if (!fs.existsSync(piperExe)) {
        console.error('[TTS][Piper] piper.exe not found at', piperExe);
        return res.status(500).json({ error: 'piper not installed' });
      }
      if (!fs.existsSync(modelPath)) {
        console.error('[TTS][Piper] model not found at', modelPath);
        return res.status(500).json({ error: 'piper model not found', model: modelPath });
      }

      const publicDir = path.join(baseDir, 'public');
      const ttsDir = path.join(publicDir, 'tts');
      try {
        if (!fs.existsSync(publicDir)) fs.mkdirSync(publicDir, { recursive: true });
        if (!fs.existsSync(ttsDir)) fs.mkdirSync(ttsDir, { recursive: true });
      } catch (e) { /* ignore */ }

      const ts = Date.now();
      const outFileName = `tts-out-${ts}.wav`;
      const outFile = path.join(ttsDir, outFileName);

      const args = [
        '--model', modelPath,
        '--output_file', outFile
      ];

      const p = spawn(piperExe, args, {
        cwd: path.dirname(piperExe),
        stdio: ['pipe', 'ignore', 'inherit'],
        windowsHide: true
      });

      p.stdin.write(text);
      p.stdin.end();

      let responded = false;

      p.on('close', (code) => {
        if (responded) return;
        responded = true;
        if (code === 0) {
          // Ensure file exists
          if (fs.existsSync(outFile)) {
            return res.json({ success: true, audioUrl: `/tts/${outFileName}` });
          }
          return res.status(500).json({ error: 'tts_failed_no_file' });
        }
        console.error('[TTS][Piper] exited with code', code);
        return res.status(500).json({ error: 'tts_failed' });
      });

      p.on('error', (err) => {
        if (responded) return;
        responded = true;
        console.error('[TTS][Piper] spawn error', err);
        return res.status(500).json({ error: 'tts_spawn_error', message: String(err && err.message) });
      });

    } catch (err) {
      console.error('[TTS][Piper] error', err);
      try { return res.status(500).json({ error: 'tts_exception', message: String(err && err.message) }); } catch (e) {}
    }
  });
};
