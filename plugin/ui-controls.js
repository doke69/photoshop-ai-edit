// Plain DOM buttons share one skin across Photoshop hosts and browser preview.
function setButtonDisabled(node,disabled){
 node.disabled=!!disabled;node.setAttribute('aria-disabled',String(!!disabled));node.setAttribute('tabindex',disabled?'-1':'0');
}
function bindButton(node){
 node.setAttribute('role','button');setButtonDisabled(node,!!node.disabled);
 node.addEventListener('click',event=>{if(node.disabled){event.preventDefault();event.stopImmediatePropagation();}},true);
 node.addEventListener('keydown',event=>{
  if(event.target!==node||node.disabled||event.repeat||event.altKey||event.ctrlKey||event.metaKey||event.key!=='Enter')return;
  event.preventDefault();event.stopPropagation();node.dispatchEvent(new Event('click',{bubbles:true,cancelable:true}));
 });
 return node;
}
function createUiButton(document){const node=document.createElement('div');node.className='ui-button';return bindButton(node);}
function initButtons(document){document.querySelectorAll('[data-ui-button]').forEach(bindButton);}
module.exports={setButtonDisabled,createUiButton,initButtons};

const checkStates=new Map();
function setChecked(node,checked,mark){checkStates.set(node.id,!!checked);node.setAttribute('aria-checked',String(!!checked));if(mark)mark.textContent=checked?'✓':'';}
function readChecked(node){return checkStates.get(node.id)===true;}
function bindCheckbox(node,mark){
 setChecked(node,false,mark);
 const toggle=()=>{if(!node.disabled)setChecked(node,!readChecked(node),mark);};
 node.addEventListener('click',toggle);node.addEventListener('keydown',event=>{if(event.target!==node||event.repeat||event.altKey||event.ctrlKey||event.metaKey)return;if(event.key==='Enter'||event.key===' '){event.preventDefault();event.stopPropagation();toggle();}});
}
module.exports.setChecked=setChecked;module.exports.readChecked=readChecked;module.exports.bindCheckbox=bindCheckbox;
