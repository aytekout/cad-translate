;;; ============================================================
;;; CAD-TRANSLATE.LSP
;;; AutoCAD DWG Text Translator
;;; 
;;; Translates Japanese (or other CJK) text in DWG drawings
;;; to English using a local or cloud AI provider.
;;;
;;; Supports:
;;;   - macOS and Windows
;;;   - LM Studio (local)
;;;   - Ollama (local)
;;;   - OpenAI / Anthropic / any OpenAI-compatible API
;;;
;;; Commands:
;;;   CADTRANSLATE  - scan, translate, apply
;;;   CADAPPLY      - apply an existing jpt_output.json
;;;
;;; GitHub: https://github.com/YOUR_USERNAME/cad-translate
;;; License: MIT
;;; ============================================================

;;; ============================================================
;;; OS DETECTION
;;; ============================================================

(defun get-os (/ os-env)
  ;; Returns "windows" or "mac"
  (setq os-env (getenv "OS"))
  (if (and os-env (vl-string-search "Windows" os-env 0))
    "windows"
    "mac"
  )
)

(defun is-windows ()
  (= (get-os) "windows")
)

;;; ============================================================
;;; PATH UTILITIES
;;; ============================================================

(defun get-dwg-dir (/ d sep)
  (setq d (getvar "DWGPREFIX"))
  (setq sep (if (is-windows) "\\" "/"))
  (if (or (null d) (= d ""))
    (if (is-windows)
      (setq d (strcat (getenv "USERPROFILE") "\\Downloads\\"))
      (setq d (strcat (getenv "HOME") "/Downloads/"))
    )
  )
  ;; Ensure trailing separator
  (if (/= (substr d (strlen d) 1) sep)
    (setq d (strcat d sep))
  )
  d
)

(defun path-join (dir file)
  ;; Join directory and filename cross-platform
  (strcat dir file)
)

;;; ============================================================
;;; BROWSER LAUNCHER
;;; ============================================================

(defun open-in-browser (filepath)
  (if (is-windows)
    ;; Windows: try Edge, fallback to default browser
    (progn
      (startapp "cmd.exe"
        (strcat "/c start msedge \"" filepath
                "\" 2>nul || start \"\" \"" filepath "\""))
    )
    ;; macOS: try Edge, fallback to default browser
    (vl-cmdf "_.SHELL"
      (strcat "open -a 'Microsoft Edge' '"
              filepath "' 2>/dev/null || open '" filepath "'"))
  )
)

;;; ============================================================
;;; JAPANESE DETECTION
;;; Unicode ranges (decimal):
;;;   12288-12543 : Hiragana, Katakana, JP punctuation
;;;   13312-19903 : CJK Extension A
;;;   19968-40959 : CJK Unified Ideographs (Kanji)
;;;   65381-65439 : Half-width Katakana
;;; ============================================================

(defun has-japanese (str / i code found)
  (setq i 1 found nil)
  (while (and (<= i (strlen str)) (not found))
    (setq code (ascii (substr str i 1)))
    (if (or (and (>= code 12288) (<= code 12543))
            (and (>= code 13312) (<= code 19903))
            (and (>= code 19968) (<= code 40959))
            (and (>= code 65381) (<= code 65439)))
      (setq found t)
    )
    (setq i (1+ i))
  )
  found
)

;;; ============================================================
;;; UNICODE ENCODING
;;; Converts non-ASCII characters to \uXXXX for safe file writing
;;; ============================================================

(defun int-to-hex4 (n / hex d0 d1 d2 d3)
  (setq hex "0123456789abcdef")
  (setq d0 (- n (* (/ n 16) 16)) n (/ n 16))
  (setq d1 (- n (* (/ n 16) 16)) n (/ n 16))
  (setq d2 (- n (* (/ n 16) 16)) n (/ n 16))
  (setq d3 (- n (* (/ n 16) 16)))
  (strcat (substr hex (1+ d3) 1) (substr hex (1+ d2) 1)
          (substr hex (1+ d1) 1) (substr hex (1+ d0) 1))
)

