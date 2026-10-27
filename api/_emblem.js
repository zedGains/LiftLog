// Generated from index.html by tools/build_emblem.py — don't edit by hand.
const esc=(t)=>String(t).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const RANKS=[["Bronze",0,"#9A5B2C","#E7B07F"],["Silver",15,"#76818F","#E4E9EF"],["Gold",40,"#B07F0C","#F8DA7A"],["Platinum",80,"#22887B","#A6EEDF"],["Diamond",130,"#2563D6","#AED6FF"],["Master",190,"#6D35C8","#D8BDFF"],["Champion",260,"#B71C1C","#FFC857"]];
function rankInfo(pts){pts=Math.max(0,Math.round(pts||0));let i=RANKS.length-1;while(i>0&&pts<RANKS[i][1])i--;
  const [name,min,c1,c2]=RANKS[i],nx=RANKS[i+1];
  if(!nx)return {i,name,full:name,div:"",pts,c1,c2,into:1,need:1,toNext:0,nextName:null};
  const span=(nx[1]-min)/3,d=Math.min(2,Math.floor((pts-min)/span)),lo=min+d*span,hi=min+(d+1)*span;
  const div=["III","II","I"][d],nextName=d<2?`${name} ${["III","II","I"][d+1]}`:`${nx[0]} III`;
  return {i,name,div,full:`${name} ${div}`,pts,c1,c2,into:pts-lo,need:hi-lo,toNext:Math.ceil(hi-pts),nextName}}
function crestBlades(n,len,R,cx,cy,from,step,fill){let s="";for(let k=0;k<n;k++){const a=from-k*step,L=len-k*3.2,w=4.6-k*.35;
  [1,-1].forEach(sd=>{const ang=sd>0?a:180-a,rad=ang*Math.PI/180,x=cx+R*Math.cos(rad),y=cy+R*Math.sin(rad);
   s+=`<path d="M0 ${-w}Q${L*.55} ${-w*1.3} ${L} 0Q${L*.55} ${w*1.3} 0 ${w}z" transform="translate(${x.toFixed(1)} ${y.toFixed(1)}) rotate(${ang.toFixed(1)})" ${fill}/>`})}return s}
