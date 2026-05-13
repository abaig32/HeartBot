import { useState, useRef, useEffect } from "react";

const API_URL = import.meta.env.VITE_API_URL || "PLACEHOLDER_API_URL";

const DISCLAIMER =
  "HeartBot provides general cardiac health information only. It is not a substitute for professional medical advice, diagnosis, or treatment. Always consult a qualified healthcare provider for medical concerns.";

function formatSources(citations) {
  if (!citations || citations.length === 0) return [];
  const sources = [];
  for (const citation of citations) {
    const refs = citation.retrievedReferences || [];
    for (const ref of refs) {
      const uri = ref?.location?.s3Location?.uri || "";
      if (uri) {
        const filename = uri.split("/").pop().replace(/\.[^/.]+$/, "").replace(/_/g, " ");
        sources.push({ uri, label: filename });
      }
    }
  }
  return sources;
}

function renderMarkdown(text) {
  return text
    .replace(/^### (.*?)$/gm, "<strong>$1</strong>")
    .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>")
    .replace(/\*(.*?)\*/g, "<em>$1</em>")
    .replace(/\n/g, "<br/>");
}

function TypingIndicator() {
  return (
    <div className="message bot">
      <div className="avatar">
        <HeartIcon />
      </div>
      <div className="bubble typing-bubble">
        <span className="dot" />
        <span className="dot" />
        <span className="dot" />
      </div>
    </div>
  );
}

function HeartIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" />
    </svg>
  );
}

