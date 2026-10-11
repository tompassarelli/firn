import * as ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73 from "./firn-host-list-os.mjs";
import * as ffi6e6f64653a6673 from "node:fs";
// Generated from checked Clause canonical executable IR.

function fail(code){throw new Error(code);}
function equal(a,b){
 if(a===b)return true;
 if(a===null||b===null||typeof a!=='object'||typeof b!=='object'||Array.isArray(a)!==Array.isArray(b))return false;
 if(Array.isArray(a))return a.length===b.length&&a.every((v,i)=>equal(v,b[i]));
 const keys=Object.keys(a);return keys.length===Object.keys(b).length&&keys.every(k=>Object.hasOwn(b,k)&&equal(a[k],b[k]));
}
function finite(value){if(typeof value!=='number'||!Number.isFinite(value))fail('NumericDomain');return value===0?0:value;}
function scalarText(value){
 if(typeof value!=='number')return String(value);
 const rendered=String(finite(value));
 if(!rendered.includes('e'))return rendered;
 const negative=rendered.startsWith('-');
 const [mantissa,exponent]=rendered.replace(/^-/, '').split('e');
 const digits=mantissa.replace('.', '');
 const point=(mantissa.includes('.')?mantissa.indexOf('.'):mantissa.length)+Number(exponent);
 const decimal=point<=0?'0.'+'0'.repeat(-point)+digits:point>=digits.length?digits+'0'.repeat(point-digits.length):digits.slice(0,point)+'.'+digits.slice(point);
 return (negative?'-':'')+decimal;
}
function text(value){if(typeof value!=='string'||!value.isWellFormed()||new TextEncoder().encode(value).length>16777216)fail('TextDomain');return value;}
function accepts(value,kind){try{validate(value,kind);return true;}catch{return false;}}
function validate(value,kind){
 switch(kind[0]){
 case 'alternatives':if(!kind[1].some(type=>accepts(value,type)))fail('TypeMismatch');break;
 case 'number':finite(value);break;
 case 'text':text(value);break;
 case 'boolean':if(typeof value!=='boolean')fail('TypeMismatch');break;
 case 'referent':if(value===null||typeof value!=='object'||value.domain!==kind[1]||!Number.isInteger(value.identity)||value.identity<=0||value.identity>4294967295)fail('TypeMismatch');break;
 case 'sequence':if(!Array.isArray(value))fail('TypeMismatch');for(let i=0;i<value.length;i++){if(!Object.hasOwn(value,i))fail('TypeMismatch');validate(value[i],kind[1]);}break;
 case 'dictionary':if(value===null||typeof value!=='object'||Array.isArray(value))fail('TypeMismatch');for(const key of Object.keys(value)){text(key);validate(value[key],kind[1]);}break;
 case 'record':if(value===null||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==kind[1].length)fail('TypeMismatch');for(const [key,type] of kind[1]){if(!Object.hasOwn(value,key))fail('TypeMismatch');validate(value[key],type);}break;
 default:fail('TypeMismatch');
 }
}
function crossing(value,kind){
 validate(value,kind);
 if(kind[0]==='alternatives')return crossing(value,kind[1].find(type=>accepts(value,type)));
 if(kind[0]==='sequence')return Object.freeze(value.map(v=>crossing(v,kind[1])));
 if(kind[0]==='dictionary')return Object.freeze(Object.fromEntries(Object.keys(value).map(key=>[key,crossing(value[key],kind[1])])));
 if(kind[0]==='record')return Object.freeze(Object.fromEntries(kind[1].map(([key,type])=>[key,crossing(value[key],type)])));
 return value;
}
function splitText(value,delimiter){return Object.freeze(delimiter===''?Array.from(value):value.split(delimiter));}
// Rust's Unicode White_Space excludes BOM and includes NEXT LINE, unlike JavaScript \s.
function trimText(value){return value.replace(/^\p{White_Space}+|\p{White_Space}+$/gu,'');}
function firstWord(value){return value.match(/[^\p{White_Space}]+/u)?.[0]??'';}
function remainingWords(value){value=value.replace(/^\p{White_Space}+/u,'');const end=value.search(/\p{White_Space}/u);return end<0?'':value.slice(end).replace(/^\p{White_Space}+/u,'');}
function lowercaseText(value){return text(value.toLowerCase());}
function parseIntegerPrefix(value){const parsed=Number.parseInt(value,10);return Number.isFinite(parsed)?(parsed===0?0:parsed):value;}
function drop(value,count){if(!Number.isFinite(count)||!Number.isInteger(count)||count<0)fail('NumericDomain');return Object.freeze(value.slice(count));}
function integerRange(end){if(!Number.isFinite(end)||!Number.isInteger(end)||end<0)fail('NumericDomain');if(end>65535)fail('ResourceLimit');return Object.freeze(Array.from({length:end},(_,index)=>index));}
function sequenceAt(value,index){if(!Number.isFinite(index)||!Number.isInteger(index)||index<0||index>=value.length)fail('NumericDomain');return value[index];}
function facet(value,domain,members){if(value===null||typeof value!=='object')return undefined;if(value.domain===domain)return value;if(members.includes(value.identity))return Object.freeze({domain,identity:value.identity});return undefined;}
function requireFacet(value,domain,members){const result=facet(value,domain,members);if(result===undefined)fail('TypeMismatch');return result;}
function concatenate(a,b){return text(text(a)+text(b));}
function add(a,b){return finite(finite(a)+finite(b));}
function subtract(a,b){return finite(finite(a)-finite(b));}
function multiply(a,b){return finite(finite(a)*finite(b));}
function divide(a,b){return finite(finite(a)/finite(b));}
function greater(a,b){return finite(a)>finite(b);}
function lessEqual(a,b){return finite(a)<=finite(b);}
function startsWith(a,b){return text(a).startsWith(text(b));}
function containsText(a,b){return text(a).includes(text(b));}
function row(table,subject){return table.rows.find(([key])=>equal(key,subject))?.[1];}
function present(table,subject){validate(subject,['referent',table.domain]);return row(table,subject)!==undefined;}
function readOne(table,subject){const values=row(table,subject);if(values?.length!==1)fail('MissingState');return values[0];}
function stage(pending,pre,slot,mode,subject,value){
 const table=pre[slot];validate(subject,['referent',table.domain]);validate(value,table.kind);
 if(table.cardinality==='many'){
  if(mode!==1&&mode!==2)fail('TypeMismatch');
 }else if(mode===1)fail('TypeMismatch');
 if(pending.some(effect=>effect.slot===slot&&equal(effect.subject,subject)&&(table.cardinality!=='many'||equal(effect.value,value))))fail('ConflictingStateEffects');
 pending.push({slot,mode,subject,value});
}
function commit(pre,pending){
 const next=pre.map(table=>({...table,rows:table.rows.map(([subject,values])=>[subject,[...values]])}));
 for(const {slot,mode,subject,value} of pending){
  const table=next[slot];let index=table.rows.findIndex(([key])=>equal(key,subject));
  if(mode===0){if(index<0)table.rows.push([subject,[value]]);else table.rows[index]=[subject,[value]];}
  else if(mode===1){if(index<0)table.rows.push([subject,[value]]);else if(!table.rows[index][1].some(prior=>equal(prior,value)))table.rows[index][1].push(value);}
  else{
   if(index<0)fail('MissingState');
   const values=table.rows[index][1];const at=values.findIndex(prior=>equal(prior,value));
   if(at<0)fail('MissingState');values.splice(at,1);if(values.length===0)table.rows.splice(index,1);
  }
 }
 validateContracts(next);return next;
}
function validateContracts(tables){
 const participants=[];
 for(const table of tables)for(const [subject,values] of table.rows){participants.push(subject);if(table.kind[0]==='referent')participants.push(...values);}
 for(const table of tables)if(table.total){if(table.cardinality!=='one')fail('TypeMismatch');for(const subject of participants)if(subject.domain===table.domain&&row(table,subject)?.length!==1)fail('MissingState');}
}

