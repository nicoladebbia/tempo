import Vapor

// MARK: - Control page

//
// GET /v1/test — one browser page for everything testenv.sh/testctl do:
// server clock, AI mode, test users (subscription, persona, sign-out),
// run-now jobs, faults, token lifetime, and the pushes / AI calls the server
// made. Plain HTML + fetch against the /v1/test API; nothing to build.

enum TestModeControlPage {
    static func response() -> Response {
        var generator = SystemRandomNumberGenerator()
        let nonce = Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }).base64EncodedString()
        var headers = HTTPHeaders()
        headers.contentType = .html
        headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        headers.replaceOrAdd(
            name: "Content-Security-Policy",
            value: "default-src 'none'; style-src 'nonce-\(nonce)'; script-src 'nonce-\(nonce)'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        )
        let page = html
            .replacingOccurrences(of: "<style>", with: "<style nonce=\"\(nonce)\">")
            .replacingOccurrences(of: "<script>", with: "<script nonce=\"\(nonce)\">")
        return Response(status: .ok, headers: headers, body: .init(string: page))
    }

    static let html = ##"""
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tempo test server</title>
<style>
:root{--bg:#f6f6f4;--card:#fff;--fg:#141414;--muted:#6b6b6b;--line:#e4e4e0;--accent:#e5484d;--ok:#1a7f37;--warn:#9a6700;--chip:#efefec}
@media (prefers-color-scheme:dark){:root{--bg:#0e0f11;--card:#17191c;--fg:#ececec;--muted:#9a9a9a;--line:#2a2d31;--accent:#ff6369;--ok:#3fb950;--warn:#d29922;--chip:#222529}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,system-ui,sans-serif}
header{position:sticky;top:0;z-index:2;background:var(--bg);border-bottom:1px solid var(--line);padding:12px 16px;display:flex;flex-wrap:wrap;gap:8px;align-items:center}
header h1{font-size:16px;margin:0 12px 0 0}
.chip{background:var(--chip);border-radius:99px;padding:3px 10px;font-size:12px;white-space:nowrap}
.chip.warn{color:var(--warn);font-weight:600}
main{max-width:1180px;margin:0 auto;padding:16px;display:grid;gap:16px;grid-template-columns:repeat(auto-fit,minmax(340px,1fr))}
section{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;min-width:0}
section.wide{grid-column:1/-1}
h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:0 0 10px}
button,select,input{font:inherit;color:inherit;background:var(--chip);border:1px solid var(--line);border-radius:8px;padding:5px 9px}
button{cursor:pointer}button:hover{border-color:var(--muted)}
button.on{background:var(--fg);color:var(--bg);border-color:var(--fg)}
button.danger{color:var(--accent)}
.row{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:6px 0}
.big{font-size:22px;font-weight:600;margin:2px 0 8px}
.muted{color:var(--muted);font-size:12px}
.scroll{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;color:var(--muted);font-weight:500;font-size:12px}
td,th{padding:6px 6px;border-top:1px solid var(--line);vertical-align:middle;white-space:nowrap}
code{font-size:12px;color:var(--muted)}
#toast{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);background:var(--fg);color:var(--bg);padding:8px 14px;border-radius:10px;opacity:0;transition:opacity .2s;max-width:90vw}
#toast.show{opacity:1}
.w70{width:70px}.w80{width:80px}.w100{width:100px}.w170{width:170px}
</style></head><body>
<header><h1>Tempo test server</h1><span id="chips"></span></header>
<main>
<section><h2>Clock</h2>
  <div class="big" id="clock">…</div><div class="muted" id="clockNote"></div>
  <div class="row"><button data-shift="3600">+1 h</button><button data-shift="86400">+1 day</button><button data-shift="604800">+1 week</button><button data-shift="-86400">−1 day</button></div>
  <div class="row"><button data-when="sun-1955">Sunday 19:55</button><button data-when="tom-0820">Tomorrow 08:20</button><button data-when="tom-0000">Midnight</button><button id="clockReset" class="danger">Real time</button></div>
  <div class="row"><input type="datetime-local" id="clockAt"><button id="clockSet">Set</button></div>
</section>
<section><h2>AI</h2>
  <div class="row" id="aiModes"></div>
  <div class="row"><span class="muted">slow delay</span><input id="slowSecs" type="number" min="0" max="120" class="w70"><span class="muted">s</span></div>
  <div class="muted" id="aiNote"></div>
</section>
<section><h2>Sessions</h2>
  <div class="row"><span class="muted">access tokens last</span><input id="ttl" type="number" min="0" class="w80"><span class="muted">s</span><button id="ttlSet">Set</button><button id="ttlOff">Real (900)</button></div>
  <div class="muted">Short tokens exercise silent re-login. Sign-out (per user, below) revokes every session.</div>
</section>
<section class="wide"><h2>Test users</h2><div class="scroll"><table id="users"></table></div>
  <div class="muted">Sign a simulator in with <code>scripts/sim.sh qa --local --as NAME</code> (a second one: <code>--sim b</code>).</div>
</section>
<section><h2>Run a job now</h2>
  <div class="row"><select id="jobUser"></select><label class="muted"><input type="checkbox" id="jobForce"> force</label></div>
  <div class="row" id="jobs"></div>
  <div class="muted">At server time. Force = briefing outside 08:15–08:45 / a second time today.</div>
</section>
<section><h2>Break requests</h2>
  <div class="row"><input id="fPath" value="/v1/" class="w170"><select id="fKind"></select><input id="fValue" placeholder="status / secs" class="w100"></div>
  <div class="row"><input id="fCount" type="number" min="1" placeholder="times (∞)" class="w100"><select id="fUser"></select><button id="fAdd">Add</button><button id="fClear" class="danger">Clear all</button></div>
  <div class="scroll"><table id="faults"></table></div>
</section>
<section class="wide"><h2>Pushes</h2><div class="scroll"><table id="pushes"></table></div></section>
<section class="wide"><h2>AI calls</h2><div class="scroll"><table id="aicalls"></table></div></section>
</main>
<div id="toast"></div>
<script>
const MODES=["fake","broken","empty","slow","error","real","replay"];
const KINDS=["error","slow","logout","garbage","empty","timeout"];
const JOBS=["morning-briefing","weekly-summary","drill-sergeant","leaderboard-refresh","notifications-cleanup"];
const SUBS=["free","trial","active","cancelled","grace","billing-retry","expired","refunded"];
const PERSONAS=["athlete","picky-vegan","exam-week","injured","lapsed-pro"];
const $=id=>document.getElementById(id);
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const fmt=d=>new Date(d).toLocaleString([], {weekday:"short",day:"numeric",month:"short",hour:"2-digit",minute:"2-digit"});
let users=[], status={};
function toast(msg){const t=$("toast");t.textContent=msg;t.classList.add("show");clearTimeout(t._h);t._h=setTimeout(()=>t.classList.remove("show"),2600)}
async function api(method,path,body){
  const r=await fetch("/v1/test/"+path,{method,headers:{"Content-Type":"application/json"},body:body===undefined?undefined:JSON.stringify(body)});
  const text=await r.text(); let data=null; try{data=text?JSON.parse(text):null}catch(e){}
  if(!r.ok){const msg=(data&&data.reason)||text||r.status; toast("✕ "+msg); throw new Error(msg)}
  return data;
}
const act=(fn,ok)=>async(...a)=>{try{await fn(...a); if(ok) toast(ok); await refresh()}catch(e){}};
function chips(){
  const c=[];
  c.push(`<span class="chip">AI ${esc(status.ai_mode)}${status.recording_ai?" · recording":""}</span>`);
  if(Math.abs(status.clock_offset_seconds)>=1) c.push(`<span class="chip warn">clock moved ${(status.clock_offset_seconds/3600).toFixed(1)} h</span>`);
  if(status.faults) c.push(`<span class="chip warn">${status.faults} fault(s)</span>`);
  if(status.access_ttl_seconds!==900) c.push(`<span class="chip warn">tokens ${status.access_ttl_seconds}s</span>`);
  c.push(`<span class="chip">${status.pushes} pushes · ${status.ai_calls} AI calls</span>`);
  $("chips").innerHTML=c.join(" ");
}
function renderClock(){
  $("clock").textContent=fmt(status.now);
  const off=status.clock_offset_seconds;
  $("clockNote").textContent=Math.abs(off)<1?"real time":`${off>0?"+":"−"}${(Math.abs(off)/3600).toFixed(1)} h from real time · JWTs and rate limits stay on real time`;
}
function renderAI(){
  $("aiModes").innerHTML=MODES.map(m=>`<button data-mode="${m}" class="${m===status.ai_mode?"on":""}">${m}</button>`).join("");
  if(document.activeElement!==$("slowSecs")) $("slowSecs").value=status.slow_seconds;
  const recs=status.ai_recordings||{}; const keys=Object.keys(recs).sort();
  $("aiNote").innerHTML=(status.real_ai_available?"":"No real key — real needs <code>testenv.sh up --real-ai</code>. ")+
    (keys.length?"Recorded: "+keys.map(k=>`${esc(k)} ×${recs[k]}`).join(", "):"No recorded replies yet (<code>up --real-ai --record</code>).");
}
function userOptions(all){return (all?`<option value="">everyone</option>`:"")+users.map(u=>`<option value="${esc(u.name)}">${esc(u.name)}</option>`).join("")}
function renderUsers(){
  $("users").innerHTML="<tr><th>name</th><th>Pro</th><th>simulator</th><th>subscription</th><th>persona</th><th></th></tr>"+users.map(u=>`<tr>
    <td><b>${esc(u.name)}</b><br><code>${esc(u.id)}</code></td><td>${u.pro?"Pro":"free"}</td><td><code>${esc((u.simulator_udid||"—").slice(0,8))}</code></td>
    <td><select data-sub="${esc(u.name)}">${SUBS.map(s=>`<option>${s}</option>`).join("")}</select> <button data-subgo="${esc(u.name)}">Set</button></td>
    <td><select data-persona="${esc(u.name)}">${PERSONAS.map(s=>`<option>${s}</option>`).join("")}</select> <button data-personago="${esc(u.name)}">Seed</button></td>
    <td><button data-brief="${esc(u.name)}">Briefing now</button> <button class="danger" data-signout="${esc(u.name)}">Sign out</button></td></tr>`).join("");
  const keep=(id,all)=>{const v=$(id).value;$(id).innerHTML=userOptions(all);$(id).value=v};
  keep("jobUser",true); keep("fUser",true);
}
function renderFaults(rules){
  $("faults").innerHTML=rules.length?"<tr><th>path</th><th>kind</th><th>left</th><th>user</th><th>hits</th><th></th></tr>"+rules.map(r=>`<tr>
    <td><code>${esc(r.method||"")} ${esc(r.path_prefix)}</code></td><td>${esc(r.kind)} ${esc(r.status||r.delay_seconds||"")}</td>
    <td>${r.remaining??"∞"}</td><td>${esc(users.find(u=>u.id===r.user_id)?.name||(r.user_id?"…":"all"))}</td><td>${r.hits||0}</td>
    <td><button class="danger" data-unfault="${esc(r.id)}">✕</button></td></tr>`).join(""):`<tr><td class="muted">No faults — every request behaves normally.</td></tr>`;
}
function renderPushes(rows){
  rows=rows.slice(-25).reverse();
  $("pushes").innerHTML=rows.length?"<tr><th>when</th><th>user</th><th>delivery</th><th>push</th></tr>"+rows.map(p=>{
    let aps={};try{aps=JSON.parse(p.payload).aps||{}}catch(e){}
    const a=aps.alert||{};
    return `<tr><td>${fmt(p.created_at)}</td><td>${esc(users.find(u=>u.id===p.user_id)?.name||p.user_id)}</td><td>${esc(p.delivery)}</td>
      <td><b>${esc(a.title||"")}</b> ${esc(a.subtitle||"")} — ${esc(a.body||"")} <code>${esc(aps.category||"")}</code></td></tr>`}).join(""):`<tr><td class="muted">No pushes yet.</td></tr>`;
}
function renderAICalls(rows){
  rows=rows.slice(-25).reverse();
  $("aicalls").innerHTML=rows.length?"<tr><th>when</th><th>feature</th><th>mode</th><th>status</th></tr>"+rows.map(c=>`<tr>
    <td>${fmt(c.at)}</td><td>${esc(c.feature)}</td><td>${esc(c.mode)}</td><td>${c.status}</td></tr>`).join(""):`<tr><td class="muted">No AI calls yet.</td></tr>`;
}
async function refresh(){
  try{
    const [s,u,f,p,a]=await Promise.all([api("GET","status"),api("GET","users"),api("GET","faults"),api("GET","pushes"),api("GET","ai-calls")]);
    status=s; users=u; chips(); renderClock(); renderAI(); renderFaults(f); renderPushes(p); renderAICalls(a);
    if(!document.querySelector("#users select:focus")) renderUsers();
    if(document.activeElement!==$("ttl")) $("ttl").value=Math.round(s.access_ttl_seconds);
  }catch(e){}
}
function localTarget(kind){
  const d=new Date(); d.setSeconds(0,0);
  if(kind==="sun-1955"){d.setDate(d.getDate()+((7-d.getDay())%7)); d.setHours(19,55)}
  if(kind==="tom-0820"){d.setDate(d.getDate()+1); d.setHours(8,20)}
  if(kind==="tom-0000"){d.setDate(d.getDate()+1); d.setHours(0,0)}
  return d;
}
$("fKind").innerHTML=KINDS.map(k=>`<option>${k}</option>`).join("");
$("jobs").innerHTML=JOBS.map(j=>`<button data-job="${j}">${j}</button>`).join("");
document.addEventListener("click",e=>{
  const b=e.target.closest("button"); if(!b) return; const d=b.dataset;
  if(d.shift) act(()=>api("POST","clock",{advance_seconds:+d.shift}))();
  else if(d.when) act(()=>api("POST","clock",{set:localTarget(d.when).toISOString().replace(/\.\d+Z$/,"Z")}))();
  else if(d.mode) act(()=>api("POST","ai",{mode:d.mode,slow_seconds:+$("slowSecs").value||undefined}),"AI mode: "+d.mode)();
  else if(d.subgo) act(()=>api("POST","subscription",{name:d.subgo,state:document.querySelector(`select[data-sub="${CSS.escape(d.subgo)}"]`).value}).then(r=>toast(`${r.name}: ${r.state} → ${r.pro?"Pro":"not Pro"}`)))();
  else if(d.personago) act(()=>api("POST","persona",{name:d.personago,persona:document.querySelector(`select[data-persona="${CSS.escape(d.personago)}"]`).value}).then(r=>toast(`${d.personago}: ${r.persona}, ${r.xp_events} XP events, ${r.receipts} receipts`)))();
  else if(d.brief) act(()=>api("POST","jobs/run",{job:"morning-briefing",name:d.brief,force:true}),"Briefing sent")();
  else if(d.signout) act(()=>api("POST","sign-out?name="+encodeURIComponent(d.signout)),"Signed out "+d.signout)();
  else if(d.job) act(()=>api("POST","jobs/run",{job:d.job,name:$("jobUser").value||undefined,force:$("jobForce").checked}).then(r=>toast(`${r.job}: ${r.affected??"done"}`)))();
  else if(d.unfault) act(()=>api("DELETE","faults?id="+encodeURIComponent(d.unfault)))();
});
$("clockReset").onclick=act(()=>api("POST","clock",{reset:true}),"Back to real time");
$("clockSet").onclick=act(()=>{const v=$("clockAt").value; if(!v) throw new Error(toast("Pick a date and time")); return api("POST","clock",{set:new Date(v).toISOString().replace(/\.\d+Z$/,"Z")})});
$("ttlSet").onclick=act(()=>api("POST","auth",{access_ttl_seconds:+$("ttl").value}),"Token lifetime set");
$("ttlOff").onclick=act(()=>api("POST","auth",{access_ttl_seconds:0}),"Real token lifetime");
$("fAdd").onclick=act(async()=>{
  const kind=$("fKind").value, v=$("fValue").value, rule={path_prefix:$("fPath").value,kind};
  if(v&&kind==="error") rule.status=+v; if(v&&kind==="slow") rule.delay_seconds=+v;
  if($("fCount").value) rule.remaining=+$("fCount").value;
  const name=$("fUser").value; if(name) rule.user_id=users.find(u=>u.name===name)?.id;
  await api("POST","faults",rule);
},"Fault added");
$("fClear").onclick=act(()=>api("DELETE","faults"),"Faults cleared");
refresh(); setInterval(refresh,3000);
</script></body></html>
"""##
}
