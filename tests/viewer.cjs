// Dependency-free runtime checks, including DOM adoption. This models document
// ownership; it is not a substitute for a browser's PiP/animation integration.
const fs=require('fs'), vm=require('vm'), assert=require('assert');
const source=fs.readFileSync(require('path').join(__dirname,'../viewer/scene.html'),'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
let moved=false, now=1000000, pixels;
const elements=new Map(), moving=new Set(['cv','hudL','hudR','stripToggle','dayCount','turnBars','turnTooltip','settingsToggle','settingsPanel','settingsClose','musicSelect','volumeRange','volumeOut','soundToggle','settingsFeedback','sceneSelect']);
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
let selectedTrack='none', selectedVolume=0.4, selectedMuted=false, failSave=false;
const preferences=new Map([['wr-strip-2','on']]);
const settingsFetch=async(url,options)=>{
  assert.equal(url,'/settings'); assert.equal(options.headers['X-Stay-Awhile'],'1');
  if(options.method==='POST') {
    if(failSave) return {ok:false,json:async()=>({error:'Save failed'})};
    const body=JSON.parse(options.body);
    if('volume' in body) { assert.deepEqual(Object.keys(body),['volume']); selectedVolume=body.volume; return {ok:true,json:async()=>({volume:selectedVolume})}; }
    if('muted' in body) { assert.deepEqual(Object.keys(body),['muted']); assert.equal(typeof body.muted,'boolean'); selectedMuted=body.muted; return {ok:true,json:async()=>({muted:selectedMuted})}; }
    selectedTrack=body.track;
  }
  return {ok:true,json:async()=>({track:selectedTrack,volume:selectedVolume,muted:selectedMuted,groups:{ambient:['ambient/dusk']}})};
};
const context=vm.createContext({console,document:parentDocument,location:{protocol:'http:',search:'?dev',hash:''},
  fetch:settingsFetch,
  window:{requestAnimationFrame(){},documentPictureInPicture:{}},Date:FakeDate,EventSource,setInterval(){},
  matchMedia:()=>({matches:false}),performance:{now:()=>1000},localStorage:{getItem:key=>preferences.get(key),setItem:(key,value)=>preferences.set(key,value)},
  documentPictureInPicture:{requestWindow:async()=>pip}});
const run=code=>vm.runInContext(code,context);
run(source);
assert.equal(element('stripToggle').checked,true);
assert.equal(preferences.get('sa-strip-2'),'on');
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
  failSave=false;
  assert.equal(element('volumeRange').value,0.4);assert.equal(element('volumeOut').textContent,'40%');
  element('volumeRange').value='0.8';element('volumeRange').oninput();assert.equal(element('volumeOut').textContent,'80%');
  await element('volumeRange').onchange();assert.equal(selectedVolume,0.8);assert.match(element('settingsFeedback').textContent,/next turn/);
  failSave=true;element('volumeRange').value='0.1';await element('volumeRange').onchange();
  assert.equal(element('volumeRange').value,0.8);assert.equal(element('volumeOut').textContent,'80%');
  failSave=false;
  assert.equal(element('soundToggle').checked,true);
  element('soundToggle').checked=false;await element('soundToggle').onchange();assert.equal(selectedMuted,true);assert.match(element('settingsFeedback').textContent,/Sound off/);
  run('applyLive({running:false,muted:false,turns:[]})');assert.equal(element('soundToggle').checked,true);
  run("settingsPanel.hidden=false;stripKey({key:'Escape',preventDefault(){}})");
  assert(element('settingsPanel').hidden);
  assert.equal(pipDocument.activeElement,element('settingsToggle'));
  run("setStrip(false);stripKey({key:'b',target:{matches:()=>true}})");
  assert.equal(element('stripToggle').checked,false);
  assert.equal(preferences.get('sa-strip-2'),'off');
  now=1003601;run('paintHud()');assert.equal(run('state.nightAmt'),0);assert.equal(element('hudL').textContent,'—');
  for(const used of [.18,.5,.88,1]){
    run(`state.used=${used};state.shown=null;state.nightAmt=${used===1?1:0};render(3000)`);
    assert.equal(pixels.length,480*225*4);assert(pixels.some(v=>v>0));
  }
  const lakePixels=Buffer.from(pixels);
  assert.equal(parentDocument.getElementById('sceneSelect'),null);
  element('sceneSelect').value='alpine';element('sceneSelect').onchange();
  assert.equal(preferences.get('sa-scene'),'alpine');
  for(const used of [.18,.5,.88,1]) {
    run(`state.used=${used};state.shown=null;state.nightAmt=${used===1?1:0};render(3000)`);
    assert(pixels.some((v,i)=>v!==lakePixels[i]));
    assert(pixels.every((v,i)=>i%4!==3 || v===255));
    if(process.env.SA_SCENE_DUMP) {
      // PPM exports come straight from the renderer, without browser automation.
      const rgb=Buffer.alloc(480*225*3);
      for(let i=0;i<480*225;i++)for(let c=0;c<3;c++)rgb[i*3+c]=pixels[i*4+c];
      fs.writeFileSync(`/tmp/sa-alpine-${used}.ppm`,Buffer.concat([Buffer.from('P6\n480 225\n255\n'),rgb]));
    }
  }
  const alpineBefore=Buffer.from(pixels);run('render(19000)');
  assert(pixels.some((v,i)=>v!==alpineBefore[i]),'Alpine animation should advance');
  element('sceneSelect').value='coast';element('sceneSelect').onchange();
  assert.equal(preferences.get('sa-scene'),'coast');
  for(const used of [.18,.5,.88,1]) {
    run(`state.used=${used};state.shown=null;state.nightAmt=${used===1?1:0};render(3000)`);
    assert(pixels.every((v,i)=>i%4!==3 || v===255));
    assert.equal(run('coastalLightAmount()>0'),used>.72);
    if(process.env.SA_SCENE_DUMP) {
      const rgb=Buffer.alloc(480*225*3);
      for(let i=0;i<480*225;i++)for(let c=0;c<3;c++)rgb[i*3+c]=pixels[i*4+c];
      fs.writeFileSync(`/tmp/sa-coast-${used}.ppm`,Buffer.concat([Buffer.from('P6\n480 225\n255\n'),rgb]));
    }
  }
  const coastBefore=Buffer.from(pixels);run('render(19000)');
  assert(pixels.some((v,i)=>v!==coastBefore[i]),'Coastal animation should advance');
  element('sceneSelect').value='desert';element('sceneSelect').onchange();
  assert.equal(preferences.get('sa-scene'),'desert');
  for(const used of [.18,.5,.88,1]) {
    run(`state.used=${used};state.shown=null;state.nightAmt=${used===1?1:0};render(3000)`);
    assert(pixels.every((v,i)=>i%4!==3 || v===255));
    if(process.env.SA_SCENE_DUMP) {
      const rgb=Buffer.alloc(480*225*3);
      for(let i=0;i<480*225;i++)for(let c=0;c<3;c++)rgb[i*3+c]=pixels[i*4+c];
      fs.writeFileSync(`/tmp/sa-desert-${used}.ppm`,Buffer.concat([Buffer.from('P6\n480 225\n255\n'),rgb]));
    }
  }
  run('state.used=.5;state.shown=null;state.nightAmt=0;render(3000)');
  const desertBefore=Buffer.from(pixels);run('render(30000)');
  assert(pixels.some((v,i)=>v!==desertBefore[i]),'Desert atmosphere should advance');
  element('sceneSelect').value='lakeside';element('sceneSelect').onchange();
  assert.equal(preferences.get('sa-scene'),'lakeside');
  pip.close();assert(!moved);run('paintHud();setStrip(true)');
  failSave=false;selectedTrack='none';await run('loadMusic()');assert.equal(element('musicSelect').value,'none');
  preferences.set('sa-scene','desert');
  const reopened=vm.createContext({...context});vm.runInContext(source,reopened);
  assert.equal(vm.runInContext('selectedScene',reopened),'desert');
  assert.equal(element('sceneSelect').value,'desert');
  console.log('Viewer passed: scene switching/persistence and Alpine/coastal/desert lighting/animation, PiP adoption/return, HUD and history updates, settings load/save/error and keyboard handling, strip toggle, local moon/reset clock, four rendered moods.');
})().catch(e=>{console.error(e);process.exitCode=1});