(defun unicode-encode (str / result i ch code)
  (setq result "" i 1)
  (while (<= i (strlen str))
    (setq ch (substr str i 1) code (ascii ch))
    (cond
      ((= ch "\"") (setq result (strcat result "\\\"")))
      ((= ch "\\") (setq result (strcat result "\\\\")))
      ((= code 10) (setq result (strcat result "\\n")))
      ((= code 13) (setq result (strcat result "\\r")))
      ((= code  9) (setq result (strcat result "\\t")))
      ((and (>= code 32) (<= code 126)) (setq result (strcat result ch)))
      (t (setq result (strcat result "\\u" (int-to-hex4 code))))
    )
    (setq i (1+ i))
  )
  result
)

;;; ============================================================
;;; MTEXT FORMATTING STRIPPER
;;; ============================================================

(defun mtext-strip (s / out i ch skip)
  (setq out "" i 1 skip 0)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (cond
      ((and (= ch "{") (= (substr s (1+ i) 1) "\\")) (setq skip (1+ skip)))
      ((and (> skip 0) (= ch "}"))  (setq skip (1- skip)))
      ((and (> skip 0) (= ch ";"))  (setq skip 0))
      ((> skip 0) nil)
      ((and (= ch "\\") (= (substr s (1+ i) 1) "P"))
       (setq out (strcat out " ")) (setq i (1+ i)))
      (t (setq out (strcat out ch)))
    )
    (setq i (1+ i))
  )
  out
)

;;; ============================================================
;;; TEXT COLLECTION
;;; ============================================================

(defun collect-texts (/ ss i ent edata etype etext ehandle items total jp)
  (setq items '() total 0 jp 0)
  (setq ss (ssget "X" '((0 . "TEXT,MTEXT"))))
  (if (null ss)
    (progn (alert "No TEXT or MTEXT found in drawing.") nil)
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq ent     (ssname ss i)
              edata   (entget ent)
              etype   (cdr (assoc 0 edata))
              ehandle (cdr (assoc 5 edata))
              etext   (cdr (assoc 1 edata)))
        (if (= etype "MTEXT") (setq etext (mtext-strip etext)))
        (setq total (1+ total))
        (if (and etext (> (strlen etext) 0) (has-japanese etext))
          (progn
            (setq jp (1+ jp))
            (setq items (append items (list (list ehandle etext etype))))
          )
        )
        (setq i (1+ i))
      )
      (princ (strcat "\nTotal texts: " (itoa total)
                     " | Japanese: " (itoa jp)
                     " | Skipped: " (itoa (- total jp))))
      items
    )
  )
)

;;; ============================================================
;;; JSON FILE WRITER (line-by-line, no strcat bottleneck)
;;; ============================================================

(defun write-json-file (json-path items / f entry first)
  (setq f (open json-path "w") first t)
  (write-line "[" f)
  (foreach entry items
    (if (not first) (write-line "," f))
    (write-line
      (strcat "{\"handle\":\"" (car entry)
              "\",\"original\":\"" (unicode-encode (cadr entry))
              "\",\"type\":\""     (caddr entry)
              "\",\"translated\":\"\",\"approved\":false}")
      f)
    (setq first nil)
  )
  (write-line "]" f)
  (close f)
)

