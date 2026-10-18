const {test}=require('node:test');
const assert=require('node:assert/strict');
const {TaskQueue,reconcileInterruptedSubmissions}=require('../plugin/task-queue');
test('polling limits concurrency, ignores overlapping ticks, and saves one batch',async()=>{
 let active=0,max=0,requests=0,saves=0;
 const jobs=Array.from({length:9},(_,i)=>({id:String(i),state:'running',tasks:[{id:String(i),state:'running',results:[]}]}));
 const queue=new TaskQueue({jobs,persist:()=>saves++,onChange:()=>{},client:async()=>({status:async()=>{
  active++;requests++;max=Math.max(max,active);await new Promise(r=>setTimeout(r,5));active--;return {state:'success',is_final:true,result_url:'https://example.com/result.png'};
 }})});
 await Promise.all([queue.tick(),queue.tick(),queue.tick()]);
 assert.equal(requests,9);assert.equal(max,3);assert.equal(saves,1);assert.ok(jobs.every(j=>j.state==='ready'));
 await queue.tick();assert.equal(saves,1);
});
test('polling does not complete a job whose remaining candidates are still being submitted',async()=>{
 const job={state:'submitting',tasks:[{id:'first',state:'running',results:[]}]};
 const queue=new TaskQueue({jobs:[job],persist:()=>{},onChange:()=>{},client:async()=>({status:async()=>({state:'success',is_final:true,result_url:'https://example.com/image.png'})})});
 await queue.tick();assert.equal(job.state,'submitting');assert.equal(job.tasks[0].state,'ready');
});

test('partial rejection retains earlier tasks and never retries remaining candidates',async()=>{
 let submits=0;const record={id:'partial',model:'banana-2',instruction:'edit',count:4,tasks:[]};const queue=new TaskQueue({persist(){},onChange(){},client:async()=>({submit:async()=>{if(++submits===2)throw Object.assign(new Error('参数错误'),{uncertain:false});return 'first';},status:async()=>({state:'success',is_final:true,result_url:'https://example.com/output.png'})})});
 await queue.submit(record,['source'],{});assert.equal(submits,2);assert.equal(record.tasks.length,1);assert.equal(record.state,'running');assert.equal(record.submissionFailed,true);await queue.tick();assert.equal(record.tasks[0].state,'ready');assert.equal(record.state,'failed');assert.equal(submits,2);
});
test('uncertain submission stays uncertain after previous successful tasks finish',async()=>{
 let submits=0;const record={id:'uncertain',model:'banana-2',count:2,tasks:[]};const queue=new TaskQueue({persist(){},onChange(){},client:async()=>({submit:async()=>{if(++submits===2)throw Object.assign(new Error('network lost'),{uncertain:true});return 'first';},status:async()=>({state:'success',is_final:true,result_url:'https://example.com/output.png'})})});await queue.submit(record,['source'],{});await queue.tick();assert.equal(record.state,'uncertain');assert.equal(record.tasks.length,1);assert.equal(submits,2);
});

test('pending submission is persisted before the request and cleared after the task id is stored',async()=>{
 const snapshots=[];let sawPending=false;const record={id:'pending',model:'banana-2',instruction:'edit',count:1,tasks:[]};
 const queue=new TaskQueue({jobs:[],persist:value=>snapshots.push(JSON.parse(JSON.stringify(value))),onChange(){},client:async()=>({submit:async()=>{
  const saved=snapshots[snapshots.length-1][0];sawPending=saved.state==='submitting'&&!!saved.pendingSubmit;return 'task-1';
 }})});
 await queue.submit(record,['source'],{});
 assert.equal(sawPending,true);assert.equal(record.pendingSubmit,undefined);assert.equal(record.tasks[0].id,'task-1');
 const saved=snapshots[snapshots.length-1][0];assert.equal(saved.pendingSubmit,undefined);assert.equal(saved.tasks.length,1);
});

test('interrupted submissions reconcile to uncertain unless every task id was saved',()=>{
 const jobs=[
  {id:'partial',state:'submitting',pendingSubmit:{at:1},count:2,tasks:[{id:'a',state:'running',results:[]}]},
  {id:'marked',state:'running',pendingSubmit:{at:1},count:1,tasks:[]},
  {id:'complete',state:'submitting',pendingSubmit:{at:1},count:1,tasks:[{id:'b',state:'ready',results:[]}]},
  {id:'settled',state:'ready',count:1,tasks:[{id:'c',state:'ready',results:[]}]}
 ];
 assert.equal(reconcileInterruptedSubmissions(jobs),true);
 assert.equal(jobs[0].state,'uncertain');assert.equal(jobs[0].submissionFailed,true);assert.equal(jobs[0].pendingSubmit,undefined);assert.match(jobs[0].error,/核对/);assert.equal(jobs[0].tasks.length,1);
 assert.equal(jobs[1].state,'uncertain');assert.equal(jobs[1].submissionFailed,true);
 assert.equal(jobs[2].state,'ready');assert.equal(jobs[2].pendingSubmit,undefined);
 assert.equal(jobs[3].state,'ready');
 assert.equal(reconcileInterruptedSubmissions(jobs),false);
});

test('a quota failure after acceptance keeps the task id and stops further submissions',async()=>{
 let writes=0,errors=0,recoveries=0,submits=0;
 const record={id:'quota',model:'banana-2',instruction:'edit',count:2,tasks:[]};
 const queue=new TaskQueue({jobs:[record],persist(){if(++writes===4)throw Object.assign(new Error('quota exceeded'),{name:'QuotaExceededError'});},onChange(){},onPersistError(){errors++;},onPersistRecovered(){recoveries++;},client:async()=>({submit:async()=>{submits++;return 'task-'+submits;}})});
 await queue.submit(record,['source'],{});
 assert.equal(submits,1);assert.equal(record.tasks.length,1);assert.equal(record.tasks[0].id,'task-1');
 assert.equal(record.state,'running');assert.equal(record.submissionFailed,true);assert.match(record.error,/存储空间不足/);
 assert.equal(errors,1);assert.ok(record.pendingSubmit);
 assert.equal(queue.save(),true);assert.equal(recoveries,1);
 const persisted=JSON.parse(JSON.stringify([record]));
 assert.equal(reconcileInterruptedSubmissions(persisted),true);
 assert.equal(persisted[0].state,'uncertain');assert.equal(persisted[0].tasks.length,1);assert.equal(persisted[0].pendingSubmit,undefined);
});

test('submission fails closed when the pending marker cannot be persisted',async()=>{
 let submits=0,errors=0;
 const record={id:'unwritable',model:'banana-2',instruction:'edit',count:1,tasks:[]};
 const queue=new TaskQueue({jobs:[],persist(){throw Object.assign(new Error('quota exceeded'),{name:'QuotaExceededError'});},onChange(){},onPersistError(){errors++;},client:async()=>({submit:async()=>{submits++;return 'task-1';}})});
 await queue.submit(record,['source'],{});
 assert.equal(submits,0);assert.equal(record.state,'failed');assert.equal(record.pendingSubmit,undefined);assert.equal(record.submissionFailed,true);assert.match(record.error,/取消提交/);assert.equal(errors,1);
});