function Message({ msg }) {
  const [open, setOpen] = useState(false);
  const isBot = msg.role === "assistant";

  return (
    <div className={`message ${isBot ? "bot" : "user"}`}>
      {isBot && (
        <div className="avatar">
          <HeartIcon />
        </div>
      )}
      <div className="bubble-wrap">
        <div className={`bubble ${isBot ? "bot-bubble" : "user-bubble"}`}>
         <p dangerouslySetInnerHTML={{ __html: renderMarkdown(msg.content) }} />
        </div>
        {isBot && msg.sources && msg.sources.length > 0 && (
          <div className="sources-wrap">
            <button className="sources-toggle" onClick={() => setOpen(!open)}>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" style={{ marginRight: 5 }}>
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm-1 1.5L18.5 9H13V3.5zM6 20V4h5v7h7v9H6z" />
              </svg>
              {msg.sources.length} source{msg.sources.length > 1 ? "s" : ""}
              <svg
                width="10"
                height="10"
                viewBox="0 0 24 24"
                fill="currentColor"
                style={{ marginLeft: 5, transform: open ? "rotate(180deg)" : "rotate(0deg)", transition: "transform 0.2s" }}
              >
                <path d="M7 10l5 5 5-5z" />
              </svg>
            </button>
            {open && (
              <div className="sources-list">
                {msg.sources.map((s, i) => (
                  <div key={i} className="source-item">
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor" style={{ flexShrink: 0, opacity: 0.5 }}>
                      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" stroke="currentColor" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                    <span>{s.label}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export default function App() {
  const [messages, setMessages] = useState([
    {
      role: "assistant",
      content: "Hello, I'm HeartBot. I can help answer questions about cardiac health, heart conditions, symptoms, and general heart wellness. How can I help you today?",
      sources: [],
    },
  ]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, loading]);

  async function send() {
    const text = input.trim();
    if (!text || loading) return;

    setMessages((prev) => [...prev, { role: "user", content: text, sources: [] }]);
    setInput("");
    setLoading(true);

    try {
      const res = await fetch(API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: text }),
      });

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();

      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content: data.answer || "I wasn't able to find an answer to that. Please try rephrasing your question.",
          sources: formatSources(data.citations || []),
        },
      ]);
    } catch {
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content: "Something went wrong connecting to HeartBot. Please check your connection and try again.",
          sources: [],
        },
      ]);
    } finally {
      setLoading(false);
      inputRef.current?.focus();
    }
  }

  function handleKey(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  }

  return (
    <>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600&family=DM+Serif+Display&display=swap');

        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

        :root {
          --bg: #f7f6f3;
          --surface: #ffffff;
          --border: #e8e6e0;
          --text-primary: #1a1917;
          --text-secondary: #6b6963;
          --text-muted: #9c9890;
          --accent: #c1392b;
          --accent-soft: #fdf1f0;
          --accent-border: #f0c4c0;
          --bot-bg: #ffffff;
          --user-bg: #1a1917;
          --user-text: #f7f6f3;
          --shadow-sm: 0 1px 3px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04);
          --shadow-md: 0 4px 12px rgba(0,0,0,0.08), 0 2px 4px rgba(0,0,0,0.04);
          --radius: 16px;
          --radius-sm: 8px;
        }

        html, body, #root {
          height: 100%;
          font-family: 'DM Sans', sans-serif;
          background: var(--bg);
          color: var(--text-primary);
          -webkit-font-smoothing: antialiased;
        }

        .app {
          display: flex;
          flex-direction: column;
          height: 100%;
          max-width: 780px;
          margin: 0 auto;
        }

        /* Header */
        .header {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 20px 24px 18px;
          border-bottom: 1px solid var(--border);
          background: var(--surface);
          flex-shrink: 0;
        }

        .header-icon {
          width: 38px;
          height: 38px;
          background: var(--accent);
          border-radius: 10px;
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          flex-shrink: 0;
        }

        .header-text h1 {
          font-family: 'DM Serif Display', serif;
          font-size: 20px;
          font-weight: 400;
          color: var(--text-primary);
          letter-spacing: -0.3px;
        }

        .header-text p {
          font-size: 12px;
          color: var(--text-muted);
          margin-top: 1px;
          font-weight: 400;
        }

        .status-dot {
          width: 7px;
          height: 7px;
          background: #22c55e;
          border-radius: 50%;
          margin-left: auto;
          flex-shrink: 0;
        }

        /* Disclaimer banner */
        .disclaimer {
          padding: 10px 24px;
          background: var(--accent-soft);
          border-bottom: 1px solid var(--accent-border);
          font-size: 11.5px;
          color: var(--accent);
          line-height: 1.5;
          flex-shrink: 0;
          font-weight: 400;
        }

        /* Messages */
        .messages {
          flex: 1;
          overflow-y: auto;
          padding: 24px 20px;
          display: flex;
          flex-direction: column;
          gap: 20px;
          scroll-behavior: smooth;
        }

        .messages::-webkit-scrollbar { width: 4px; }
        .messages::-webkit-scrollbar-track { background: transparent; }
        .messages::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }

        .message {
          display: flex;
          align-items: flex-start;
          gap: 10px;
          animation: fadeUp 0.2s ease;
        }

        @keyframes fadeUp {
          from { opacity: 0; transform: translateY(6px); }
          to   { opacity: 1; transform: translateY(0); }
        }

        .message.user {
          flex-direction: row-reverse;
        }

        .avatar {
          width: 32px;
          height: 32px;
          background: var(--accent-soft);
          border: 1px solid var(--accent-border);
          border-radius: 9px;
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--accent);
          flex-shrink: 0;
          margin-top: 2px;
        }

        .bubble-wrap {
          display: flex;
          flex-direction: column;
          gap: 6px;
          max-width: 72%;
        }

        .message.user .bubble-wrap {
          align-items: flex-end;
        }

        .bubble {
          padding: 12px 16px;
          border-radius: var(--radius);
          font-size: 14.5px;
          line-height: 1.65;
          font-weight: 400;
        }

        .bot-bubble {
          background: var(--bot-bg);
          border: 1px solid var(--border);
          box-shadow: var(--shadow-sm);
          border-radius: 4px var(--radius) var(--radius) var(--radius);
          color: var(--text-primary);
        }

        .user-bubble {
          background: var(--user-bg);
          color: var(--user-text);
          border-radius: var(--radius) 4px var(--radius) var(--radius);
        }

        .bubble p { margin: 0; }

        /* Typing indicator */
        .typing-bubble {
          background: var(--bot-bg);
          border: 1px solid var(--border);
          box-shadow: var(--shadow-sm);
          border-radius: 4px var(--radius) var(--radius) var(--radius);
          padding: 14px 18px;
          display: flex;
          align-items: center;
          gap: 5px;
        }

        .dot {
          width: 6px;
          height: 6px;
          background: var(--text-muted);
          border-radius: 50%;
          animation: bounce 1.2s ease-in-out infinite;
        }
        .dot:nth-child(2) { animation-delay: 0.2s; }
        .dot:nth-child(3) { animation-delay: 0.4s; }

        @keyframes bounce {
          0%, 60%, 100% { transform: translateY(0); opacity: 0.4; }
          30% { transform: translateY(-5px); opacity: 1; }
        }

        /* Sources */
        .sources-wrap {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .sources-toggle {
          display: inline-flex;
          align-items: center;
          background: none;
          border: 1px solid var(--border);
          border-radius: 6px;
          padding: 4px 10px;
          font-size: 11.5px;
          font-family: 'DM Sans', sans-serif;
          color: var(--text-secondary);
          cursor: pointer;
          transition: all 0.15s;
          font-weight: 500;
        }

        .sources-toggle:hover {
          background: var(--bg);
          color: var(--text-primary);
          border-color: var(--text-muted);
        }

        .sources-list {
          display: flex;
          flex-direction: column;
          gap: 3px;
          padding: 6px 0 2px;
          animation: fadeUp 0.15s ease;
        }

        .source-item {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11.5px;
          color: var(--text-secondary);
          text-transform: capitalize;
          padding: 2px 0;
        }

        /* Input area */
        .input-area {
          padding: 16px 20px 20px;
          border-top: 1px solid var(--border);
          background: var(--surface);
          flex-shrink: 0;
        }

        .input-row {
          display: flex;
          align-items: flex-end;
          gap: 10px;
          background: var(--bg);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 10px 12px 10px 16px;
          transition: border-color 0.15s, box-shadow 0.15s;
        }

        .input-row:focus-within {
          border-color: var(--text-muted);
          box-shadow: 0 0 0 3px rgba(26,25,23,0.05);
        }

        .input-row textarea {
          flex: 1;
          border: none;
          background: transparent;
          font-family: 'DM Sans', sans-serif;
          font-size: 14px;
          color: var(--text-primary);
          resize: none;
          outline: none;
          line-height: 1.5;
          max-height: 120px;
          min-height: 22px;
          height: 22px;
          overflow-y: auto;
        }

        .input-row textarea::placeholder {
          color: var(--text-muted);
        }

        .send-btn {
          width: 34px;
          height: 34px;
          background: var(--user-bg);
          border: none;
          border-radius: 9px;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          color: white;
          flex-shrink: 0;
          transition: opacity 0.15s, transform 0.1s;
        }

        .send-btn:disabled {
          opacity: 0.3;
          cursor: default;
          transform: none;
        }

        .send-btn:not(:disabled):hover {
          opacity: 0.85;
          transform: scale(1.04);
        }

        .send-btn:not(:disabled):active {
          transform: scale(0.97);
        }

        .input-hint {
          font-size: 11px;
          color: var(--text-muted);
          margin-top: 8px;
          text-align: center;
        }

        /* Responsive */
        @media (max-width: 600px) {
          .header { padding: 16px 16px 14px; }
          .disclaimer { padding: 8px 16px; }
          .messages { padding: 16px 12px; }
          .input-area { padding: 12px 12px 16px; }
          .bubble-wrap { max-width: 85%; }
        }
      `}</style>

      <div className="app">
        <header className="header">
          <div className="header-icon">
            <HeartIcon />
          </div>
          <div className="header-text">
            <h1>HeartBot</h1>
            <p>Cardiac Health Assistant</p>
          </div>
          <div className="status-dot" title="Online" />
        </header>

        <div className="disclaimer">{DISCLAIMER}</div>

        <div className="messages">
          {messages.map((msg, i) => (
            <Message key={i} msg={msg} />
          ))}
          {loading && <TypingIndicator />}
          <div ref={bottomRef} />
        </div>

        <div className="input-area">
          <div className="input-row">
            <textarea
              ref={inputRef}
              value={input}
              onChange={(e) => {
                setInput(e.target.value);
                e.target.style.height = "22px";
                e.target.style.height = Math.min(e.target.scrollHeight, 120) + "px";
              }}
              onKeyDown={handleKey}
              placeholder="Ask about heart health, symptoms, or conditions…"
              disabled={loading}
              rows={1}
            />
            <button className="send-btn" onClick={send} disabled={loading || !input.trim()} aria-label="Send">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                <path d="M2 21l21-9L2 3v7l15 2-15 2z" />
              </svg>
            </button>
          </div>
          <p className="input-hint">Press Enter to send · Shift+Enter for new line</p>
        </div>
      </div>
    </>
  );
}