;;; Wrap JSON as JS variable for <script src> (avoids file:// fetch restriction)
(defun write-data-js (js-path json-path / f line content)
  (setq f (open json-path "r") content "")
  (while (setq line (read-line f))
    (setq content (strcat content line "\n")))
  (close f)
  (setq f (open js-path "w"))
  (write-line (strcat "const rows = " content ";") f)
  (close f)
)

;;; ============================================================
;;; HTML GUI WRITER
;;; ============================================================

(defun write-html (html-path dwg-dir item-count / f n)
  (setq n (itoa item-count))
  (setq f (open html-path "w"))

  ;; HEAD
  (write-line "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'>" f)
  (write-line "<title>CAD Translate</title>" f)
  (write-line "<script src='jpt_data.js'></script>" f)
  (write-line "<style>" f)
  (write-line "*{box-sizing:border-box;margin:0;padding:0}" f)
  (write-line "body{font-family:-apple-system,'Segoe UI',sans-serif;background:#0d1117;color:#c9d1d9;padding:20px;font-size:14px}" f)
  (write-line "h1{color:#58a6ff;font-size:1.4em;margin-bottom:2px}" f)
  (write-line ".sub{color:#8b949e;font-size:.82em;margin-bottom:16px}" f)
  (write-line ".card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:14px;margin-bottom:10px}" f)
  (write-line ".card h3{color:#8b949e;font-size:.78em;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px}" f)
  (write-line ".row{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap}" f)
  (write-line ".col{display:flex;flex-direction:column;gap:3px}" f)
  (write-line "label{font-size:.76em;color:#8b949e}" f)
  (write-line "input[type=text],select,textarea.prompt-box{background:#0d1117;color:#c9d1d9;border:1px solid #30363d;border-radius:6px;padding:7px 10px;font-size:.84em;font-family:inherit}" f)
  (write-line "input[type=text]:focus,select:focus,textarea.prompt-box:focus{outline:none;border-color:#58a6ff}" f)
  (write-line "select option{background:#161b22}" f)
  (write-line ".iurl{width:280px}.imdl{width:260px}.ikey{width:200px}" f)
  (write-line ".prompt-box{width:100%;height:90px;resize:vertical;line-height:1.5;font-size:.8em;margin-top:6px}" f)
  (write-line ".btn{padding:8px 15px;border:none;border-radius:6px;cursor:pointer;font-weight:600;font-size:.84em;transition:.15s;white-space:nowrap}" f)
  (write-line ".bb{background:#1f6feb;color:#fff}.bb:hover{background:#388bfd}" f)
  (write-line ".bg{background:#238636;color:#fff}.bg:hover{background:#2ea043}" f)
  (write-line ".bd{background:#21262d;color:#c9d1d9;border:1px solid #30363d}.bd:hover{background:#30363d}" f)
  (write-line ".br{background:#6e2020;color:#fff}.br:hover{background:#8b2727}" f)
  (write-line ".st{padding:6px 12px;border-radius:6px;font-size:.8em;display:inline-block;min-width:140px}" f)
  (write-line ".si{background:#0d2137;color:#58a6ff}.so{background:#0f2a1a;color:#3fb950}.se{background:#2d0f0f;color:#f85149}" f)
  (write-line ".prog{height:3px;background:#21262d;border-radius:2px;margin:8px 0 0;overflow:hidden}" f)
  (write-line ".pf{height:100%;background:linear-gradient(90deg,#1f6feb,#238636);transition:width .3s;width:0}" f)
  (write-line "table{width:100%;border-collapse:collapse}" f)
  (write-line "th{background:#161b22;color:#58a6ff;padding:9px 8px;text-align:left;font-size:.78em;border-bottom:2px solid #30363d;position:sticky;top:0;z-index:1;font-weight:600;text-transform:uppercase;letter-spacing:.04em}" f)
  (write-line "td{padding:8px;border-bottom:1px solid #21262d;font-size:.83em;vertical-align:top}" f)
  (write-line "tr:hover td{background:#ffffff04}" f)
  (write-line ".jp{color:#e3b341;line-height:1.5;word-break:break-all}" f)
  (write-line "textarea.tl{width:100%;background:#0d1117;color:#7ee787;border:1px solid #1a4d2e;border-radius:5px;padding:6px 8px;font-size:.87em;resize:vertical;min-height:34px;font-family:inherit}" f)
  (write-line "textarea.tl:focus{outline:none;border-color:#3fb950}" f)
  (write-line ".cc{text-align:center;width:40px}" f)
  (write-line "input[type=checkbox]{width:15px;height:15px;cursor:pointer;accent-color:#238636}" f)
  (write-line ".tag{font-size:.68em;background:#21262d;border:1px solid #30363d;padding:2px 5px;border-radius:3px;color:#8b949e}" f)
  (write-line ".wrap{max-height:calc(100vh - 370px);overflow-y:auto;border:1px solid #30363d;border-radius:8px}" f)
  (write-line ".toolbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:8px}" f)
  (write-line ".foot{margin-top:12px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}" f)
  (write-line ".notice{display:none;background:#161b22;border:1px solid #388bfd;border-radius:8px;padding:14px;margin-top:10px;font-size:.83em;color:#79c0ff;line-height:1.7}" f)
  (write-line "@keyframes spin{to{transform:rotate(360deg)}}.spin{display:inline-block;animation:spin 1s linear infinite}" f)
  (write-line "</style></head><body>" f)

  ;; HEADER
  (write-line "<h1>CAD Translate</h1>" f)
  (write-line (strcat "<div class='sub'>AutoCAD DWG &rarr; English &nbsp;|&nbsp; <b style='color:#3fb950'>"
                      n " Japanese texts found</b></div>") f)

  ;; PROVIDER CONFIG CARD
  (write-line "<div class='card'>" f)
  (write-line "<h3>AI Provider</h3>" f)
  (write-line "<div class='row'>" f)
  ;; Provider dropdown
  (write-line "<div class='col'><label>Provider</label>" f)
  (write-line "<select id='provider' onchange='onProviderChange()' style='width:160px'>" f)
  (write-line "<option value='lmstudio'>LM Studio</option>" f)
  (write-line "<option value='ollama'>Ollama</option>" f)
  (write-line "<option value='openai'>OpenAI</option>" f)
  (write-line "<option value='anthropic'>Anthropic (Claude)</option>" f)
  (write-line "<option value='custom'>Custom / Other</option>" f)
  (write-line "</select></div>" f)
  ;; API URL
  (write-line "<div class='col'><label>API URL</label>" f)
  (write-line "<input type='text' class='iurl' id='apiUrl' value='http://127.0.0.1:1234/v1/chat/completions'></div>" f)
  ;; Model
  (write-line "<div class='col'><label>Model</label>" f)
  (write-line "<input type='text' class='imdl' id='apiModel' value='mlx-community/qwen3.6-35b-a3b'></div>" f)
  ;; API Key
  (write-line "<div class='col'><label>API Key <span style='color:#484f58'>(local = leave empty)</span></label>" f)
  (write-line "<input type='text' class='ikey' id='apiKey' placeholder='sk-...'></div>" f)
  ;; Start button + status
  (write-line "<div class='col' style='justify-content:flex-end'>" f)
  (write-line "<button class='btn bb' onclick='startAll()'>&#9654; Translate All</button></div>" f)
  (write-line "<div class='col' style='justify-content:flex-end'>" f)
  (write-line "<span id='st' class='st si'>Ready</span></div>" f)
  (write-line "</div>" f)
  (write-line "<div class='prog'><div class='pf' id='pf'></div></div>" f)
  (write-line "</div>" f)

  ;; PROMPT EDITOR CARD
  (write-line "<div class='card'>" f)
  (write-line "<h3>System Prompt <span style='color:#484f58;font-weight:400;text-transform:none'>(customize for your project)</span></h3>" f)
  (write-line "<textarea class='prompt-box' id='sysPrompt'>You are an expert technical translator for Japanese architectural, structural, and facade construction drawings. Translate Japanese labels, annotations, and technical terms to English.\n\nRules:\n- Return ONLY the translated English text, nothing else\n- Use standard construction/architectural terminology\n- Common terms: Top/Upper=上, Bottom/Lower=下, Left=左, Right=右, Surface=表面, Back=裏面, Side=側面, Front=正面, Section=断面, Detail=詳細, Dimension=寸法, Thickness=厚さ, Width=幅, Height=高さ, Installation=取付, Construction=施工, Finish=仕上, Stone=石材, Exterior wall=外壁, Coping=笠木, Joint=目地, Anchor=アンカー, Bracket=ブラケット\n- Keep numbers, codes, symbols as-is (e.g. NO.17, EXP.J)\n- Short labels stay concise (e.g. 上=Top not Top surface)\n- If already English, return as-is</textarea>" f)
  (write-line "</div>" f)

  ;; TOOLBAR
  (write-line "<div class='toolbar'>" f)
  (write-line "<button class='btn bd' onclick='sa(true)'>&#10003; Select All</button>" f)
  (write-line "<button class='btn bd' onclick='sa(false)'>&#10007; Deselect All</button>" f)
  (write-line "<button class='btn bd' onclick='reTr()'>&#8635; Re-translate Selected</button>" f)
  (write-line "<span id='ci' style='color:#8b949e;font-size:.8em;margin-left:4px'></span>" f)
  (write-line "</div>" f)

  ;; TABLE
  (write-line "<div class='wrap'><table><thead><tr>" f)
  (write-line "<th class='cc'>&#10003;</th>" f)
  (write-line "<th style='width:36%'>Japanese (Original)</th>" f)
  (write-line "<th>English (Translation &mdash; editable)</th>" f)
  (write-line "<th style='width:52px'>Type</th>" f)
  (write-line "</tr></thead><tbody id='tb'></tbody></table></div>" f)

  ;; FOOTER
  (write-line "<div class='foot'>" f)
  (write-line "<button class='btn bg' onclick='saveOutput()'>&#128190; Approve &amp; Download jpt_output.json</button>" f)
  (write-line "<span style='color:#8b949e;font-size:.8em'>Move downloaded file to DWG folder &rarr; run <b style='color:#e3b341'>CADAPPLY</b> in AutoCAD</span>" f)
  (write-line "</div>" f)
  (write-line "<div class='notice' id='notice'></div>" f)

  ;; JAVASCRIPT
  (write-line "<script>" f)
  (write-line (strcat "const DWG_DIR='" dwg-dir "';") f)
  (write-line "let busy=false;" f)
  (write-line "const cache=new Map();" f)
  (write-line "" f)

  ;; Provider presets
  (write-line "const PROVIDERS={" f)
  (write-line "  lmstudio:{url:'http://127.0.0.1:1234/v1/chat/completions',model:'mlx-community/qwen3.6-35b-a3b',key:''}," f)
  (write-line "  ollama:{url:'http://127.0.0.1:11434/v1/chat/completions',model:'llama3',key:''}," f)
  (write-line "  openai:{url:'https://api.openai.com/v1/chat/completions',model:'gpt-4o-mini',key:''}," f)
  (write-line "  anthropic:{url:'https://api.anthropic.com/v1/messages',model:'claude-3-5-haiku-20241022',key:''}," f)
  (write-line "  custom:{url:'',model:'',key:''}" f)
  (write-line "};" f)
  (write-line "" f)

  (write-line "function onProviderChange(){" f)
  (write-line "  const p=document.getElementById('provider').value;" f)
  (write-line "  const preset=PROVIDERS[p];" f)
  (write-line "  if(p!=='custom'){" f)
  (write-line "    document.getElementById('apiUrl').value=preset.url;" f)
  (write-line "    document.getElementById('apiModel').value=preset.model;" f)
  (write-line "  }" f)
  (write-line "}" f)
  (write-line "" f)

  (write-line "window.onload=()=>render();" f)
  (write-line "" f)

  (write-line "function render(){" f)
  (write-line "  const tb=document.getElementById('tb');tb.innerHTML='';" f)
  (write-line "  rows.forEach((r,i)=>{" f)
  (write-line "    const tr=document.createElement('tr');" f)
  (write-line "    tr.innerHTML=" f)
  (write-line "      `<td class='cc'><input type='checkbox' id='c${i}' checked onchange='cnt()'></td>`" f)
  (write-line "      +`<td class='jp'>${eh(r.original)}</td>`" f)
  (write-line "      +`<td><textarea class='tl' id='t${i}' rows='2'>${eh(r.translated||'')}</textarea></td>`" f)
  (write-line "      +`<td><span class='tag'>${r.type}</span></td>`;" f)
  (write-line "    tb.appendChild(tr);" f)
  (write-line "  });cnt();" f)
  (write-line "}" f)
  (write-line "" f)

  (write-line "async function startAll(){" f)
  (write-line "  if(busy)return;busy=true;" f)
  (write-line "  let done=0,fromCache=0,apiCalls=0;" f)
  (write-line "  rows.forEach(r=>{if(r.translated&&r.translated.length>0&&!r.translated.startsWith('['))cache.set(r.original,r.translated);});" f)
  (write-line "  const unique=new Set(rows.map(r=>r.original)).size;" f)
  (write-line "  setSt('i',`${rows.length} texts / ${unique} unique &mdash; starting...`);" f)
  (write-line "  for(let i=0;i<rows.length;i++){" f)
  (write-line "    if(rows[i].translated&&rows[i].translated.length>0&&!rows[i].translated.startsWith('[')){done++;prog(done);continue;}" f)
  (write-line "    const hit=cache.has(rows[i].original);" f)
  (write-line "    const t=await lmCall(rows[i].original);" f)
  (write-line "    rows[i].translated=t;" f)
  (write-line "    const el=document.getElementById('t'+i);if(el)el.value=t;" f)
  (write-line "    if(hit)fromCache++;else apiCalls++;" f)
  (write-line "    done++;prog(done);" f)
  (write-line "    if(done%5===0)setSt('i',`<span class='spin'>&#9881;</span> ${done}/${rows.length} &mdash; API: ${apiCalls}, cache: ${fromCache}`);" f)
  (write-line "  }" f)
  (write-line "  busy=false;" f)
  (write-line "  setSt('o',`&#10003; Done! API calls: ${apiCalls}, from cache: ${fromCache}`);" f)
  (write-line "}" f)
  (write-line "" f)

  (write-line "async function reTr(){" f)
  (write-line "  if(busy)return;busy=true;" f)
  (write-line "  for(let i=0;i<rows.length;i++){" f)
  (write-line "    if(!document.getElementById('c'+i)?.checked)continue;" f)
  (write-line "    setSt('i',`<span class='spin'>&#9881;</span> Re-translating ${i+1}/${rows.length}...`);" f)
  (write-line "    cache.delete(rows[i].original);" f)
  (write-line "    const t=await lmCall(rows[i].original);" f)
  (write-line "    rows[i].translated=t;" f)
  (write-line "    document.getElementById('t'+i).value=t;" f)
  (write-line "  }" f)
  (write-line "  busy=false;setSt('o','&#8635; Re-translation done.');" f)
  (write-line "}" f)
  (write-line "" f)

  ;; Universal LM call - handles OpenAI-compatible + Anthropic
  (write-line "async function lmCall(text){" f)
  (write-line "  if(cache.has(text))return cache.get(text);" f)
  (write-line "  const url=document.getElementById('apiUrl').value.trim();" f)
  (write-line "  const model=document.getElementById('apiModel').value.trim();" f)
  (write-line "  const key=document.getElementById('apiKey').value.trim();" f)
  (write-line "  const sys=document.getElementById('sysPrompt').value.trim();" f)
  (write-line "  const provider=document.getElementById('provider').value;" f)
  (write-line "  const headers={'Content-Type':'application/json'};" f)
  (write-line "  if(key){" f)
  (write-line "    if(provider==='anthropic')headers['x-api-key']=key;" f)
  (write-line "    else headers['Authorization']='Bearer '+key;" f)
  (write-line "  }" f)
  (write-line "  try{" f)
  ;; Anthropic needs different body format
  (write-line "    let body;" f)
  (write-line "    if(provider==='anthropic'){" f)
  (write-line "      headers['anthropic-version']='2023-06-01';" f)
  (write-line "      body={model,system:sys,messages:[{role:'user',content:text}],max_tokens:200};" f)
  (write-line "    }else{" f)
  (write-line "      body={model,messages:[{role:'system',content:sys},{role:'user',content:text}],temperature:0.1,max_tokens:200};" f)
  (write-line "    }" f)
  (write-line "    const r=await fetch(url,{method:'POST',headers,body:JSON.stringify(body)});" f)
  (write-line "    const d=await r.json();" f)
  ;; Handle both OpenAI and Anthropic response formats
  (write-line "    let t;" f)
  (write-line "    if(provider==='anthropic'){" f)
  (write-line "      t=(d.content?.[0]?.text||'').trim();" f)
  (write-line "    }else{" f)
  (write-line "      t=(d.choices?.[0]?.message?.content||'').trim();" f)
  (write-line "    }" f)
  (write-line "    if(!t)t='[empty response]';" f)
  (write-line "    cache.set(text,t);" f)
  (write-line "    return t;" f)
  (write-line "  }catch(e){return '[ERROR: '+e.message+']';}" f)
  (write-line "}" f)
  (write-line "" f)

  (write-line "function saveOutput(){" f)
  (write-line "  rows.forEach((r,i)=>{" f)
  (write-line "    const el=document.getElementById('t'+i);if(el)r.translated=el.value;" f)
  (write-line "    r.approved=document.getElementById('c'+i)?.checked||false;" f)
  (write-line "  });" f)
  (write-line "  const blob=new Blob([JSON.stringify(rows,null,2)],{type:'application/json'});" f)
  (write-line "  const a=document.createElement('a');a.href=URL.createObjectURL(blob);" f)
  (write-line "  a.download='jpt_output.json';a.click();" f)
  (write-line "  const n=document.getElementById('notice');n.style.display='block';" f)
  (write-line "  n.innerHTML='<b style=\"color:#3fb950\">&#10003; jpt_output.json downloaded!</b><br><br>'" f)
  (write-line "    +'<b>Next steps:</b><br>'" f)
  (write-line "    +'1. Move the downloaded file to your DWG folder:<br>'" f)
  (write-line "    +'<code style=\"color:#e3b341\">'+DWG_DIR+'</code><br><br>'" f)
  (write-line "    +'2. In AutoCAD command line, type: <code style=\"color:#e3b341\">CADAPPLY</code>';" f)
  (write-line "}" f)
  (write-line "" f)

  (write-line "function sa(v){rows.forEach((_,i)=>{const c=document.getElementById('c'+i);if(c)c.checked=v;});cnt();}" f)
  (write-line "function cnt(){const n=rows.filter((_,i)=>document.getElementById('c'+i)?.checked).length;document.getElementById('ci').textContent=n+' / '+rows.length+' selected';}" f)
  (write-line "function prog(d){document.getElementById('pf').style.width=(d/rows.length*100)+'%';}" f)
  (write-line "function eh(s){return(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}" f)
  (write-line "function setSt(c,m){const el=document.getElementById('st');el.className='st s'+c;el.innerHTML=m;}" f)
  (write-line "</script></body></html>" f)
  (close f)
)

;;; ============================================================
;;; MAIN COMMAND: CADTRANSLATE
;;; ============================================================

(defun c:CADTRANSLATE (/ items dwg-dir html-path json-path js-path out-path)
  (princ "\n=== CAD-TRANSLATE ===\n")

  (setq dwg-dir   (get-dwg-dir)
        json-path (path-join dwg-dir "jpt_data.json")
        js-path   (path-join dwg-dir "jpt_data.js")
        html-path (path-join dwg-dir "jpt_gui.html")
        out-path  (path-join dwg-dir "jpt_output.json"))

  (princ "\nScanning for Japanese text...")
  (setq items (collect-texts))
  (if (or (null items) (= (length items) 0))
    (progn (alert "No Japanese text found in this drawing.") (exit))
  )
  (princ (strcat "\nSending " (itoa (length items)) " texts to GUI..."))

  (princ "\nWriting data files...")
  (write-json-file json-path items)
  (write-data-js   js-path   json-path)
  (write-html      html-path dwg-dir (length items))

  (open-in-browser html-path)

  (alert (strcat
    "GUI opened in browser!\n\n"
    (itoa (length items)) " Japanese texts found.\n\n"
    "Steps:\n"
    "1. Select your AI provider\n"
    "2. Click 'Translate All'\n"
    "3. Review, edit, tick to approve\n"
    "4. Click 'Approve & Download'\n"
    "5. Move jpt_output.json to:\n"
    "   " dwg-dir "\n"
    "6. In AutoCAD: CADAPPLY\n\n"
    "Click OK when ready to apply..."))

  (apply-translations out-path)
  (princ "\n=== Done ===\n")
  (princ)
)

;;; ============================================================
;;; APPLY COMMAND: CADAPPLY
;;; ============================================================

(defun c:CADAPPLY (/ out-path dwg-dir)
  (setq dwg-dir (get-dwg-dir))
  (setq out-path (path-join dwg-dir "jpt_output.json"))
  (princ (strcat "\nApplying: " out-path "\n"))
  (apply-translations out-path)
  (princ)
)

;;; ============================================================
;;; APPLY TRANSLATIONS (pretty-printed JSON reader)
;;; ============================================================

(defun apply-translations (out-path / f line handle trans approved ent edata count total trimmed)
  (if (not (findfile out-path))
    (alert (strcat "File not found:\n" out-path
                   "\n\nDownload from GUI and move to DWG folder first."))
    (progn
      (setq f (open out-path "r"))
      (setq count 0 total 0 handle nil trans nil approved nil)
      (while (setq line (read-line f))
        (setq trimmed (vl-string-trim " \t" line))
        (cond
          ((vl-string-search "\"handle\":" trimmed 0)
           (setq handle (extract-quoted-val trimmed)))
          ((vl-string-search "\"translated\":" trimmed 0)
           (setq trans (extract-quoted-val trimmed)))
          ((vl-string-search "\"approved\":" trimmed 0)
           (setq approved (if (vl-string-search "true" trimmed 0) "true" "false")))
        )
        (if (and handle trans approved)
          (progn
            (setq total (1+ total))
            (if (and (= approved "true") (> (strlen trans) 0))
              (progn
                (setq ent (handent handle))
                (if ent
                  (progn
                    (setq edata (entget ent))
                    (setq edata (subst (cons 1 trans) (assoc 1 edata) edata))
                    (entmod edata)
                    (entupd ent)
                    (setq count (1+ count))
                  )
                )
              )
            )
            (setq handle nil trans nil approved nil)
          )
        )
      )
      (close f)
      (alert (strcat (itoa count) " / " (itoa total) " texts updated successfully!"))
    )
  )
)

(defun extract-quoted-val (line / p1 p2)
  (setq p1 (vl-string-search ":" line 0))
  (if (null p1) nil
    (progn
      (setq p1 (vl-string-search "\"" line (1+ p1)))
      (if (null p1) nil
        (progn
          (setq p1 (1+ p1))
          (setq p2 p1)
          (while (and (< p2 (strlen line))
                      (not (and (= (substr line (1+ p2) 1) "\"")
                                (or (= p2 p1) (/= (substr line p2 1) "\\")))))
            (setq p2 (1+ p2))
          )
          (substr line (1+ p1) (- p2 p1))
        )
      )
    )
  )
)

;;; ============================================================
;;; LEGACY COMMAND ALIASES (backward compatibility)
;;; ============================================================
(defun c:JPTRANSLATE () (c:CADTRANSLATE))
(defun c:JPTAPPLY    () (c:CADAPPLY))

(princ "\n================================================")
(princ "\n  CAD-TRANSLATE loaded")
(princ "\n  Commands: CADTRANSLATE | CADAPPLY")
(princ "\n  (also: JPTRANSLATE | JPTAPPLY)")
(princ "\n  Supports: LM Studio, Ollama, OpenAI,")
(princ "\n            Anthropic, any OpenAI-compatible API")
(princ "\n  Mac + Windows compatible")
(princ "\n================================================\n")
(princ)