function callable0(...args){
if(args.length!==1)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
const result=crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["listDirectory"])(args[0]),["record",[["names",["sequence",["text"]]],["status",["number"]]]]);
validate(result,["record",[["names",["sequence",["text"]]],["status",["number"]]]]);
return result;
}
function callable1(...args){
if(args.length!==1)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
const result=crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["pathKind"])(args[0]),["record",[["kind",["number"]],["status",["number"]]]]);
validate(result,["record",[["kind",["number"]],["status",["number"]]]]);
return result;
}
function callable2(...args){
if(args.length!==2)fail("ArgumentCount");
args[0]=crossing(args[0],["number"]);
args[1]=crossing(args[1],["text"]);
const result=crossing((0,ffi6e6f64653a6673["writeSync"])(args[0],args[1]),["number"]);
validate(result,["number"]);
return result;
}
function callable3(...args){
if(args.length!==0)fail("ArgumentCount");
const result=Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]]));
validate(result,["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
return result;
}
function callable4(...args){
if(args.length!==3)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
args[1]=crossing(args[1],["text"]);
args[2]=crossing(args[2],["number"]);
const result=concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(args[0]))," '"),scalarText(args[1])),"': errno "),scalarText(args[2])),"\n");
validate(result,["text"]);
return result;
}
function callable5(...args){
if(args.length!==3)fail("ArgumentCount");
args[0]=crossing(args[0],["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
args[1]=crossing(args[1],["text"]);
args[2]=crossing(args[2],["record",[["kind",["number"]],["status",["number"]]]]);
const result=(equal(args[2]["status"],0)?(equal(args[2]["kind"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([...(args[0]["names"]),(args[1])])]])):args[0]):(equal(args[2]["status"],2)?args[0]:Object.freeze(Object.fromEntries([["error",((b2)=>(((b3)=>(((b4)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b2))," '"),scalarText(b3)),"': errno "),scalarText(b4)),"\n")))(args[2]["status"])))(concatenate(concatenate("hosts/",scalarText(args[1])),""))))("cannot inspect")],["names",args[0]["names"]]]))));
validate(result,["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
return result;
}
function callable6(...args){
if(args.length!==3)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
args[1]=crossing(args[1],["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
args[2]=crossing(args[2],["text"]);
const result=(equal(args[1]["error"],"")?((b7)=>(((b8)=>(((b9)=>((equal(b9["status"],0)?(equal(b9["kind"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([...(b7["names"]),(b8)])]])):b7):(equal(b9["status"],2)?b7:Object.freeze(Object.fromEntries([["error",((b10)=>(((b11)=>(((b12)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b10))," '"),scalarText(b11)),"': errno "),scalarText(b12)),"\n")))(b9["status"])))(concatenate(concatenate("hosts/",scalarText(b8)),""))))("cannot inspect")],["names",b7["names"]]]))))))(((b6)=>(crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["pathKind"])(b6),["record",[["kind",["number"]],["status",["number"]]]])))(concatenate(concatenate(concatenate(concatenate("",scalarText(args[0])),"/hosts/"),scalarText(args[2])),"")))))(args[2])))(args[1]):args[1]);
validate(result,["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
return result;
}
function callable7(...args){
if(args.length!==2)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
args[1]=crossing(args[1],["sequence",["text"]]);
const result=((xs,initial)=>{let b14=initial;for(const b15 of xs){b14=(((b16)=>(((b17)=>(((b18)=>((equal(b17["error"],"")?((b19)=>(((b20)=>(((b22)=>((equal(b22["status"],0)?(equal(b22["kind"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([...(b19["names"]),(b20)])]])):b19):(equal(b22["status"],2)?b19:Object.freeze(Object.fromEntries([["error",((b23)=>(((b24)=>(((b25)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b23))," '"),scalarText(b24)),"': errno "),scalarText(b25)),"\n")))(b22["status"])))(concatenate(concatenate("hosts/",scalarText(b20)),""))))("cannot inspect")],["names",b19["names"]]]))))))(((b21)=>(crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["pathKind"])(b21),["record",[["kind",["number"]],["status",["number"]]]])))(concatenate(concatenate(concatenate(concatenate("",scalarText(b16)),"/hosts/"),scalarText(b18)),"")))))(b18)))(b17):b17)))(b15)))(b14)))(args[0]));}return b14;})((args[1]),(Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]]))));
validate(result,["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
return result;
}
function callable8(...args){
if(args.length!==2)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
args[1]=crossing(args[1],["record",[["names",["sequence",["text"]]],["status",["number"]]]]);
const result=(equal(args[1]["status"],0)?(greater((args[1]["names"]).length,16384)?Object.freeze(Object.fromEntries([["error",((b27)=>(((b28)=>(((b29)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b27))," '"),scalarText(b28)),"': errno "),scalarText(b29)),"\n")))(27)))("hosts")))("cannot list")],["names",Object.freeze([])]])):((b30)=>(((b31)=>(((xs,initial)=>{let b32=initial;for(const b33 of xs){b32=(((b34)=>(((b35)=>(((b36)=>((equal(b35["error"],"")?((b37)=>(((b38)=>(((b40)=>((equal(b40["status"],0)?(equal(b40["kind"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([...(b37["names"]),(b38)])]])):b37):(equal(b40["status"],2)?b37:Object.freeze(Object.fromEntries([["error",((b41)=>(((b42)=>(((b43)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b41))," '"),scalarText(b42)),"': errno "),scalarText(b43)),"\n")))(b40["status"])))(concatenate(concatenate("hosts/",scalarText(b38)),""))))("cannot inspect")],["names",b37["names"]]]))))))(((b39)=>(crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["pathKind"])(b39),["record",[["kind",["number"]],["status",["number"]]]])))(concatenate(concatenate(concatenate(concatenate("",scalarText(b34)),"/hosts/"),scalarText(b36)),"")))))(b36)))(b35):b35)))(b33)))(b32)))(b30));}return b32;})((b31),(Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]]))))))(args[1]["names"])))(args[0])):(equal(args[1]["status"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]])):Object.freeze(Object.fromEntries([["error",((b44)=>(((b45)=>(((b46)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b44))," '"),scalarText(b45)),"': errno "),scalarText(b46)),"\n")))(args[1]["status"])))("hosts")))("cannot list")],["names",Object.freeze([])]]))));
validate(result,["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
return result;
}
function callable9(...args){
if(args.length!==1)fail("ArgumentCount");
args[0]=crossing(args[0],["sequence",["text"]]);
const result=concatenate(concatenate(concatenate(concatenate("Hosts (",scalarText((args[0]).length)),"):\n"),scalarText(text((Object.freeze((args[0]).map((b48)=>(concatenate(concatenate("  ",scalarText(b48)),"\n"))))).join("")))),"");
validate(result,["text"]);
return result;
}
function callable10(...args){
if(args.length!==1)fail("ArgumentCount");
args[0]=crossing(args[0],["record",[["error",["text"]],["names",["sequence",["text"]]]]]);
const result=(equal(args[0]["error"],"")?Object.freeze(Object.fromEntries([["error",""],["output",((b50)=>(concatenate(concatenate(concatenate(concatenate("Hosts (",scalarText((b50).length)),"):\n"),scalarText(text((Object.freeze((b50).map((b51)=>(concatenate(concatenate("  ",scalarText(b51)),"\n"))))).join("")))),"")))(Object.freeze([...(args[0]["names"])].sort()))],["status",0]])):Object.freeze(Object.fromEntries([["error",args[0]["error"]],["output",""],["status",1]])));
validate(result,["record",[["error",["text"]],["output",["text"]],["status",["number"]]]]);
return result;
}
function callable11(...args){
if(args.length!==1)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
const result=((b76)=>((equal(b76["error"],"")?Object.freeze(Object.fromEntries([["error",""],["output",((b77)=>(concatenate(concatenate(concatenate(concatenate("Hosts (",scalarText((b77).length)),"):\n"),scalarText(text((Object.freeze((b77).map((b78)=>(concatenate(concatenate("  ",scalarText(b78)),"\n"))))).join("")))),"")))(Object.freeze([...(b76["names"])].sort()))],["status",0]])):Object.freeze(Object.fromEntries([["error",b76["error"]],["output",""],["status",1]])))))(((b54)=>(((b55)=>((equal(b55["status"],0)?(greater((b55["names"]).length,16384)?Object.freeze(Object.fromEntries([["error",((b56)=>(((b57)=>(((b58)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b56))," '"),scalarText(b57)),"': errno "),scalarText(b58)),"\n")))(27)))("hosts")))("cannot list")],["names",Object.freeze([])]])):((b59)=>(((b60)=>(((xs,initial)=>{let b61=initial;for(const b62 of xs){b61=(((b63)=>(((b64)=>(((b65)=>((equal(b64["error"],"")?((b66)=>(((b67)=>(((b69)=>((equal(b69["status"],0)?(equal(b69["kind"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([...(b66["names"]),(b67)])]])):b66):(equal(b69["status"],2)?b66:Object.freeze(Object.fromEntries([["error",((b70)=>(((b71)=>(((b72)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b70))," '"),scalarText(b71)),"': errno "),scalarText(b72)),"\n")))(b69["status"])))(concatenate(concatenate("hosts/",scalarText(b67)),""))))("cannot inspect")],["names",b66["names"]]]))))))(((b68)=>(crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["pathKind"])(b68),["record",[["kind",["number"]],["status",["number"]]]])))(concatenate(concatenate(concatenate(concatenate("",scalarText(b63)),"/hosts/"),scalarText(b65)),"")))))(b65)))(b64):b64)))(b62)))(b61)))(b59));}return b61;})((b60),(Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]]))))))(b55["names"])))(b54)):(equal(b55["status"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]])):Object.freeze(Object.fromEntries([["error",((b73)=>(((b74)=>(((b75)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b73))," '"),scalarText(b74)),"': errno "),scalarText(b75)),"\n")))(b55["status"])))("hosts")))("cannot list")],["names",Object.freeze([])]]))))))(((b53)=>(crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["listDirectory"])(b53),["record",[["names",["sequence",["text"]]],["status",["number"]]]])))(concatenate(concatenate("",scalarText(args[0])),"/hosts")))))(args[0]));
validate(result,["record",[["error",["text"]],["output",["text"]],["status",["number"]]]]);
return result;
}
export { callable11 as "host-list" };
function callable12(...args){
if(args.length!==1)fail("ArgumentCount");
args[0]=crossing(args[0],["record",[["error",["text"]],["output",["text"]],["status",["number"]]]]);
const result=((b82)=>(((b85)=>(args[0]["status"]))(((b83)=>(((b84)=>(crossing((0,ffi6e6f64653a6673["writeSync"])(b83,b84),["number"])))(args[0]["error"])))(2))))(((b80)=>(((b81)=>(crossing((0,ffi6e6f64653a6673["writeSync"])(b80,b81),["number"])))(args[0]["output"])))(1));
validate(result,["number"]);
return result;
}
function callable13(...args){
if(args.length!==1)fail("ArgumentCount");
args[0]=crossing(args[0],["sequence",["text"]]);
const result=(equal(args[0],Object.freeze(["host","list"]))?true:equal(args[0],Object.freeze(["host","list","all"])));
validate(result,["boolean"]);
return result;
}
export { callable13 as "handles" };
function callable14(...args){
if(args.length!==2)fail("ArgumentCount");
args[0]=crossing(args[0],["text"]);
args[1]=crossing(args[1],["sequence",["text"]]);
const result=((b116)=>(((b119)=>(((b122)=>(b116["status"]))(((b120)=>(((b121)=>(crossing((0,ffi6e6f64653a6673["writeSync"])(b120,b121),["number"])))(b116["error"])))(2))))(((b117)=>(((b118)=>(crossing((0,ffi6e6f64653a6673["writeSync"])(b117,b118),["number"])))(b116["output"])))(1))))((((b88)=>((equal(b88,Object.freeze(["host","list"]))?true:equal(b88,Object.freeze(["host","list","all"])))))(args[1])?((b89)=>(((b113)=>((equal(b113["error"],"")?Object.freeze(Object.fromEntries([["error",""],["output",((b114)=>(concatenate(concatenate(concatenate(concatenate("Hosts (",scalarText((b114).length)),"):\n"),scalarText(text((Object.freeze((b114).map((b115)=>(concatenate(concatenate("  ",scalarText(b115)),"\n"))))).join("")))),"")))(Object.freeze([...(b113["names"])].sort()))],["status",0]])):Object.freeze(Object.fromEntries([["error",b113["error"]],["output",""],["status",1]])))))(((b90)=>(((b92)=>((equal(b92["status"],0)?(greater((b92["names"]).length,16384)?Object.freeze(Object.fromEntries([["error",((b93)=>(((b94)=>(((b95)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b93))," '"),scalarText(b94)),"': errno "),scalarText(b95)),"\n")))(27)))("hosts")))("cannot list")],["names",Object.freeze([])]])):((b96)=>(((b97)=>(((xs,initial)=>{let b98=initial;for(const b99 of xs){b98=(((b100)=>(((b101)=>(((b102)=>((equal(b101["error"],"")?((b103)=>(((b104)=>(((b106)=>((equal(b106["status"],0)?(equal(b106["kind"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([...(b103["names"]),(b104)])]])):b103):(equal(b106["status"],2)?b103:Object.freeze(Object.fromEntries([["error",((b107)=>(((b108)=>(((b109)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b107))," '"),scalarText(b108)),"': errno "),scalarText(b109)),"\n")))(b106["status"])))(concatenate(concatenate("hosts/",scalarText(b104)),""))))("cannot inspect")],["names",b103["names"]]]))))))(((b105)=>(crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["pathKind"])(b105),["record",[["kind",["number"]],["status",["number"]]]])))(concatenate(concatenate(concatenate(concatenate("",scalarText(b100)),"/hosts/"),scalarText(b102)),"")))))(b102)))(b101):b101)))(b99)))(b98)))(b96));}return b98;})((b97),(Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]]))))))(b92["names"])))(b90)):(equal(b92["status"],2)?Object.freeze(Object.fromEntries([["error",""],["names",Object.freeze([])]])):Object.freeze(Object.fromEntries([["error",((b110)=>(((b111)=>(((b112)=>(concatenate(concatenate(concatenate(concatenate(concatenate(concatenate("firn host list: ",scalarText(b110))," '"),scalarText(b111)),"': errno "),scalarText(b112)),"\n")))(b92["status"])))("hosts")))("cannot list")],["names",Object.freeze([])]]))))))(((b91)=>(crossing((0,ffi2e2f6669726e2d686f73742d6c6973742d6f732e6d6a73["listDirectory"])(b91),["record",[["names",["sequence",["text"]]],["status",["number"]]]])))(concatenate(concatenate("",scalarText(b89)),"/hosts")))))(b89))))(args[0]):Object.freeze(Object.fromEntries([["error","Usage: firn host list [all]\n"],["output",""],["status",64]]))));
validate(result,["number"]);
return result;
}
export { callable14 as "run" };
