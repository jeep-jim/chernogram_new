"use strict";
(()=>{
  const B=globalThis.BriefCraftBridge;
  if(!B)return;

  const seen=new Set();
  const responseActions=new Set(["OSMINOG_CHAT_RESPONSE","BRIEFCRAFT_CHAT_RESPONSE"]);
  const safeString=value=>String(value??"");

  function snapshot(){
    try{return B.getProjectMap?.({limit:200})||B.canvasStatus?.()||{info:"Local canvas"}}
    catch(error){return{info:"Local canvas",error:error?.message||String(error)}}
  }

  function normalizePatch(input){
    if(!input)return null;
    if(input.protocol==="briefcraft.patch/v1"&&Array.isArray(input.actions))return input;
    const actions=Array.isArray(input)?input:(Array.isArray(input.actions)?input.actions:(input.op?[input]:[]));
    if(!actions.length)return null;
    return{
      protocol:"briefcraft.patch/v1",
      projectId:B.canvasStatus?.()?.project?.id||"",
      summary:safeString(input.summary||"AI proposal"),
      actions
    };
  }

  async function queuePatch(input){
    const patch=normalizePatch(input);
    if(!patch)return{ok:false,error:"Patch is empty or invalid"};
    document.dispatchEvent(new CustomEvent("osminog:patch-staging",{detail:{actions:patch.actions,summary:patch.summary||"AI proposal"}}));
    return await B.executeTool("propose_canvas_patch",{summary:patch.summary||"AI proposal",actions:patch.actions});
  }

  function appendGenericMessage(text,isUser=false){
    const root=document.getElementById("chatMessages");
    if(!root)return;
    const row=document.createElement("div");
    row.className=`message ${isUser?"user-message":"assistant-message"}`;
    const bubble=document.createElement("div");
    bubble.className="message-bubble";
    bubble.textContent=safeString(text);
    const time=document.createElement("span");
    time.className="message-time";
    time.textContent=new Date().toLocaleTimeString([],{hour:"2-digit",minute:"2-digit"});
    if(!isUser){
      const avatar=document.createElement("div");
      avatar.className="avatar";
      avatar.textContent="●";
      const wrap=document.createElement("div");
      wrap.className="message-wrapper";
      wrap.append(bubble,time);
      row.append(avatar,wrap);
    }else row.append(bubble,time);
    root.append(row);
    root.scrollTop=root.scrollHeight;
  }

  async function publishResponse(message){
    const key=`${message?.requestId||"none"}:${message?.ok!==false}:${safeString(message?.text||message?.error).slice(0,120)}`;
    if(seen.has(key))return message;
    seen.add(key);setTimeout(()=>seen.delete(key),30000);
    if(message?.patch)await queuePatch(message.patch).catch(()=>{});
    if(message?.text)appendGenericMessage(message.text,false);
    document.dispatchEvent(new CustomEvent("osminog:chat-response",{detail:message}));
    return message;
  }

  async function send(message,options={}){
    const text=safeString(message).trim();
    if(!text)throw new Error("Пустое сообщение");
    const requestId=safeString(options.requestId||`osminog-${Date.now()}-${Math.random().toString(36).slice(2,7)}`);
    const response=await chrome.runtime.sendMessage({
      action:"OSMINOG_CHAT_REQUEST",
      payload:{
        message:text,
        provider:options.provider||"gpt",
        canvasContext:options.canvasContext||snapshot(),
        images:Array.isArray(options.images)?options.images:[],
        requestId
      }
    });
    if(!response?.ok)throw new Error(response?.error||"OSMINOG chat bridge failed");
    await publishResponse(response);
    return response;
  }

  chrome.runtime.onMessage.addListener(message=>{
    if(responseActions.has(String(message?.action||message?.type||"")))publishResponse(message).catch(()=>{});
  });

  const input=document.getElementById("chatInput"),button=document.getElementById("sendBtn");
  if(input&&button&&!button.dataset.osminogChatBound){
    button.dataset.osminogChatBound="1";
    const submit=async()=>{
      const text=safeString(input.value).trim();if(!text)return;
      appendGenericMessage(text,true);input.value="";
      try{await send(text,{provider:input.dataset.provider||"gpt"})}
      catch(error){appendGenericMessage(`Ошибка моста: ${error?.message||String(error)}`,false)}
    };
    button.addEventListener("click",submit);
    input.addEventListener("keydown",event=>{if(event.key==="Enter"&&!event.shiftKey){event.preventDefault();submit()}});
  }

  const api=Object.freeze({send,snapshot,queuePatch,applyPatch:()=>B.applyPatch?.(),dismissPatch:()=>B.dismissPatch?.()});
  globalThis.OSMINOG_CHAT=api;
  globalThis.BriefCraftChatBridge=api;
  globalThis.getLocalCanvasSnapshot=globalThis.getLocalCanvasSnapshot||snapshot;
  globalThis.executeOsminogPatch=queuePatch;
  globalThis.executeBriefCraftPatch=globalThis.executeBriefCraftPatch||queuePatch;
})();
