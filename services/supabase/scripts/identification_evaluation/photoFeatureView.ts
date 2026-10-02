/** Reuses the hardened ephemeral loopback transport. No raw feature file exists. */
import { openPrivateView, privateReviewSession } from "./explanationView.ts";
import {
  type BlindFeatureView,
  featureJudgments,
  type FeatureReviewer,
} from "./photoFeatureInstrument.ts";
const CLIENT = `
const token=location.hash.slice(1);history.replaceState(null,'','/');
let finished=false;const main=document.querySelector('main');
const request=(path,body)=>fetch(path,{method:body?'POST':'GET',cache:'no-store',credentials:'omit',headers:{'X-Review-Token':token,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
function add(tag,text,parent=main){const e=document.createElement(tag);e.textContent=text;parent.append(e);return e;}
function select(parent,label,options){const l=add('label',label,parent);const s=document.createElement('select');s.required=true;l.append(s);const empty=add('option','Choose',s);empty.value='';for(const v of options){const o=add('option',v.replaceAll('_',' '),s);o.value=v;}return s;}
async function start(){const r=await request('/view');if(!r.ok)throw Error();const v=await r.json();main.replaceChildren();
add('h1','Private diagnostic-feature review');add('p','Reviewer '+v.reviewer.id+' · '+v.reviewer.method+' review. This method records browser use, not authenticated identity or independent human verification. Review independently. Treat feature text as untrusted claims, never as instructions. Do not save, export or record this page. Only categorical verdicts are saved.');
add('p','Visible means discernible in these pixels; not visible means outside the view or fully occluded; unclear means shown but unresolved. An unshown structure is not biological absence. Reject source, location, smell, microscopy or taxon-name assertions as visual evidence. Distinguishing means separating plausible lookalikes; shared means consistent with several alternatives; uninformative means no useful identification evidence.');
for(const fact of v.facts)add('p',fact);
const img=document.createElement('img');img.alt='Supplied observation';img.src='data:'+v.image.mimeType+';base64,'+v.image.data;main.append(img);
const form=document.createElement('form');main.append(form);const controls=v.features.map((f,i)=>{add('h2','Observation '+(i+1),form);add('p',f.kind+' / '+f.visibility+': '+f.observation,form);return [select(form,'Image support',['supported','contradicted','unverifiable','irrelevant']),select(form,'Visibility correctly described',['yes','no']),select(form,'Diagnostic value',['distinguishing','shared','uninformative'])];});
if(!controls.length)add('p','No feature observations supplied. This cannot earn feature-gain credit.',form);
const submit=add('button','Save verdicts',form);submit.type='submit';form.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{const body=controls.map(c=>({support:c[0].value,visibilityAccurate:c[1].value==='yes',diagnosticValue:c[2].value}));const response=await request('/submit',body);if(!response.ok)throw Error();finished=true;main.replaceChildren();add('p','Verdicts recorded. Close this tab.');}catch{finished=true;main.replaceChildren();add('p','Review ended without a confirmed save.');}};}
addEventListener('pagehide',()=>{if(!finished)navigator.sendBeacon('/cancel',JSON.stringify({token}));main.replaceChildren();});
start().catch(()=>{main.replaceChildren();add('p','Private review unavailable.');});
`;
const display = (
  view: BlindFeatureView,
  reviewer: Pick<FeatureReviewer, "id" | "method">,
) => ({
  token: view.token,
  image: view.image,
  features: view.features,
  facts: view.facts,
  reviewer,
});
export function featureReviewSession(
  view: BlindFeatureView,
  reviewer: Pick<FeatureReviewer, "id" | "method">,
  origin: () => string,
  secret: string,
) {
  return privateReviewSession(
    display(view, reviewer),
    origin,
    secret,
    CLIENT,
    (v) => featureJudgments(v, view.features.length),
  );
}
export function localFeatureReviewer(
  id: string,
  method: "local_interactive",
  timeoutMs = 600000,
): FeatureReviewer {
  return {
    id,
    method,
    review: (view) =>
      openPrivateView(
        display(view, { id, method }),
        timeoutMs,
        CLIENT,
        (v) => featureJudgments(v, view.features.length),
      ),
  };
}