let rfN=0;
function rankFrame(r,o,cls){o=o||{};const id="rf"+(++rfN),i=r.i||0,P=RANKS[i]||RANKS[0],c1=P[2],c2=P[3],cx=60,cy=58,R=30;
  const g=`fill="url(#${id}g)"`,blades=[1,2,3,3,4,4,5][i],len=[12,15,18,21,23,26,29][i];
  const back=crestBlades(blades,len,R+1,cx,cy,i>=5?-8:4,i>=5?24:26,`${g} stroke="${c1}" stroke-width="1"`)+
    (i>=1?`<path d="M${cx-14} ${cy+R-4}L${cx} ${cy+R+14+i}L${cx+14} ${cy+R-4}z" ${g} stroke="${c1}" stroke-width="1.2" stroke-linejoin="round"/>`:"")+
    (i>=2?`<path d="M${cx-9} ${cy-R+3}L${cx} ${cy-R-10-i*1.5}L${cx+9} ${cy-R+3}z" ${g} stroke="${c1}" stroke-width="1.2" stroke-linejoin="round"/>`:"")+
    (i>=4?`<path d="M${cx-20} ${cy-R+6}L${cx-17} ${cy-R-8-i}L${cx-8} ${cy-R-1}L${cx} ${cy-R-14-i*1.5}L${cx+8} ${cy-R-1}L${cx+17} ${cy-R-8-i}L${cx+20} ${cy-R+6}z" ${g} stroke="${c1}" stroke-width="1.3" stroke-linejoin="round"/>`:"");
  const gemTop=i>=2?`<path d="M${cx} ${cy-R-(i>=4?9+i*1.5:5+i)}l3.2 4-3.2 4-3.2-4z" fill="#fff" opacity=".9"/>`:"";
  const pips=r.div?["III","II","I"].indexOf(r.div)+1:0;
  const pipS=Array.from({length:pips},(_,k)=>`<path d="M${cx+(k-(pips-1)/2)*8} ${cy+R+3}l3 3.5-3 3.5-3-3.5z" fill="#fff" stroke="${c1}" stroke-width=".8"/>`).join("");
  const inner=o.img?`<clipPath id="${id}c"><circle cx="${cx}" cy="${cy}" r="${R-4}"/></clipPath><image href="${esc(o.img)}" x="${cx-R+4}" y="${cy-R+4}" width="${2*R-8}" height="${2*R-8}" clip-path="url(#${id}c)" preserveAspectRatio="xMidYMid slice"/>`:o.ini!=null?`<circle cx="${cx}" cy="${cy}" r="${R-5}" fill="url(#${id}d)"/><text x="${cx}" y="${cy+8}" text-anchor="middle" font-size="${o.ini.length>1?21:24}" font-weight="800" fill="#fff" >${esc(o.ini)}</text>`
    :`<circle cx="${cx}" cy="${cy}" r="${R-5}" fill="url(#${id}d)"/><path d="M${cx} ${cy-14}L${cx+11} ${cy-2}L${cx} ${cy+15}L${cx-11} ${cy-2}z" fill="url(#${id}g)" stroke="#fff" stroke-opacity=".7" stroke-width="1.5"/><path d="M${cx-11} ${cy-2}H${cx+11}M${cx} ${cy-14}V${cy+15}" stroke="#fff" stroke-opacity=".35" stroke-width="1"/>`;
  return `<svg class="rframe ${cls||""}" viewBox="0 -8 120 124" role="img" aria-label="${esc(r.full||P[0])}"><defs>
   <linearGradient id="${id}g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c2}"/><stop offset="1" stop-color="${c1}"/></linearGradient>
   <radialGradient id="${id}d" cx=".5" cy=".4" r=".7"><stop offset="0" stop-color="${c1}"/><stop offset="1" stop-color="#11151b"/></radialGradient></defs>
   ${back}<circle cx="${cx}" cy="${cy}" r="${R}" ${g} stroke="${c1}" stroke-width="1.5"/>${inner}<circle cx="${cx}" cy="${cy}" r="${R-5}" fill="none" stroke="${c2}" stroke-width="1.5" opacity=".8"/>${gemTop}${pipS}</svg>`}
