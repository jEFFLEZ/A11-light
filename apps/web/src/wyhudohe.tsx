import React from "react";
/// <reference types="vite/client" />
import {useCallback, useEffect, useRef, useState} from "react";
import { chat, type Provider } from "./lib/api";
import { speakMaleFR } from "./lib/tts";
import handleImportFiles from "./lib/importer";
import { initSpeech, startMic, stopMic } from "./lib/speech";
import SecurityPage from "./pages/Security";
import "./lib/avatar"; // Ensure global A11Avatar helper is registered
import "./lib/avatar-ui"; // Register UI listeners for avatar animation
import "./index.css";
import "./mobile.css";

type Msg = { role: "user" | "assistant"; content: string };
type Upload = { name: string; url: string; file?: File; analysis?: any; useForSearch?: boolean };

declare global { interface Window { webkitSpeechRecognition: any; SpeechRecognition: any; } }

export default function App() {
  // If path indicates security page, render that simple admin UI
  const pathname = typeof window !== 'undefined' ? window.location.pathname : '';
  const isSecurity = pathname.endsWith('/security') || pathname.endsWith('/a11/security') || pathname.includes('/security');
  if (isSecurity) {
    return <SecurityPage />;
  }

  const [messages, setMessages] = useState<Msg[]>([
    { role: "assistant", content: "Je suis AlphaOnze (A-11). Comment puis-je aider ?" },
  ]);
  const [text, setText] = useState("");
  const [uploads, setUploads] = useState<Upload[]>([]);
  const [listening, setListening] = useState(false);
  const [voiceChat, setVoiceChat] = useState(false);

  // Ajout des états pour le nindo et le modèle
  const [nindo, setNindo] = useState("Tu es AlphaOnze (A-11), un assistant IA français unique et attachant.");
  const [model, setModel] = useState("llama3");

  // new state for tts urls panel
  const [ttsUrls, setTtsUrls] = useState<string[]>([]);

  // Interim transcript state (temporary user bubble)
  const [interimText, setInterimText] = useState<string | null>(null);

  // provider state
  const [provider, setProvider] = useState<Provider>(() => {
    const saved = window.localStorage.getItem('a11.provider') as Provider | null;
    return saved || 'local';
  });
  useEffect(() => { window.localStorage.setItem('a11.provider', provider); }, [provider]);

  const scroller = useRef<HTMLDivElement>(null);
  const voiceChatRef = useRef(voiceChat);
  useEffect(() => { voiceChatRef.current = voiceChat; }, [voiceChat]);

  // Throttled scroll helper to avoid too many tiny scroll adjustments
  const lastScrollAt = useRef<number>(0);
  const SCROLL_THROTTLE_MS = 200;
  const NEAR_BOTTOM_PX = 120;
  const scrollToBottomIfNeeded = (force = false) => {
    const el = scroller.current;
    if (!el) return;
    const now = Date.now();
    if (!force && (now - lastScrollAt.current) < SCROLL_THROTTLE_MS) return;
    try {
      const distanceFromBottom = el.scrollHeight - el.clientHeight - el.scrollTop;
      if (force || distanceFromBottom < NEAR_BOTTOM_PX) {
        el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
        lastScrollAt.current = now;
      }
    } catch (e) { /* ignore */ }
  };

  const safeSetSpeaking = (speaking: boolean) => {
    try {
      const a = (globalThis as any).A11Avatar;
      if (a && typeof a.setSpeaking === 'function') a.setSpeaking(speaking);
    } catch (e) { /* ignore */ }
  };

  // Lightweight browser TTS fallback for immediate speech
  function speakBrowser(text: string) {
    try {
      if (!('speechSynthesis' in window) || !('SpeechSynthesisUtterance' in window)) return;
      const u = new (window as any).SpeechSynthesisUtterance(text);
      u.lang = 'fr-FR';
      u.rate = 1.03;
      u.pitch = 0.98;
      u.volume = 1.0;
      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(u);
    } catch (e) {
      console.warn('speakBrowser failed', e);
    }
  }

  // Liste des modèles disponibles (à adapter selon ce que tu as installé)
  const models = [
    { value: "llama3", label: "Llama 3" },
    { value: "phi3", label: "Phi-3" },
    { value: "mistral", label: "Mistral" },
    // Ajoute ici les modèles installés
  ];

  // Modifie sendMessage pour passer nindo et model
  const sendMessage = useCallback(async (message: string) => {
    console.log('[A11][SENDMESSAGE] called with:', { message, provider, nindo });
    const next: Msg[] = [...messages, { role: "user", content: message }];
    setMessages(next);
    try {
      const j = await chat(message, next, provider, nindo);
      console.log('[A11][SENDMESSAGE] chat() result:', j);
      const out =
        j?.choices?.[0]?.message?.content ??
        j?.content ??
        j?.output ??
        (typeof j === 'string' ? j : "(vide)");
      setMessages(m => [...m, { role: "assistant", content: out }]);
      try { stopMic(); setListening(false); } catch {}
      safeSetSpeaking(true);
      try {
        speakBrowser(out as string);
      } catch (e) {
        try { await speakMaleFR(out as string); } catch (err) { /* ignore */ }
      }
      safeSetSpeaking(false);
    } catch (e: any) {
      setMessages(m => [...m, { role: "assistant", content: `⚠️ Erreur API : ${(e as any)?.message || String(e)}` }]);
      console.error('[A11][SENDMESSAGE] error:', e);
    }
    try { scrollToBottomIfNeeded(); } catch {}
  }, [messages, nindo, model, provider]);

  const send = async () => {
    console.log('[A11][SEND] called, text:', text);
    const t = text.trim();
    if (!t && uploads.length === 0) return;
    const userLine = t + (uploads.length ? `\n[Fichiers: ${uploads.map(u => u.name).join(", ")}]` : "");
    setText(""); setUploads([]);
    try {
      await sendMessage(userLine);
    } catch (err) {
      console.error('[A11][SEND] Erreur lors de l\'envoi du message:', err);
      setMessages(m => [...m, { role: "assistant", content: `⚠️ Erreur d\'envoi : ${err && err.message ? err.message : err}` }]);
    }
  };

  // Voice handling
  const sendVoiceMessage = useCallback(async (txt: string) => {
    const userText = String(txt || '').trim(); if (!userText) return;
    // Add final user message to chat (sendVoiceMessage is used for final transcripts)
    setMessages(prev => [...prev, { role: 'user', content: userText }]);
    try { stopMic(); setListening(false); } catch {}
    try {
      const j = await chat(userText, [...messages, { role: 'user', content: userText }], provider, nindo);
      const out = j?.choices?.[0]?.message?.content || j?.content || '(vide)';
      setMessages(prev => [...prev, { role: 'assistant', content: out }]);
      safeSetSpeaking(true);

      try {
        speakBrowser(out as string);
      } catch (e) {
        try { await speakMaleFR(out as string); } catch {}
      }

      safeSetSpeaking(false);
      if (voiceChatRef.current) { try { await startMic(); setListening(true); } catch { setListening(false); } }
    } catch (err) {
      setMessages(prev => [...prev, { role: 'assistant', content: `⚠️ Erreur API : ${(err as any)?.message || String(err)}` }]);
    }
    try { scrollToBottomIfNeeded(); } catch {}
  }, [messages, model, nindo, provider]);

  useEffect(() => {
    try {
      // initSpeech now provides interim and final transcripts via (text, isFinal)
      initSpeech((txt: string, isFinal?: boolean) => {
        if (!voiceChatRef.current) return;
        if (!txt || txt.trim().length === 0) return;
        if (isFinal) {
          // clear interim and send final
          setInterimText(null);
          sendVoiceMessage(txt);
        } else {
          // show interim text as temporary bubble
          setInterimText(txt);
        }
      });
    } catch (e) { }
  }, [sendVoiceMessage]);

  // File import
  async function handleImportInput(list: FileList | null) {
    if (!list?.length) return; const arr: Upload[] = [];
    for (const f of Array.from(list)) arr.push({ name: f.name, url: URL.createObjectURL(f), file: f, useForSearch: true });
    setUploads(u => [...u, ...arr]);
    try { await handleImportFiles(list, (txt) => { setText(prev => (prev ? prev + "\n\n" : "") + txt); }); } catch (e) { console.warn(e); }
  }

  useEffect(() => { setUploads([]); }, [messages.length]);

  // Ajout du style de fond global cohérent
  useEffect(() => {
    document.body.style.background = '#0a0c17'; // même fond que le chat
  }, []);

  // Listen for TTS URL events emitted by tts-server
  useEffect(() => {
    const handler = (e: any) => {
      try {
        const urls = (e && e.detail && Array.isArray(e.detail.urls)) ? e.detail.urls : [];
        setTtsUrls(urls);
      } catch (err) {
        console.warn('tts:urls handler error', err);
      }
    };
    window.addEventListener('tts:urls', handler as EventListener);
    return () => window.removeEventListener('tts:urls', handler as EventListener);
  }, []);

  const playUrl = useCallback(async (raw: string) => {
    try {
      if (!raw) return;
      let src = raw;
      if (!/^https?:\/\//i.test(src)) {
        if (src.startsWith('/')) src = `${window.location.origin}${src}`;
        else src = `${window.location.origin}/${src}`;
      }
      const a = new Audio(src);
      await a.play().catch(err => { console.warn('Audio play failed', err); });
    } catch (e) {
      console.warn('playUrl error', e);
    }
  }, []);

  const clearTtsUrls = useCallback(() => setTtsUrls([]), []);

  return (
    <div style={{ maxWidth: 1200, margin: '0 auto', padding: 16 }}>
      <header className="app-header">
        <div className="brand-wrap"><span className="nossen-flame">NOSSEN</span></div>
        <div style={{marginLeft: 'auto', display: 'flex', gap: 8, alignItems: 'center'}}>
          <a href="/a11/security" style={{color:'#fff', textDecoration:'none', padding:'6px 10px', background:'#333', borderRadius:6}}>Security</a>

          {/* Provider badge */}
          <span style={{ padding: '4px 10px', borderRadius: 999, fontSize: 12, border: '1px solid rgba(255,255,255,0.2)', background: 'rgba(0, 255, 200, 0.05)' }}>
            Mode : {provider === 'local' ? 'Local (llama.cpp)' : provider === 'ollama' ? 'Ollama' : 'OpenAI'}
          </span>

          {/* Provider select */}
          <select value={provider} onChange={e => setProvider(e.target.value as Provider)} style={{ background: 'transparent', color: '#fff', borderRadius: 999, border: '1px solid rgba(255,255,255,0.2)', padding: '4px 8px', fontSize: 12 }}>
            <option value="local">Local (llama.cpp)</option>
            <option value="ollama">Ollama</option>
            <option value="openai">OpenAI</option>
          </select>

        </div>
        <div className="avatar-wrap"><img id="a11-avatar" src="/assets/a11_static.png" data-anim="/assets/A11_talking_smooth_8s.gif" width={128} height={128} alt="A11"/></div>
      </header>

      {/* Nouvelle barre d'options accessible */}
      <div className="options-bar" style={{ display: 'flex', gap: 24, alignItems: 'center', background: '#181a2a', padding: '18px 24px', borderRadius: 12, margin: '18px 0 18px 0', boxShadow: '0 2px 12px #0004' }}>
        <label style={{ color: '#fff', fontWeight: 500, fontSize: 16 }}>
          Modèle&nbsp;
          <select className="control-select" value={model} onChange={e => setModel(e.target.value)} style={{ fontSize: 16, padding: '6px 18px', borderRadius: 8, marginLeft: 4 }}>
            {models.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
          </select>
        </label>
        <label style={{ color: '#fff', fontWeight: 500, fontSize: 16, flex: 1 }}>
          Nindo / System prompt&nbsp;
          <input
            className="control-input"
            type="text"
            value={nindo}
            onChange={e => setNindo(e.target.value)}
            placeholder="Nindo / System prompt"
            style={{ fontSize: 16, padding: '6px 18px', borderRadius: 8, width: '100%', marginLeft: 4 }}
          />
        </label>
      </div>

      <main className="app-main">
        <div className="card chat">
          <div className="chat-scroll" ref={scroller} style={{ overflowAnchor: 'none' }}>
            {messages.map((m, i) => (
              <div key={`${m.role}-${i}`} className={`row ${m.role}`}>
                <div className="bubble">{m.content}</div>
              </div>
            ))}
            {uploads.length > 0 && (
              <div className="row user"><div className="bubble"><b>Pièces jointes :</b><ul style={{paddingLeft:18}}>{uploads.map(u=> <li key={u.url}><a href={u.url} target="_blank">{u.name}</a></li>)}</ul></div></div>
            )}
            {interimText && (
              <div className="row user"><div className="bubble" style={{fontStyle:'italic', opacity:0.85}}>{interimText}</div></div>
            )}
          </div>

          <div className="dock">
            <input className="input" placeholder="Écris ton message…" value={text} onChange={e=>setText(e.target.value)} onKeyDown={e=> e.key==='Enter' && send()} />
          </div>
        </div>
      </main>

      {/* TTS URLs panel for debugging/playback */}
      {ttsUrls && ttsUrls.length > 0 && (
        <div style={{ position: 'fixed', right: 16, bottom: 120, background: 'rgba(0,0,0,0.7)', color:'#fff', padding: 10, borderRadius: 8, zIndex: 9999, maxWidth: 420 }}>
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom:8 }}>
            <strong>TTS audio URLs</strong>
            <button onClick={clearTtsUrls} style={{ background:'transparent', color:'#fff', border:'none', cursor:'pointer' }}>✖</button>
          </div>
          <div style={{ display:'flex', flexDirection:'column', gap:6 }}>
            {ttsUrls.map((u,i) => (
              <div key={i} style={{ display:'flex', gap:8, alignItems:'center' }}>
                <button onClick={() => playUrl(u)} style={{ padding:'6px 8px', borderRadius:6, cursor:'pointer' }}>▶️ Play</button>
                <a href={/^https?:\/\//.test(u) ? u : (u.startsWith('/') ? `${window.location.origin}${u}` : `${window.location.origin}/${u}`)} target="_blank" rel="noreferrer" style={{ color:'#9ae6ff', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap', display:'block', maxWidth:300 }}>{u}</a>
              </div>
            ))}
          </div>
        </div>
      )}

      <nav className="bottom-bar" id="bottomBar">
        <label className="btn ghost">📎 Importer<input type="file" multiple hidden onChange={e=> handleImportInput(e.target.files)} /></label>
        <button className="btn" onClick={send}>Envoyer</button>
        <button className={`btn mic ${voiceChat? 'active' : (listening? 'on' : '')}`} title={voiceChat? 'Arrêter discussion vocale' : 'Démarrer discussion vocale'} onClick={async ()=>{
          if (voiceChat) { setVoiceChat(false); voiceChatRef.current=false; try{ stopMic(); setListening(false);}catch{} }
          else { setVoiceChat(true); voiceChatRef.current=true; try{ await startMic(); setListening(true);}catch(e){ setListening(false); console.warn(e);} }
        }}>{voiceChat? '🎧' : '🎙️'}</button>
      </nav>

    </div>
  );
}}