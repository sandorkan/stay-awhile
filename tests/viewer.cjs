// Dependency-free runtime checks, including DOM adoption. This models document
// ownership; it is not a substitute for a browser's PiP/animation integration.
const fs=require('fs'), vm=require('vm'), assert=require('assert');
const source=fs.readFileSync(require('path').join(__dirname,'../viewer/scene.html'),'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
let moved=false, now=1000000, pixels;
const elements=new Map(), moving=new Set(['cv','hudL','hudR','stripToggle','dayCount','turnBars','turnTooltip','settingsToggle','settingsPanel','settingsClose','musicSelect','settingsFeedback']);
let parentDocument, pipDocument;
function element(id) {
  if(!elements.has(id)) elements.set(id,{
    textContent:'',width:480,height:225,hidden:false,children:[],attributes:{},dataset:{},
    style:{setProperty(k,v){this[k]=v}},classList:{add(){},remove(){},toggle(){}},
    get ownerDocument(){return moved&&moving.has(id)?pipDocument:parentDocument},
    setAttribute(k,v){this.attributes[k]=v},
    append(child){this.children.push(child);if(id==='.stage')moved=false},
    focus(){this.ownerDocument.activeElement=this;if(this.onfocus)this.onfocus()},
    addEventListener(){}, replaceChildren(){this.children=[]}, contains(other){return this===other},
    getContext(){return {createImageData(w,h){return {data:new Uint8ClampedArray(w*h*4)}},putImageData(f){pixels=f.data}}}
  });
  return elements.get(id);
}
parentDocument={hidden:false,activeElement:null,getElementById:id=>moved&&moving.has(id)?null:element(id),
  querySelector:element,querySelectorAll:()=>[],createElement:()=>element(Symbol()),body:element('body'),addEventListener(){}};
pipDocument={createElement:()=>element(Symbol()),activeElement:null,head:element('head'),body:{classList:{add(){}},append(){moved=true}},addEventListener(){}};
const pip={document:pipDocument,events:{},addEventListener(k,f){this.events[k]=f},requestAnimationFrame(){},close(){this.events.pagehide?.()}};
class FakeDate extends Date { static now(){return now*1000} }
class EventSource { static CLOSED=2;static CONNECTING=0; constructor(){this.readyState=1} addEventListener(){} close(){} }
let selectedTrack='none', failSave=false;
const preferences=new Map([['wr-strip-2','on']]);
const settingsFetch=async(url,options)=>{
  assert.equal(url,'/settings'); assert.equal(options.headers['X-Waiting-Room'],'1');
  if(options.method==='POST') {
    if(failSave) return {ok:false,json:async()=>({error:'Save failed'})};
    selectedTrack=JSON.parse(options.body).track;
  }
  return {ok:true,json:async()=>({track:selectedTrack,groups:{ambient:['ambient/dusk']}})};
};
const context=vm.createContext({console,document:parentDocument,location:{protocol:'http:',search:'?dev',hash:''},
  fetch:settingsFetch,
  window:{requestAnimationFrame(){},documentPictureInPicture:{}},Date:FakeDate,EventSource,setInterval(){},
  matchMedia:()=>({matches:false}),performance:{now:()=>1000},localStorage:{getItem:key=>preferences.get(key),setItem:(key,value)=>preferences.set(key,value)},
  documentPictureInPicture:{requestWindow:async()=>pip}});
const run=code=>vm.runInContext(code,context);
run(source);
assert.equal(element('stripToggle').checked,true);
(async()=>{
  run('applyLive({five_hour:{used:100,resets_at:1003600},seven_day:{used:45,resets_at:1200000},ran_out_at:996400,running:false,turns:[]})');
  assert.equal(run('state.moonF'),.5);
  now+=1800;run('paintHud()');assert.equal(run('state.moonF'),.75);
  assert.match(element('hudL').textContent,/spent.*0:30/);
  await run('popOut()');assert(moved);
  assert.equal(parentDocument.getElementById('hudL'),null);
  run('paintHud();setStrip(true);rebuildTurns([{ended:"today",sec:90,outcome:"done"}])');
  assert.equal(element('dayCount').textContent,'1 turns');
  assert.equal(element('stripToggle').checked,true);
  run('applyLive({five_hour:{used:80,resets_at:1003600},seven_day:{used:46,resets_at:1200000},running:true,turns:[{ended:"new",sec:120,outcome:"done"}]})');
  assert.match(element('hudL').textContent,/80%/);assert.equal(element('hudR').textContent,'wk 46%');
  run('setStrip(false)');assert.equal(element('stripToggle').checked,false);
  await run('loadMusic()');
  assert.equal(element('musicSelect').value,'none');
  element('musicSelect').value='ambient/dusk'; await element('musicSelect').onchange();
  assert.equal(selectedTrack,'ambient/dusk');
  assert.match(element('settingsFeedback').textContent,/Saved/);
  failSave=true; element('musicSelect').value='none'; await element('musicSelect').onchange();
  assert.equal(element('musicSelect').value,'ambient/dusk');
  assert.match(element('settingsFeedback').textContent,/Save failed/);
  run("settingsPanel.hidden=false;stripKey({key:'Escape',preventDefault(){}})");
  assert(element('settingsPanel').hidden);
  assert.equal(pipDocument.activeElement,element('settingsToggle'));
  run("setStrip(false);stripKey({key:'b',target:{matches:()=>true}})");
  assert.equal(element('stripToggle').checked,false);
  assert.equal(preferences.get('wr-strip-2'),'off');
  now=1003601;run('paintHud()');assert.equal(run('state.nightAmt'),0);assert.equal(element('hudL').textContent,'—');
  for(const used of [.18,.5,.88,1]){
    run(`state.used=${used};state.shown=null;state.nightAmt=${used===1?1:0};render(3000)`);
    assert.equal(pixels.length,480*225*4);assert(pixels.some(v=>v>0));
  }
  pip.close();assert(!moved);run('paintHud();setStrip(true)');
  failSave=false;selectedTrack='none';await run('loadMusic()');assert.equal(element('musicSelect').value,'none');
  console.log('Viewer passed: PiP adoption/return, HUD and history updates, settings load/save/error and keyboard handling, strip toggle, local moon/reset clock, four rendered moods.');
})().catch(e=>{console.error(e);process.exitCode=1});
