import React, { useCallback, useEffect, useRef, useState } from "react";
/// <reference types="vite/client" />
import { chatCompletion, type Provider } from "./lib/api";
import { speakMaleFR } from "./lib/tts";
import handleImportFiles from "./lib/importer";
import { initSpeech, startMic, stopMic } from "./lib/speech";
import SecurityPage from "./pages/Security";
import "./lib/avatar";
import "./lib/avatar-ui";
import "./index.css";
import "./mobile.css";

type Msg = { role: "user" | "assistant"; content: string };
type Upload = {
  name: string;
  url: string;
  file?: File;
  analysis?: any;
  useForSearch?: boolean;
};

declare global {
  interface Window {
    webkitSpeechRecognition: any;
    SpeechRecognition: any;
  }
}

export default function App() {
  // All hooks must be called unconditionally
  const [messages, setMessages] = useState<Msg[]>([
    {
      role: "assistant",
      content: "Je suis AlphaOnze (A-11). Comment puis-je aider ?",
    },
  ]);
  const [text, setText] = useState("");
  const [uploads, setUploads] = useState<Upload[]>([]);
  const [listening, setListening] = useState(false);
  const [voiceChat, setVoiceChat] = useState(false);
  const [nindo, setNindo] = useState(
    "Tu es AlphaOnze (A-11), un assistant IA français unique et attachant."
  );
  const [model, setModel] = useState("llama3");
  const [ttsUrls, setTtsUrls] = useState<string[]>([]);
  const [interimText, setInterimText] = useState<string | null>(null);
  const [provider, setProvider] = useState<Provider>(() => {
    const saved = window.localStorage.getItem("a11.provider") as Provider | null;
    return saved || "local";
  });
  const [turbo, setTurbo] = useState<boolean>(() => {
    const saved = window.localStorage.getItem("a11.turbo");
    return saved === "1";
  });
  const [llmStats, setLlmStats] = useState<{
    backend: string;
    model: string;
    gpu: boolean;
    lastTps: number;
  } | null>(null);

  useEffect(() => {
    window.localStorage.setItem("a11.provider", provider);
  }, [provider]);
  useEffect(() => {
    window.localStorage.setItem("a11.turbo", turbo ? "1" : "0");
  }, [turbo]);
  // Polling des stats du LLM toutes les 4 secondes
  useEffect(() => {
    let canceled = false;
    const poll = async () => {
      try {
        const res = await fetch("/api/llm/stats", { credentials: 'include' });
        if (!res.ok) return;
        const data = await res.json();
        if (!canceled) setLlmStats(data);
      } catch {}
    };
    poll();
    const id = setInterval(poll, 4000);
    return () => {
      canceled = true;
      clearInterval(id);
    };
  }, []);

  const scroller = useRef<HTMLDivElement>(null);
  const voiceChatRef = useRef(voiceChat);
  useEffect(() => {
    voiceChatRef.current = voiceChat;
  }, [voiceChat]);
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
  const send = async () => {
    const t = text.trim();
    if (!t && uploads.length === 0) return;
    const userLine =
      t + (uploads.length ? `\n[Fichiers: ${uploads.map((u) => u.name).join(", ")}]` : "");
    const newMessages = [...messages, { role: "user", content: userLine }];
    setMessages(newMessages);
    setText("");
    setUploads([]);
    try {
      const answer = await chatCompletion(newMessages, provider, { turbo });
      setMessages([...newMessages, { role: "assistant", content: answer }]);
      try {
        stopMic();
        setListening(false);
      } catch {}
      safeSetSpeaking(true);
      try {
        await speakMaleFR(answer as string); // Piper / Siwis via backend
      } catch (e) {
        // fallback to browser TTS
        try { speakBrowser(answer as string); } catch {}
      }
      safeSetSpeaking(false);
    } catch (err) {
      setMessages((m) => [
        ...m,
        {
          role: "assistant",
          content: `⚠️ Erreur d'envoi : ${err && err.message ? err.message : err}`,
        },
      ]);
    }
    try {
      scrollToBottomIfNeeded();
    } catch {}
  };
  // Voice handling
  const sendVoiceMessage = useCallback(
    async (txt: string) => {
      const userText = String(txt || "").trim();
      if (!userText) return;
      const newMessages = [...messages, { role: "user", content: userText }];
      setMessages(newMessages);
      try {
        stopMic();
        setListening(false);
      } catch {}
      try {
        const answer = await chatCompletion(newMessages, provider, { turbo });
        setMessages([...newMessages, { role: "assistant", content: answer }]);
        safeSetSpeaking(true);
        try {
          await speakMaleFR(answer as string);
        } catch (e) {
          try { speakBrowser(answer as string); } catch {}
        }
        safeSetSpeaking(false);
        if (voiceChatRef.current) {
          try {
            await startMic();
            setListening(true);
          } catch {
            setListening(false);
          }
        }
      } catch (err) {
        setMessages((prev) => [
          ...prev,
          { role: "assistant", content: `⚠️ Erreur API : ${(err as any)?.message || String(err)}` },
        ]);
      }
      try {
        scrollToBottomIfNeeded();
      } catch {}
    },
    [messages, provider, turbo]
  );
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
    } catch (e) {}
  }, [sendVoiceMessage]);
  // File import
  async function handleImportInput(list: FileList | null) {
    if (!list?.length) return;
    const arr: Upload[] = [];
    for (const f of Array.from(list))
      arr.push({ name: f.name, url: URL.createObjectURL(f), file: f, useForSearch: true });
    setUploads((u) => [...u, ...arr]);
    try {
      await handleImportFiles(list, (txt) => {
        setText((prev) => (prev ? prev + "\n\n" : "") + txt);
      });
    } catch (e) {
      console.warn(e);
    }
  }
  useEffect(() => {
    setUploads([]);
  }, [messages.length]);
  // Ajout du style de fond global cohérent
  useEffect(() => {
    document.body.style.background = "#0a0c17"; // même fond que le chat
  }, []);
  // Listen for TTS URL events emitted by tts-server
  useEffect(() => {
    const handler = (e: any) => {
      try {
        const urls = e && e.detail && Array.isArray(e.detail.urls) ? e.detail.urls : [];
        setTtsUrls(urls);
      } catch (err) {
        console.warn("tts:urls handler error", err);
      }
    };
    window.addEventListener("tts:urls", handler as EventListener);
    return () => window.removeEventListener("tts:urls", handler as EventListener);
  }, []);
  const playUrl = useCallback(
    async (raw: string) => {
      try {
        if (!raw) return;
        let src = raw;
        if (!/^https?:\/\//i.test(src)) {
          if (src.startsWith("/")) src = `${window.location.origin}${src}`;
          else src = `${window.location.origin}/${src}`;
        }
        const a = new Audio(src);
        await a.play().catch((err) => {
          console.warn("Audio play failed", err);
        });
      } catch (e) {
        console.warn("playUrl error", e);
      }
    },
    []
  );
  const clearTtsUrls = useCallback(() => setTtsUrls([]), []);

  // Security page conditional rendering after all hooks
  const pathname = typeof window !== "undefined" ? window.location.pathname : "";
  const isSecurity =
    pathname.endsWith("/security") ||
    pathname.endsWith("/a11/security") ||
    pathname.includes("/security");
  if (isSecurity) {
    return <SecurityPage />;
  }

  return (
    <div style={{ maxWidth: 1200, margin: "0 auto", padding: 16 }}>
      <header className="top-bar">
        <div className="logo">NOSSEN</div>
        <div style={{ marginLeft: "auto", display: "flex", gap: 12, alignItems: "center" }}>
          <span style={{ padding: "4px 10px", borderRadius: 999, fontSize: 12, border: "1px solid rgba(255,255,255,0.2)", background: "rgba(0,255,200,0.06)" }}>
            Mode&nbsp;:&nbsp;
            {provider === "local"
              ? "Local (llama.cpp GPU)"
              : provider === "ollama"
              ? "Ollama"
              : "OpenAI"}
          </span>
          {llmStats && (
            <span style={{ padding: "4px 10px", borderRadius: 999, fontSize: 12, border: "1px solid rgba(255,255,255,0.2)", background: llmStats.gpu ? "rgba(0,255,100,0.08)" : "rgba(255,180,0,0.08)" }}>
              GPU&nbsp;: {llmStats.gpu ? "ON" : "OFF"} · {llmStats.lastTps ? `${llmStats.lastTps} tok/s` : "n/a"}
            </span>
          )}
          <select value={provider} onChange={e => setProvider(e.target.value as Provider)} style={{ background: "transparent", color: "#fff", borderRadius: 999, border: "1px solid rgba(255,255,255,0.3)", padding: "4px 8px", fontSize: 12 }}>
            <option value="local">Local (llama.cpp)</option>
            <option value="ollama">Ollama</option>
            <option value="openai">OpenAI</option>
          </select>
          <label style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, cursor: "pointer" }}>
            <input type="checkbox" checked={turbo} onChange={e => setTurbo(e.target.checked)} />
            Turbo
          </label>
        </div>
        <div className="avatar-wrap">
          <img id="a11-avatar" src="/assets/a11_static.png" data-anim="/assets/A11_talking_smooth_8s.gif" width={128} height={128} alt="A11" />
        </div>
      </header>
      {/* Nouvelle barre d'options accessible */}
      <div className="options-bar" style={{ display: "flex", gap: 24, alignItems: "center", background: "#181a2a", padding: "18px 24px", borderRadius: 12, margin: "18px 0 18px 0", boxShadow: "0 2px 12px #0004" }}>
        <label style={{ color: "#fff", fontWeight: 500, fontSize: 16 }}>
          Modèle&nbsp;
          <select className="control-select" value={model} onChange={(e) => setModel(e.target.value)} style={{ fontSize: 16, padding: "6px 18px", borderRadius: 8, marginLeft: 4 }}>
            {models.map((m) => (
              <option key={m.value} value={m.value}>
                {m.label}
              </option>
            ))}
          </select>
        </label>
        <label style={{ color: "#fff", fontWeight: 500, fontSize: 16, flex: 1 }}>
          Nindo / System prompt&nbsp;
          <input className="control-input" type="text" value={nindo} onChange={(e) => setNindo(e.target.value)} placeholder="Nindo / System prompt" style={{ fontSize: 16, padding: "6px 18px", borderRadius: 8, width: "100%", marginLeft: 4 }} />
        </label>
      </div>
      <main className="app-main">
        <div className="card chat">
          <div className="chat-scroll" ref={scroller} style={{ overflowAnchor: "none" }}>
            {messages.map((m, i) => (
              <div key={`${m.role}-${i}`} className={`row ${m.role}`}>
                <div className="bubble">{m.content}</div>
              </div>
            ))}
            {uploads.length > 0 && (
              <div className="row user">
                <div className="bubble">
                  <b>Pièces jointes :</b>
                  <ul style={{ paddingLeft: 18 }}>
                    {uploads.map((u) => (
                      <li key={u.url}>
                        <a href={u.url} target="_blank">
                          {u.name}
                        </a>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            )}
            {interimText && (
              <div className="row user">
                <div className="bubble" style={{ fontStyle: "italic", opacity: 0.85 }}>
                  {interimText}
                </div>
              </div>
            )}
          </div>
          <div className="dock">
            <input className="input" placeholder="Écris ton message…" value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => e.key === "Enter" && send()} />
          </div>
        </div>
      </main>
      {/* TTS URLs panel for debugging/playback */}
      {ttsUrls && ttsUrls.length > 0 && (
        <div style={{ position: "fixed", right: 16, bottom: 120, background: "rgba(0,0,0,0.7)", color: "#fff", padding: 10, borderRadius: 8, zIndex: 9999, maxWidth: 420 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
            <strong>TTS audio URLs</strong>
            <button onClick={clearTtsUrls} style={{ background: "transparent", color: "#fff", border: "none", cursor: "pointer" }}>
              ✖
            </button>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            {ttsUrls.map((u, i) => (
              <div key={i} style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <button onClick={() => playUrl(u)} style={{ padding: "6px 8px", borderRadius: 6, cursor: "pointer" }}>
                  ▶️ Play
                </button>
                <a href={/^https?:\//.test(u) ? u : u.startsWith('/') ? `${window.location.origin}${u}` : `${window.location.origin}/${u}`} target="_blank" rel="noreferrer" style={{ color: "#9ae6ff", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", display: "block", maxWidth: 300 }}>
                  {u}
                </a>
              </div>
            ))}
          </div>
        </div>
      )}
      <nav className="bottom-bar" id="bottomBar">
        <label className="btn ghost">
          📎 Importer
          <input type="file" multiple hidden onChange={(e) => handleImportInput(e.target.files)} />
        </label>
        <button className="btn" onClick={send}>
          Envoyer
        </button>
        <button className={`btn mic ${voiceChat ? "active" : listening ? "on" : ""}`} title={voiceChat ? "Arrêter discussion vocale" : "Démarrer discussion vocale"} onClick={async () => {
          if (voiceChat) {
            setVoiceChat(false);
            voiceChatRef.current = false;
            try {
              stopMic();
              setListening(false);
            } catch {}
          } else {
            setVoiceChat(true);
            voiceChatRef.current = true;
            try {
              await startMic();
              setListening(true);
            } catch (e) {
              setListening(false);
              console.warn(e);
            }
          }
        }}>
          {voiceChat ? "🎧" : "🎙️"}
        </button>
      </nav>
    </div>
  );
}