const HPLUME=["#C2410C","#3B82F6","#DC2626","#14B8A6","#8B5CF6","#EC4899","#F59E0B"];
let hmN=0;
function helmEmblem(r,cls){const id="hm"+(++hmN),i=r.i||0,P=RANKS[i]||RANKS[0],c1=P[2],c2=P[3],pl=HPLUME[i];
  const metal=`fill="url(#${id}m)"`,edge=`stroke="${c1}" stroke-width="2" stroke-linejoin="round"`;
  const wing=(n,len,sd)=>{let s="";for(let k=0;k<n;k++){const L=len-k*5,x=sd>0?96:24,y=60-k*4;
    s+=`<path d="M0 -6Q${L*.5} -10 ${L} 0Q${L*.5} 8 0 6z" transform="translate(${x} ${y}) rotate(${sd>0?-12-k*22:180+12+k*22})" ${metal} ${edge}/>`}return s};
  const wings=i>=2?wing(i>=6?5:i>=4?4:3,[0,0,28,32,36,38,42][i],1)+wing(i>=6?5:i>=4?4:3,[0,0,28,32,36,38,42][i],-1):"";
  const horns=i>=5?`<path d="M32 42C16 36 8 20 12 2C18 18 26 26 40 30Z" ${metal} ${edge}/><path d="M88 42C104 36 112 20 108 2C102 18 94 26 80 30Z" ${metal} ${edge}/>`:"";
  const crown=i>=4?`<path d="M36 30L40 4L50 18L60 -6L70 18L80 4L84 30Z" ${metal} ${edge}/>`:"";
  const halo=i>=6?`<circle cx="60" cy="58" r="56" fill="none" stroke="${c2}" stroke-width="2" opacity=".5"/><circle cx="60" cy="58" r="50" fill="url(#${id}h)"/>`:"";
  const plate=i>=1?`<path d="M60 0L102 16V66C102 96 84 116 60 128C36 116 18 96 18 66V16Z" fill="url(#${id}b)" stroke="${c2}" stroke-width="2" stroke-opacity=".7"/><path d="M60 8L95 21V66C95 91 80 108 60 119C40 108 25 91 25 66V21Z" fill="none" stroke="${c1}" stroke-width="1.5" opacity=".9"/>`:"";
  const ridge=`<path d="M60 20V44" stroke="${c2}" stroke-width="4" stroke-linecap="round" opacity=".55"/>`;
  const cheeks=`<path d="M26 72C30 70 40 70 46 72V112C38 110 30 104 27 96Z" fill="rgba(0,0,0,.18)"/><path d="M94 72C90 70 80 70 74 72V112C82 110 90 104 93 96Z" fill="rgba(0,0,0,.25)"/>`;
  const trim=`<path d="M23 88C23 102 32 110 44 114L50 116M97 88C97 102 88 110 76 114L70 116" fill="none" stroke="${c2}" stroke-width="2.5" stroke-linecap="round" opacity=".8"/>`;
  const plume=`<path d="M52 26C50 10 54 -2 60 ${i>=3?-12:-6}C66 -2 70 10 68 26Z" fill="url(#${id}p)" stroke="${c1}" stroke-width="1.5"/>`;
  const shell=`<path d="M60 20C85 20 97 40 97 64V90C97 102 88 110 76 114L70 116V96L64 90H56L50 96V116L44 114C32 110 23 102 23 90V64C23 40 35 20 60 20Z" ${metal} ${edge}/>`;
  const face=`<path d="M36 56H84V63C84 66 80 68 76 68H66V93L60 99L54 93V68H44C40 68 36 66 36 63Z" fill="url(#${id}f)"/>`;
  const brow=i>=1?`<path d="M28 50C44 42 76 42 92 50" fill="none" stroke="${c2}" stroke-width="3" stroke-linecap="round" opacity=".9"/>${[34,47,60,73,86].map(x=>`<circle cx="${x}" cy="${x===60?44.5:x===47||x===73?45.5:48}" r="1.8" fill="${c2}"/>`).join("")}`:"";
  const gem=i>=3?`<path d="M60 28l6 7-6 7-6-7z" fill="${pl}" stroke="#fff" stroke-width="1.2"/>`:"";
  const shine=`<path d="M40 30C34 38 31 50 31 62" stroke="rgba(255,255,255,.45)" stroke-width="3" fill="none" stroke-linecap="round"/>`;
  const pips=r.div?["III","II","I"].indexOf(r.div)+1:0;
  const pipS=Array.from({length:pips},(_,k)=>`<path d="M${60+(k-(pips-1)/2)*10} 126l4 5-4 5-4-5z" fill="${c2}" stroke="${c1}" stroke-width="1"/>`).join("");
  return `<svg class="helm ${cls||""}" viewBox="-14 -18 148 156" role="img" aria-label="${esc(r.full||P[0])}"><defs>
   <linearGradient id="${id}m" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${c2}"/><stop offset=".5" stop-color="${c1}"/><stop offset="1" stop-color="#1a1d24"/></linearGradient>
   <linearGradient id="${id}p" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".9"/><stop offset=".25" stop-color="${pl}"/><stop offset="1" stop-color="${pl}" stop-opacity=".85"/></linearGradient>
   <linearGradient id="${id}f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#05070a"/><stop offset="1" stop-color="#1c2230"/></linearGradient>
   <linearGradient id="${id}b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c1}" stop-opacity=".95"/><stop offset="1" stop-color="#0d1015"/></linearGradient><radialGradient id="${id}h"><stop offset="0" stop-color="${c2}" stop-opacity=".35"/><stop offset="1" stop-color="${c2}" stop-opacity="0"/></radialGradient></defs>
   ${halo}${plate}${wings}${horns}${crown}${plume}${shell}${ridge}${cheeks}${face}${trim}${brow}${gem}${shine}${pipS}</svg>`}
function initialsOf(nm){return String(nm||"").split(/\s+/).map(w=>w[0]||"").join("").slice(0,2).toUpperCase()||"?"}

export {RANKS,rankInfo,rankFrame,helmEmblem,initialsOf,esc};
