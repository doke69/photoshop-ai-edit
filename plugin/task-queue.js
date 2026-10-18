const {imageSources,unwrap}=require('./api');

// Only a record whose intent was durably persisted, and whose accepted
// requests all have task ids, may be resumed automatically. An interrupted
// "submitting" record may already be running (and billable) on the platform,
// so it must be confirmed by the user instead of retried.
function reconcileInterruptedSubmissions(jobs=[]){
 let changed=false;
 for(const job of jobs){
  if(!job||typeof job!=='object')continue;
  if(job.state!=='submitting'&&!job.pendingSubmit)continue;
  const tasks=Array.isArray(job.tasks)?job.tasks:[];
  const expected=Number(job.count)>0?Number(job.count):tasks.length;
  const incomplete=tasks.length===0||tasks.length<expected||tasks.some(task=>!task?.id);
  delete job.pendingSubmit;
  if(incomplete){
   job.state='uncertain';job.submissionFailed=true;
   job.error='上次提交在平台受理后中断，结果未知。请先到平台核对任务，避免重复扣费。';
  }else{
   job.state=tasks.some(task=>task.state==='running')?'running':job.submissionFailed?'failed':tasks.every(task=>task.state==='ready')?'ready':'failed';
  }
  changed=true;
 }
 return changed;
}

class TaskQueue{
 constructor({jobs=[],persist,client,onChange,onPersistError,onPersistRecovered}){
  this.jobs=jobs;this.persist=persist;this.client=client;this.onChange=onChange;
  this.onPersistError=onPersistError;this.onPersistRecovered=onPersistRecovered;
  this.querying=new Set();this.ticking=false;this.persistFailed=false;
 }
 save(){
  let saved=true;
  try{this.persist(this.jobs);}catch(error){
   saved=false;
   if(!this.persistFailed){
    this.persistFailed=true;this.persistError=error;
    if(typeof this.onPersistError==='function'){try{this.onPersistError(error);}catch(_){}}
   }
  }
  if(saved&&this.persistFailed){
   this.persistFailed=false;this.persistError=null;
   if(typeof this.onPersistRecovered==='function'){try{this.onPersistRecovered();}catch(_){}}
  }
  if(typeof this.onChange==='function')this.onChange();
  return saved;
 }
 async submit(record,images,params){
  const index=this.jobs.findIndex(j=>j.id===record.id);if(index>=0)this.jobs[index]=record;else this.jobs.unshift(record);this.save();
  let api;try{api=await this.client(record);}catch(error){record.state='failed';record.submissionFailed=true;record.error=error.message;this.save();return;}
  // Fail closed: without a durable marker we could not tell a rejected
  // request from an accepted one after a reload.
  record.pendingSubmit={at:Date.now()};record.state='submitting';
  if(!this.save()){
   delete record.pendingSubmit;record.state='failed';record.submissionFailed=true;
   record.error='本机存储空间不足，无法记录提交状态，已取消提交以避免重复扣费。请清理本机存储后重试。';
   this.save();return;
  }
  for(let i=0;i<record.count;i++){
   record.state='submitting';this.save();let id;
   try{id=await api.submit(record.model,record.instruction,images,params);}catch(error){
    delete record.pendingSubmit;
    record.submissionFailed=true;record.state=error.uncertain===true?'uncertain':record.tasks.length?'running':'failed';
    record.error=(record.tasks.length?'已提交 '+record.tasks.length+' / '+record.count+' 张；剩余未自动重试。':'')+error.message;this.save();return;
   }
   record.tasks.push({id,state:'running',results:[]});
   if(!this.save()){
    // Keep pendingSubmit so a reload reconciles this job to "uncertain";
    // stop here rather than create more tasks we cannot record.
    record.submissionFailed=true;record.state=record.tasks.some(t=>t.state==='running')?'running':'failed';
    record.error='本机存储空间不足，已停止提交剩余图片；已提交的 '+record.tasks.length+' / '+record.count+' 张仍会继续查询。请清理本机存储，并在平台核对。';
    return;
   }
  }
  delete record.pendingSubmit;
  record.state=record.tasks.every(t=>t.state==='ready')?'ready':record.tasks.some(t=>t.state==='running')?'running':'failed';this.save();
 }
 async tick(){
  if(this.ticking)return;
  const pending=this.jobs.flatMap(job=>job.tasks.filter(task=>task.state==='running').map(task=>({job,task})));
  if(!pending.length)return;
  this.ticking=true;let next=0;
  try{await Promise.all(Array.from({length:Math.min(3,pending.length)},async()=>{
   while(next<pending.length){const {job,task}=pending[next++];await this.query(job,task,true);}
  }));}finally{this.ticking=false;this.save();}
 }
 async query(job,task,batched=false){if(this.querying.has(task.id))return;this.querying.add(task.id);try{const api=await this.client(job),response=await api.status(task.id),data=unwrap(response),state=data.state||response.state;task.progress=data.progress??response.progress;task.updatedAt=Date.now();task.error=null;if(data.is_final===true||response.is_final===true||['success','failed','error','cancelled','canceled'].includes(state)){task.state=state==='success'?'ready':'failed';const failure=data.error||response.error||data.failure_reason||data.失败原因;task.error=state==='success'?null:typeof failure==='string'?failure:failure?.message||failure?.type||data.msg||'平台任务失败';task.results=state==='success'?imageSources(response).map(source=>({source,imported:false})):[];if(task.state==='ready'&&!task.results.length){task.state='failed';task.error='平台完成但没有返回可识别图片。';}}else task.platformState=state||'running';if(job.state!=='uncertain'&&job.state!=='submitting')job.state=job.tasks.some(t=>t.state==='running')?'running':job.submissionFailed?'failed':job.tasks.every(t=>t.state==='ready')?'ready':'failed';}catch(e){task.error=e.message;}finally{this.querying.delete(task.id);if(!batched)this.save();}}
}
module.exports={TaskQueue,reconcileInterruptedSubmissions};
