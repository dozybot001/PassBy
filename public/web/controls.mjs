let serial=0;
function element(tag,className,text){const el=document.createElement(tag);el.className=className;if(text)el.textContent=text;return el;}
// Popovers live in the top layer, outside clipped dialog bodies.
function position(panel,anchor){const r=anchor.getBoundingClientRect(),w=Math.min(260,innerWidth-32);panel.style.width=`${w}px`;panel.style.left=`${Math.max(16,Math.min(r.left,innerWidth-w-16))}px`;const height=panel.getBoundingClientRect().height;panel.style.top=`${Math.max(16,r.bottom+8+height<=innerHeight-16?r.bottom+8:r.top-height-8)}px`;}
export function info(text,label){
  const wrap=element('span','info-control'),trigger=element('button','info-trigger','i'),panel=element('div','info-panel',text);
  trigger.type='button';trigger.setAttribute('aria-label',label);panel.id=`info-${++serial}`;panel.popover='auto';trigger.setAttribute('aria-describedby',panel.id);trigger.setAttribute('aria-expanded','false');
  function show(){if(!panel.matches(':popover-open'))panel.showPopover();position(panel,trigger);}
  trigger.addEventListener('click',()=>panel.matches(':popover-open')?panel.hidePopover():show());
  trigger.addEventListener('pointerenter',e=>{if(e.pointerType==='mouse')show();});trigger.addEventListener('focus',()=>{if(trigger.matches(':focus-visible'))show();});
  wrap.addEventListener('pointerleave',()=>{if(document.activeElement!==trigger)panel.hidePopover();});
  trigger.addEventListener('blur',()=>panel.hidePopover());
  panel.addEventListener('toggle',()=>trigger.setAttribute('aria-expanded',String(panel.matches(':popover-open'))));
  wrap.append(trigger,panel);return wrap;
}
export function choice(options,value,label,onChange,id){
  const wrap=element('div','choice'),trigger=element('button','choice-trigger'),panel=element('div','choice-panel');trigger.type='button';trigger.id=id;panel.id=`choice-${++serial}`;panel.popover='auto';panel.setAttribute('role','listbox');panel.setAttribute('aria-label',label);trigger.setAttribute('aria-label',label);trigger.setAttribute('aria-haspopup','listbox');trigger.setAttribute('aria-controls',panel.id);trigger.setAttribute('aria-expanded','false');
  const items=options.map(option=>{const el=element('button','choice-option',option.name);el.type='button';el.setAttribute('role','option');el.setAttribute('aria-selected',String(option.id===value));el.addEventListener('click',()=>{value=option.id;update();panel.hidePopover();trigger.focus();onChange(value);});panel.append(el);return el;});
  function update(){trigger.textContent=options.find(o=>o.id===value)?.name||'';items.forEach((el,i)=>el.setAttribute('aria-selected',String(options[i].id===value)));}
  function show(){panel.showPopover();position(panel,trigger);items[Math.max(0,options.findIndex(o=>o.id===value))]?.focus();}
  trigger.addEventListener('click',()=>panel.matches(':popover-open')?panel.hidePopover():show());
  trigger.addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();show();}});
  panel.addEventListener('keydown',e=>{let i=items.indexOf(document.activeElement);if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)){e.preventDefault();i=e.key==='Home'?0:e.key==='End'?items.length-1:(i+(e.key==='ArrowDown'?1:-1)+items.length)%items.length;items[i]?.focus();}if(e.key==='Escape'){e.preventDefault();e.stopPropagation();panel.hidePopover();trigger.focus();}if(e.key==='Tab')panel.hidePopover();});
  panel.addEventListener('toggle',()=>trigger.setAttribute('aria-expanded',String(panel.matches(':popover-open'))));wrap.append(trigger,panel);update();return wrap;
}
export function switchInput(input){input.classList.add('capsule-switch');input.setAttribute('role','switch');return input;}

// Let the dialog body carry long notes, rather than scrolling inside the field.
export function autoGrow(input){
  function resize(){
    if(!input.isConnected || !input.clientWidth)return;
    input.style.height='auto';
    const style=getComputedStyle(input);
    const border=parseFloat(style.borderTopWidth)+parseFloat(style.borderBottomWidth);
    input.style.height=`${Math.ceil(input.scrollHeight+border)}px`;
  }
  let width;
  const observer=new ResizeObserver(entries=>{
    const next=entries[0].contentRect.width;
    if(next!==width){width=next;resize();}
  });
  observer.observe(input);
  input.addEventListener('input',resize);
  const frame=requestAnimationFrame(resize);
  return()=>{cancelAnimationFrame(frame);observer.disconnect();input.removeEventListener('input',resize);};
}
